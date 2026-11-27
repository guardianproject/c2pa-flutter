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
import CryptoKit
import Foundation
import Security

/// Keychain / Secure Enclave key management behind the Dart key API.
final class KeyManagement {
    func isHardwareSigningAvailable() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func createKey(_ keyAlias: String, algorithm: SigningAlgorithmMessage, useHardware: Bool) throws {
        if useHardware {
            guard algorithm == .es256 else {
                throw PluginError.invalidArgument("Hardware keys are P-256: use es256, not \(algorithm.dartName)")
            }
            #if targetEnvironment(simulator)
            throw PluginError(code: "NOT_AVAILABLE", message: "Secure Enclave not available in Simulator")
            #else
            let config = SecureEnclaveSignerConfig(keyTag: keyAlias, accessControl: [.privateKeyUsage])
            _ = try Signer.createSecureEnclaveKey(config: config)
            #endif
        } else {
            try createKeychainKey(keyAlias, bits: try keySize(for: algorithm))
        }
    }

    private func keySize(for algorithm: SigningAlgorithmMessage) throws -> Int {
        switch algorithm {
        case .es256: return 256
        case .es384: return 384
        case .es512: return 521
        default:
            throw PluginError.invalidArgument("createKey supports es256, es384 and es512, not \(algorithm.dartName)")
        }
    }

