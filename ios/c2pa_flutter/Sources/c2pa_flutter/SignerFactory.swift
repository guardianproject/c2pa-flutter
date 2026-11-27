/*
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

import C2PA
import Flutter
import Foundation
import Security

/// Calls Dart through the Pigeon `C2paFlutterApi` on the main thread. Callback
/// signers and HTTP resolvers run synchronously on the thread performing a
/// C2PA operation, so they wait here for Dart's answer.
final class DartBridge: @unchecked Sendable {
    /// Set once in `register`, before any call can arrive.
    var api: C2paFlutterApi?

    private final class Box<T>: @unchecked Sendable {
        var result: Result<T, PigeonError>?
    }

    func sign(callbackId: String, data: Data) throws -> Data {
        try call("sign") { api, done in
            api.sign(callbackId: callbackId, data: FlutterStandardTypedData(bytes: data)) { done($0) }
        }.data
    }

    func resolveHttp(contextHandle: Int64, request: HttpRequestMessage) throws -> HttpResponseMessage {
        try call("resolveHttp") { api, done in
            api.resolveHttp(contextHandle: contextHandle, request: request) { done($0) }
        }
    }

    /// Fire-and-forget progress notification.
    func progress(contextHandle: Int64, phase: String, step: Int64, total: Int64) {
        DispatchQueue.main.async { [weak self] in
            self?.api?.progress(contextHandle: contextHandle, phase: phase, step: step, total: total) { _ in }
        }
    }

    private func call<T>(
        _ name: String,
        _ invoke: @escaping (C2paFlutterApi, @escaping (Result<T, PigeonError>) -> Void) -> Void
    ) throws -> T {
        if Thread.isMainThread {
            throw C2PAError.api("\(name) must not be called on the main thread")
        }
        guard let api = api else {
            throw C2PAError.api("\(name): the Flutter engine is detached")
        }
        let box = Box<T>()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            invoke(api) { result in
                box.result = result
                semaphore.signal()
            }
        }
        semaphore.wait()
        switch box.result {
        case .success(let value)?:
            return value
        case .failure(let error)?:
            throw C2PAError.api("\(name) failed in Dart: \(error.message ?? error.code)")
        case nil:
            throw C2PAError.api("\(name) returned no result")
        }
    }
}

/// Builds c2pa-swift `Signer`s from the signer messages Dart sends.
///
/// Call only from the plugin's worker queue: remote signers wait for a
/// network round trip and callback signers wait for Dart.
final class SignerFactory {
    private let bridge: DartBridge

    init(bridge: DartBridge) {
        self.bridge = bridge
    }

    func create(_ message: SignerMessage) throws -> Signer {
        switch message {
        case let pem as PemSignerMessage:
            return try Signer(
                certsPEM: pem.certificatePem,
                privateKeyPEM: pem.privateKeyPem,
                algorithm: pem.algorithm.sdk,
                tsa: tsaURL(pem.tsaUrl)
            )
        case let keystore as KeystoreSignerMessage:
            return try Signer(
                algorithm: keystore.algorithm.sdk,
                certificateChainPEM: keystore.certificateChainPem,
                tsa: tsaURL(keystore.tsaUrl),
                keychainKeyTag: keystore.keyAlias
            )
        case let hardware as HardwareSignerMessage:
            var accessControl: SecAccessControlCreateFlags = [.privateKeyUsage]
            if hardware.requireUserAuthentication {
                accessControl.insert(.biometryCurrentSet)
            }
            return try Signer(
                algorithm: .es256,
                certificateChainPEM: hardware.certificateChainPem,
                tsa: tsaURL(hardware.tsaUrl),
                secureEnclaveConfig: SecureEnclaveSignerConfig(
                    keyTag: hardware.keyAlias,
                    accessControl: accessControl
                )
            )
        case let callback as CallbackSignerMessage:
            return try createCallback(callback)
        case let remote as RemoteSignerMessage:
            return try createRemote(remote)
        case let cawg as CawgIdentitySignerMessage:
            return try Signer.withCawgIdentity(
                try create(cawg.claimSigner),
                identity: try create(cawg.identitySigner),
                referencedAssertions: cawg.referencedAssertions,
                roles: cawg.roles
            )
        case is SettingsSignerMessage:
            throw PluginError.invalidArgument(
                "A SettingsSigner is not a standalone signer. Put the signer in the settings of a " +
                    "C2paContext and sign without passing a signer, or use C2pa.signBytes/signFile."
            )
        default:
            throw PluginError.invalidArgument("Unknown signer type: \(type(of: message))")
        }
    }

    private func tsaURL(_ value: String?) -> URL? {
        value.flatMap(URL.init(string:))
    }

    private func createCallback(_ message: CallbackSignerMessage) throws -> Signer {
        let callbackId = message.callbackId
        let bridge = self.bridge
        return try Signer(
            algorithm: message.algorithm.sdk,
            certificateChainPEM: message.certificateChainPem,
            tsa: tsaURL(message.tsaUrl)
        ) { @Sendable dataToSign in
            try bridge.sign(callbackId: callbackId, data: dataToSign)
        }
    }

    private final class SignerBox: @unchecked Sendable {
        var result: Result<Signer, Error>?
    }

    private func createRemote(_ message: RemoteSignerMessage) throws -> Signer {
        guard let endpoint = URL(string: message.configurationUrl) else {
            throw PluginError.invalidArgument("Invalid configurationUrl: \(message.configurationUrl)")
        }
        let webServiceSigner = WebServiceSigner(
            configurationEndpoint: endpoint,
            bearerToken: message.bearerToken,
            headers: message.customHeaders
        )
        let box = SignerBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                box.result = .success(try await webServiceSigner.createSigner())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = box.result else {
            throw C2PAError.api("Remote signer creation failed")
        }
        return try result.get()
    }
}