    private func createKeychainKey(_ keyAlias: String, bits: Int = 256) throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: bits,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyAlias,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            let message = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw PluginError(code: "ERROR", message: "Failed to create key: \(message)")
        }
    }

    /// Deletes every key tagged [keyAlias], in the keychain or the Secure
    /// Enclave. c2pa-swift's `deleteSecureEnclaveKey` reports success when
    /// nothing matched, so it cannot tell whether a keychain key remains.
    func deleteKey(_ keyAlias: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    func keyExists(_ keyAlias: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias,
            kSecReturnRef as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Exports the public key as a PEM SubjectPublicKeyInfo, the form Android
    /// returns. c2pa-swift's `Signer.exportPublicKeyPEM` returns the bare
    /// X9.63 point under the same PEM label, so the point is wrapped here.
    func exportPublicKey(_ keyAlias: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let found = item else {
            throw PluginError(code: "KEY_NOT_FOUND", message: "Key not found: \(keyAlias)")
        }
        // swiftlint:disable:next force_cast
        let privateKey = found as! SecKey
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let point = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "no public key"
            throw PluginError(code: "ERROR", message: "Failed to export public key: \(message)")
        }
        guard let header = Self.spkiHeaders[point.count] else {
            throw PluginError(code: "ERROR", message: "Unexpected EC point of \(point.count) bytes")
        }
        let der = header + point
        let base64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----"
    }

    /// DER SubjectPublicKeyInfo prefixes for uncompressed P-256, P-384 and
    /// P-521 points, keyed by the point's length.
    private static let spkiHeaders: [Int: Data] = [
        65: Data(hex: "3059301306072a8648ce3d020106082a8648ce3d030107034200"),
        97: Data(hex: "3076301006072a8648ce3d020106052b81040022036200"),
        133: Data(hex: "30819b301006072a8648ce3d020106052b8104002303818600"),
    ]

    /// Imports an EC private key (PEM, PKCS#8 or SEC1) into the keychain under
    /// [keyAlias]. The certificate chain is not stored: keychain signers take
    /// it as a separate argument. RSA keys are not supported by the keychain
    /// signer path, so they are rejected.
    func importKey(_ keyAlias: String, privateKeyPem: String) throws {
        let (x963, bits) = try ecPrivateKeyX963(privateKeyPem)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: bits,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(x963 as CFData, attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw PluginError(code: "ERROR", message: "Failed to import key: \(message)")
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias,
        ]
        _ = SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: key,
            kSecAttrApplicationTag as String: keyAlias,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PluginError(code: "ERROR", message: "Failed to store imported key: \(status)")
        }
    }

    private func ecPrivateKeyX963(_ pem: String) throws -> (Data, Int) {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return (key.x963Representation, 256)
        }
        if let key = try? P384.Signing.PrivateKey(pemRepresentation: pem) {
            return (key.x963Representation, 384)
        }
        if let key = try? P521.Signing.PrivateKey(pemRepresentation: pem) {
            return (key.x963Representation, 521)
        }
        throw PluginError.notImplemented(
            "importKey on iOS supports EC P-256, P-384 and P-521 private keys only"
        )
    }

    func createCSR(_ keyAlias: String, config: CertificateConfigMessage) throws -> String {
        let certificateConfig = CertificateManager.CertificateConfig(
            commonName: config.commonName,
            organization: config.organization ?? "",
            organizationalUnit: config.organizationalUnit ?? "",
            country: config.country ?? "",
            state: config.state ?? "",
            locality: config.locality ?? ""
        )
        return try CertificateManager.createCSR(keyTag: keyAlias, config: certificateConfig)
    }

    /// Creates a fresh key (Secure Enclave on device, keychain in the
    /// simulator or when `useStrongBox` is false and the enclave is
    /// unavailable), creates a CSR for it and submits it to
    /// `<signingServerUrl>/api/v1/certificates/sign`, the same protocol the
    /// Android implementation uses.
    func enrollHardwareKey(
        _ keyAlias: String,
        signingServerURL serverURL: String,
        bearerToken: String?,
        commonName commonNameOrNil: String?,
        organization organizationOrNil: String?
    ) throws -> HardwareKeyEnrollmentMessage {
        let commonName = commonNameOrNil ?? "C2PA Hardware Key"
        let organization = organizationOrNil ?? "C2PA App"

        _ = deleteKey(keyAlias)
        if isHardwareSigningAvailable() {
            let config = SecureEnclaveSignerConfig(keyTag: keyAlias, accessControl: [.privateKeyUsage])
            _ = try Signer.createSecureEnclaveKey(config: config)
        } else {
            try createKeychainKey(keyAlias)
        }

        let csr = try CertificateManager.createCSR(
            keyTag: keyAlias,
            config: CertificateManager.CertificateConfig(
                commonName: commonName,
                organization: organization,
                organizationalUnit: "",
                country: "US",
                state: "",
                locality: ""
            )
        )

        guard let url = URL(string: "\(serverURL)/api/v1/certificates/sign") else {
            throw PluginError.invalidArgument("Invalid signingServerUrl: \(serverURL)")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["csr": csr])

        let (data, response) = try performBlocking(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw PluginError(code: "ENROLLMENT_ERROR", message: "Certificate enrollment failed: \(body)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chain = json["certificate_chain"] as? String else {
            throw PluginError(code: "ENROLLMENT_ERROR", message: "Enrollment response has no certificate_chain")
        }
        return HardwareKeyEnrollmentMessage(keyAlias: keyAlias, certificateChainPem: chain)
    }

    private func performBlocking(_ request: URLRequest) throws -> (Data, URLResponse?) {
        final class Box: @unchecked Sendable {
            var data = Data()
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data ?? Data()
            box.response = response
            box.error = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let error = box.error { throw error }
        return (box.data, box.response)
    }

    func createSelfSignedCertificateChain(_ keyAlias: String, config message: CertificateConfigMessage?) throws -> String {
        let config = CertificateManager.CertificateConfig(
            commonName: message?.commonName ?? "C2PA Signer",
            organization: message?.organization ?? "Unknown",
            organizationalUnit: message?.organizationalUnit ?? "",
            country: message?.country ?? "US",
            state: message?.state ?? "",
            locality: message?.locality ?? "",
            emailAddress: message?.emailAddress,
            validityDays: message?.validityDays.map { Int($0) } ?? 365
        )

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let found = item else {
            throw PluginError(code: "ERROR", message: "Failed to find key '\(keyAlias)' in keychain: \(status)")
        }
        // swiftlint:disable:next force_cast
        let privateKey = found as! SecKey
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw PluginError(code: "ERROR", message: "Failed to extract public key from private key")
        }
        return try CertificateManager.createSelfSignedCertificateChain(for: publicKey, config: config)
    }
}

private extension Data {
    init(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
