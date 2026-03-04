import Flutter
import UIKit
import C2PA

/// Stored settings entry for the handle-based settings API.
/// Since the c2pa-ios library uses a global settings load rather than an
/// object, we store the accumulated settings strings so they can be
/// re-applied (merged) when creating signers or contexts.
private struct SettingsEntry {
    var segments: [(settings: String, format: String)]
}

public class C2paPlugin: NSObject, FlutterPlugin {
    private var builders: [Int: Builder] = [:]
    private var nextBuilderHandle: Int = 1
    private let builderLock = NSLock()

    private var settingsMap: [Int: SettingsEntry] = [:]
    private var nextSettingsHandle: Int = 1
    private let settingsLock = NSLock()

    // Contexts wrap a settings handle reference on iOS
    private var contexts: [Int: Int] = [:]  // contextHandle -> settingsHandle
    private var nextContextHandle: Int = 1
    private let contextLock = NSLock()

    private var methodChannel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.guardianproject.c2pa", binaryMessenger: registrar.messenger())
        let instance = C2paPlugin()
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "getVersion":
            handleGetVersion(result: result)
        case "getSupportedReadMimeTypes":
            handleGetSupportedReadMimeTypes(result: result)
        case "getSupportedSignMimeTypes":
            handleGetSupportedSignMimeTypes(result: result)
        case "readFile":
            handleReadFile(call: call, result: result)
        case "readBytes":
            handleReadBytes(call: call, result: result)
        case "readFileDetailed":
            handleReadFileDetailed(call: call, result: result)
        case "readBytesDetailed":
            handleReadBytesDetailed(call: call, result: result)
        case "extractResource":
            handleExtractResource(call: call, result: result)
        case "readIngredientFile":
            handleReadIngredientFile(call: call, result: result)
        case "signBytes":
            handleSignBytes(call: call, result: result)
        case "signFile":
            handleSignFile(call: call, result: result)
        case "createBuilder":
            handleCreateBuilder(call: call, result: result)
        case "createBuilderFromArchive":
            handleCreateBuilderFromArchive(call: call, result: result)
        case "builderSetIntent":
            handleBuilderSetIntent(call: call, result: result)
        case "builderSetNoEmbed":
            handleBuilderSetNoEmbed(call: call, result: result)
        case "builderSetRemoteUrl":
            handleBuilderSetRemoteUrl(call: call, result: result)
        case "builderAddResource":
            handleBuilderAddResource(call: call, result: result)
        case "builderAddIngredient":
            handleBuilderAddIngredient(call: call, result: result)
        case "builderAddIngredientFromFile":
            handleBuilderAddIngredientFromFile(call: call, result: result)
        case "builderAddAction":
            handleBuilderAddAction(call: call, result: result)
        case "builderToArchive":
            handleBuilderToArchive(call: call, result: result)
        case "builderSign":
            handleBuilderSign(call: call, result: result)
        case "builderSignFile":
            handleBuilderSignFile(call: call, result: result)
        case "builderDispose":
            handleBuilderDispose(call: call, result: result)
        case "getSignerReserveSize":
            handleGetSignerReserveSize(call: call, result: result)
        case "loadSettings":
            handleLoadSettings(call: call, result: result)
        case "isHardwareSigningAvailable":
            handleIsHardwareSigningAvailable(result: result)
        case "createKey":
            handleCreateKey(call: call, result: result)
        case "deleteKey":
            handleDeleteKey(call: call, result: result)
        case "keyExists":
            handleKeyExists(call: call, result: result)
        case "exportPublicKey":
            handleExportPublicKey(call: call, result: result)
        // Settings Handle API
        case "createSettings":
            handleCreateSettings(result: result)
        case "settingsUpdateFromString":
            handleSettingsUpdateFromString(call: call, result: result)
        case "settingsSetValue":
            handleSettingsSetValue(call: call, result: result)
        case "settingsDispose":
            handleSettingsDispose(call: call, result: result)
        // Context Handle API
        case "createContext":
            handleCreateContext(result: result)
        case "createContextFromSettings":
            handleCreateContextFromSettings(call: call, result: result)
        case "contextDispose":
            handleContextDispose(call: call, result: result)
        // Enhanced Reader
        case "readFileWithContext":
            handleReadFileWithContext(call: call, result: result)
        // Enhanced Builder
        case "createBuilderWithContext":
            handleCreateBuilderWithContext(call: call, result: result)
        case "createBuilderWithSettings":
            handleCreateBuilderWithSettings(call: call, result: result)
        // Certificate Manager
        case "createSelfSignedCertificateChain":
            handleCreateSelfSignedCertificateChain(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Version and Info

    private func handleGetVersion(result: @escaping FlutterResult) {
        result(C2PA.version)
    }

    private func handleGetSupportedReadMimeTypes(result: @escaping FlutterResult) {
        let mimeTypes = [
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/heic",
            "image/heif",
            "image/avif",
            "video/mp4",
            "video/quicktime",
            "audio/mp4",
            "application/mp4",
            "audio/mpeg",
            "application/pdf",
            "image/svg+xml"
        ]
        result(mimeTypes)
    }

    private func handleGetSupportedSignMimeTypes(result: @escaping FlutterResult) {
        let mimeTypes = [
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/heic",
            "image/heif",
            "image/avif",
            "video/mp4",
            "video/quicktime",
            "audio/mp4",
            "application/mp4",
            "audio/mpeg",
            "application/pdf",
            "image/svg+xml"
        ]
        result(mimeTypes)
    }

    // MARK: - Reader API

    private func handleReadFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
            return
        }

        do {
            let url = URL(fileURLWithPath: path)
            let json = try C2PA.readFile(at: url, dataDir: nil)
            result(json)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleReadBytes(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data and mimeType are required", details: nil))
            return
        }

        readBytesInternal(data: data.data, mimeType: mimeType, detailed: false, result: result)
    }

    private func handleReadFileDetailed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
            return
        }

        let dataDirPath = args["dataDir"] as? String
        let dataDir = dataDirPath.map { URL(fileURLWithPath: $0) }

        do {
            let url = URL(fileURLWithPath: path)
            let json = try C2PA.readFile(at: url, dataDir: dataDir)
            result(json)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleReadBytesDetailed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data and mimeType are required", details: nil))
            return
        }

        let detailed = args["detailed"] as? Bool ?? false
        readBytesInternal(data: data.data, mimeType: mimeType, detailed: detailed, result: result)
    }

    private func readBytesInternal(data: Data, mimeType: String, detailed: Bool, result: @escaping FlutterResult) {
        do {
            let stream = try Stream(data: data)
            let reader = try Reader(format: mimeType, stream: stream)
            let json = detailed ? try reader.detailedJSON() : try reader.json()
            result(json)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleExtractResource(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String,
              let uri = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Data, mimeType, and uri are required", details: nil))
            return
        }

        do {
            let sourceStream = try Stream(data: data.data)
            let reader = try Reader(format: mimeType, stream: sourceStream)

            var resourceData = Data()
            let destStream = try Stream(
                write: { buffer, count in
                    resourceData.append(Data(bytes: buffer, count: count))
                    return count
                },
                flush: { return 0 }
            )

            try reader.resource(uri: uri, to: destStream)
            result(FlutterStandardTypedData(bytes: resourceData))
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleReadIngredientFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
            return
        }

        let dataDirPath = args["dataDir"] as? String
        let dataDir = dataDirPath.map { URL(fileURLWithPath: $0) }

        do {
            let url = URL(fileURLWithPath: path)
            let json = try C2PA.readIngredient(at: url, dataDir: dataDir)
            result(json)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Signer Creation

    private func createSigner(_ signerMap: [String: Any], result: @escaping FlutterResult, completion: @escaping (Signer) -> Void) {
        let signerType = signerMap["type"] as? String ?? "pem"

        do {
            switch signerType {
            case "pem":
                let signer = try createPemSigner(signerMap)
                completion(signer)

            case "keystore":
                let signer = try createKeychainSigner(signerMap)
                completion(signer)

            case "hardware":
                let signer = try createSecureEnclaveSigner(signerMap)
                completion(signer)

            case "callback":
                let signer = try createCallbackSigner(signerMap)
                completion(signer)

            case "settings":
                let signer = try createSettingsSigner(signerMap)
                completion(signer)

            case "remote":
                createRemoteSigner(signerMap) { signerResult in
                    switch signerResult {
                    case .success(let signer):
                        completion(signer)
                    case .failure(let error):
                        result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
                    }
                }

            default:
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Unknown signer type: \(signerType)", details: nil))
            }
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func createPemSigner(_ signerMap: [String: Any]) throws -> Signer {
        guard let algorithmStr = signerMap["algorithm"] as? String,
              let certificatePem = signerMap["certificatePem"] as? String,
              let privateKeyPem = signerMap["privateKeyPem"] as? String else {
            throw C2PAError.api("Invalid PEM signer configuration")
        }

        let tsaUrl = signerMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        return try Signer(
            certsPEM: certificatePem,
            privateKeyPEM: privateKeyPem,
            algorithm: algorithm,
            tsaURL: tsaUrl
        )
    }

    private func createKeychainSigner(_ signerMap: [String: Any]) throws -> Signer {
        guard let algorithmStr = signerMap["algorithm"] as? String,
              let certificateChainPem = signerMap["certificateChainPem"] as? String,
              let keyAlias = signerMap["keyAlias"] as? String else {
            throw C2PAError.api("Invalid keychain signer configuration")
        }

        let tsaUrl = signerMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        return try Signer(
            algorithm: algorithm,
            certificateChainPEM: certificateChainPem,
            tsaURL: tsaUrl,
            keychainKeyTag: keyAlias
        )
    }

    private func createSecureEnclaveSigner(_ signerMap: [String: Any]) throws -> Signer {
        guard let certificateChainPem = signerMap["certificateChainPem"] as? String,
              let keyAlias = signerMap["keyAlias"] as? String else {
            throw C2PAError.api("Invalid Secure Enclave signer configuration")
        }

        let tsaUrl = signerMap["tsaUrl"] as? String
        let requireUserAuth = signerMap["requireUserAuthentication"] as? Bool ?? false

        var accessControl: SecAccessControlCreateFlags = [.privateKeyUsage]
        if requireUserAuth {
            accessControl.insert(.biometryCurrentSet)
        }

        let config = SecureEnclaveSignerConfig(
            keyTag: keyAlias,
            accessControl: accessControl
        )

        return try Signer(
            algorithm: .es256,
            certificateChainPEM: certificateChainPem,
            tsaURL: tsaUrl,
            secureEnclaveConfig: config
        )
    }

    private func createCallbackSigner(_ signerMap: [String: Any]) throws -> Signer {
        guard let algorithmStr = signerMap["algorithm"] as? String,
              let certificateChainPem = signerMap["certificateChainPem"] as? String,
              let callbackId = signerMap["callbackId"] as? String else {
            throw C2PAError.api("Invalid callback signer configuration")
        }

        let tsaUrl = signerMap["tsaUrl"] as? String
        let algorithm = mapAlgorithm(algorithmStr)

        return try Signer(
            algorithm: algorithm,
            certificateChainPEM: certificateChainPem,
            tsaURL: tsaUrl
        ) { [weak self] dataToSign in
            guard let self = self, let channel = self.methodChannel else {
                throw C2PAError.api("Method channel not available")
            }

            let semaphore = DispatchSemaphore(value: 0)
            var signatureResult: Result<Data, Error>?

            DispatchQueue.main.async {
                channel.invokeMethod("signCallback", arguments: [
                    "callbackId": callbackId,
                    "data": FlutterStandardTypedData(bytes: dataToSign)
                ]) { response in
                    if let error = response as? FlutterError {
                        signatureResult = .failure(C2PAError.api(error.message ?? "Callback signing failed"))
                    } else if let signatureData = response as? FlutterStandardTypedData {
                        signatureResult = .success(signatureData.data)
                    } else {
                        signatureResult = .failure(C2PAError.api("Invalid callback response"))
                    }
                    semaphore.signal()
                }
            }

            semaphore.wait()

            switch signatureResult {
            case .success(let data):
                return data
            case .failure(let error):
                throw error
            case .none:
                throw C2PAError.api("Callback signing failed")
            }
        }
    }

    private func createRemoteSigner(_ signerMap: [String: Any], completion: @escaping (Result<Signer, Error>) -> Void) {
        guard let configurationUrl = signerMap["configurationUrl"] as? String else {
            completion(.failure(C2PAError.api("Invalid remote signer configuration")))
            return
        }

        let bearerToken = signerMap["bearerToken"] as? String
        let customHeaders = signerMap["customHeaders"] as? [String: String] ?? [:]

        let webServiceSigner = WebServiceSigner(
            configurationURL: configurationUrl,
            bearerToken: bearerToken,
            headers: customHeaders
        )

        Task { @MainActor in
            do {
                let signer = try await webServiceSigner.createSigner()
                completion(.success(signer))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func createSettingsSigner(_ signerMap: [String: Any]) throws -> Signer {
        guard let settings = signerMap["settings"] as? String else {
            throw C2PAError.api("Invalid settings signer configuration: settings string required")
        }

        let format = signerMap["format"] as? String ?? "json"

        switch format.lowercased() {
        case "json":
            return try Signer(settingsJSON: settings)
        case "toml":
            return try Signer(settingsTOML: settings)
        default:
            throw C2PAError.api("Unsupported settings format: \(format). Use 'json' or 'toml'.")
        }
    }

    // MARK: - Sign API

    private func handleSignBytes(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sourceData = args["sourceData"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String,
              let manifestJson = args["manifestJson"] as? String,
              let signerMap = args["signer"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "sourceData, mimeType, manifestJson, and signer are required", details: nil))
            return
        }

        createSigner(signerMap, result: result) { signer in
            self.performSignBytes(sourceData: sourceData.data, mimeType: mimeType, manifestJson: manifestJson, signer: signer, result: result)
        }
    }

    private func performSignBytes(sourceData: Data, mimeType: String, manifestJson: String, signer: Signer, result: @escaping FlutterResult) {
        do {
            let builder = try Builder(manifestJSON: manifestJson)
            let sourceStream = try Stream(data: sourceData)

            let tempDir = FileManager.default.temporaryDirectory
            let destUrl = tempDir.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: destUrl) }

            let destStream = try Stream(writeTo: destUrl)

            let manifestBytes = try builder.sign(
                format: mimeType,
                source: sourceStream,
                destination: destStream,
                signer: signer
            )

            let destData = try Data(contentsOf: destUrl)

            let resultMap: [String: Any?] = [
                "signedData": FlutterStandardTypedData(bytes: destData),
                "manifestBytes": FlutterStandardTypedData(bytes: manifestBytes),
                "manifestSize": manifestBytes.count
            ]

            result(resultMap)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleSignFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sourcePath = args["sourcePath"] as? String,
              let destPath = args["destPath"] as? String,
              let manifestJson = args["manifestJson"] as? String,
              let signerMap = args["signer"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "sourcePath, destPath, manifestJson, and signer are required", details: nil))
            return
        }

        createSigner(signerMap, result: result) { signer in
            do {
                let builder = try Builder(manifestJSON: manifestJson)
                let sourceStream = try Stream(readFrom: URL(fileURLWithPath: sourcePath))
                let destStream = try Stream(writeTo: URL(fileURLWithPath: destPath))

                let mimeType = self.mimeTypeForExtension((sourcePath as NSString).pathExtension.lowercased())

                try builder.sign(
                    format: mimeType,
                    source: sourceStream,
                    destination: destStream,
                    signer: signer
                )

                result(nil)
            } catch {
                result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    // MARK: - Builder API

    private func handleCreateBuilder(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let manifestJson = args["manifestJson"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "manifestJson is required", details: nil))
            return
        }

        do {
            let builder = try Builder(manifestJSON: manifestJson)
            let handle = storeBuilder(builder)
            result(handle)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleCreateBuilderFromArchive(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let archiveData = args["archiveData"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "archiveData is required", details: nil))
            return
        }

        do {
            let stream = try Stream(data: archiveData.data)
            let builder = try Builder(archiveStream: stream)
            let handle = storeBuilder(builder)
            result(handle)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderSetIntent(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let intentStr = args["intent"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and intent are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        do {
            let digitalSourceTypeStr = args["digitalSourceType"] as? String
            let intent = mapIntent(intentStr, digitalSourceType: digitalSourceTypeStr)
            try builder.setIntent(intent)
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderSetNoEmbed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        builder.setNoEmbed()
        result(nil)
    }

    private func handleBuilderSetRemoteUrl(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let url = args["url"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and url are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        do {
            try builder.setRemoteURL(url)
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderAddResource(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let uri = args["uri"] as? String,
              let data = args["data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, uri, and data are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        do {
            let stream = try Stream(data: data.data)
            try builder.addResource(uri: uri, stream: stream)
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderAddIngredient(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let data = args["data"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, data, and mimeType are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let ingredientJson = args["ingredientJson"] as? String ?? "{}"

        do {
            let stream = try Stream(data: data.data)
            try builder.addIngredient(json: ingredientJson, format: mimeType, from: stream)
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderAddIngredientFromFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and path are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let ingredientJson = args["ingredientJson"] as? String ?? "{}"
        let ext = (path as NSString).pathExtension.lowercased()
        let mimeType = mimeTypeForExtension(ext)

        do {
            let stream = try Stream(readFrom: URL(fileURLWithPath: path))
            try builder.addIngredient(json: ingredientJson, format: mimeType, from: stream)
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderAddAction(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let actionJson = args["actionJson"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle and actionJson are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        do {
            if let actionData = actionJson.data(using: .utf8),
               let actionDict = try JSONSerialization.jsonObject(with: actionData) as? [String: Any],
               let actionName = actionDict["action"] as? String {
                let digitalSourceTypeStr = actionDict["digitalSourceType"] as? String
                let action = Action(
                    action: actionName,
                    digitalSourceType: digitalSourceTypeStr,
                    softwareAgent: actionDict["softwareAgent"] as? String,
                    parameters: actionDict["parameters"] as? [String: String]
                )
                try builder.addAction(action)
            }
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderToArchive(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        do {
            var archiveData = Data()
            let stream = try Stream(
                write: { buffer, count in
                    archiveData.append(Data(bytes: buffer, count: count))
                    return count
                },
                flush: { return 0 }
            )

            try builder.writeArchive(to: stream)
            result(FlutterStandardTypedData(bytes: archiveData))
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleBuilderSign(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let sourceData = args["sourceData"] as? FlutterStandardTypedData,
              let mimeType = args["mimeType"] as? String,
              let signerMap = args["signer"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, sourceData, mimeType, and signer are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let signerType = signerMap["type"] as? String ?? "pem"
        let needsBackgroundQueue = signerType == "callback" || signerType == "remote"

        createSigner(signerMap, result: result) { signer in
            let signingWork = {
                do {
                    let sourceStream = try Stream(data: sourceData.data)

                    let tempDir = FileManager.default.temporaryDirectory
                    let destUrl = tempDir.appendingPathComponent(UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: destUrl) }

                    let destStream = try Stream(writeTo: destUrl)

                    let manifestBytes = try builder.sign(
                        format: mimeType,
                        source: sourceStream,
                        destination: destStream,
                        signer: signer
                    )

                    let destData = try Data(contentsOf: destUrl)

                    let resultMap: [String: Any?] = [
                        "signedData": FlutterStandardTypedData(bytes: destData),
                        "manifestBytes": FlutterStandardTypedData(bytes: manifestBytes),
                        "manifestSize": manifestBytes.count
                    ]

                    DispatchQueue.main.async {
                        result(resultMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

            if needsBackgroundQueue {
                DispatchQueue.global(qos: .userInitiated).async {
                    signingWork()
                }
            } else {
                signingWork()
            }
        }
    }

    private func handleBuilderSignFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let sourcePath = args["sourcePath"] as? String,
              let destPath = args["destPath"] as? String,
              let signerMap = args["signer"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, sourcePath, destPath, and signer are required", details: nil))
            return
        }

        guard let builder = getBuilder(handle) else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Builder not found", details: nil))
            return
        }

        let signerType = signerMap["type"] as? String ?? "pem"
        let needsBackgroundQueue = signerType == "callback" || signerType == "remote"

        createSigner(signerMap, result: result) { signer in
            let signingWork = {
                do {
                    let mimeType = self.mimeTypeForExtension((sourcePath as NSString).pathExtension.lowercased())
                    let sourceStream = try Stream(readFrom: URL(fileURLWithPath: sourcePath))
                    let destStream = try Stream(writeTo: URL(fileURLWithPath: destPath))

                    try builder.sign(
                        format: mimeType,
                        source: sourceStream,
                        destination: destStream,
                        signer: signer
                    )

                    DispatchQueue.main.async {
                        result(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

            if needsBackgroundQueue {
                DispatchQueue.global(qos: .userInitiated).async {
                    signingWork()
                }
            } else {
                signingWork()
            }
        }
    }

    private func handleBuilderDispose(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        removeBuilder(handle)
        result(nil)
    }

    // MARK: - Signer Utilities

    private func handleGetSignerReserveSize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let signerMap = args["signer"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "signer is required", details: nil))
            return
        }

        createSigner(signerMap, result: result) { signer in
            do {
                let reserveSize = try signer.reserveSize()
                result(reserveSize)
            } catch {
                result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func handleLoadSettings(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let settings = args["settings"] as? String,
              let format = args["format"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "settings and format are required", details: nil))
            return
        }

        do {
            try Signer.loadSettings(settings, format: format)
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Settings Handle API

    private func handleCreateSettings(result: @escaping FlutterResult) {
        let handle = storeSettings(SettingsEntry(segments: []))
        result(handle)
    }

    private func handleSettingsUpdateFromString(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int,
              let settings = args["settings"] as? String,
              let format = args["format"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle, settings, and format are required", details: nil))
            return
        }

        guard format.lowercased() == "json" || format.lowercased() == "toml" else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "format must be 'json' or 'toml'", details: nil))
            return
        }

        settingsLock.lock()
        guard settingsMap[handle] != nil else {
            settingsLock.unlock()
            result(FlutterError(code: "INVALID_HANDLE", message: "Settings not found", details: nil))
            return
        }
        settingsMap[handle]!.segments.append((settings: settings, format: format.lowercased()))
        settingsLock.unlock()

        // Also apply the settings globally so they take effect immediately
        do {
            try Signer.loadSettings(settings, format: format.lowercased())
            result(nil)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleSettingsSetValue(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // The c2pa-ios library does not expose a method to set individual
        // settings values. Settings are loaded as complete JSON or TOML
        // documents via Signer.loadSettings(). Individual key/value
        // setting is not supported on iOS.
        result(FlutterError(
            code: "NOT_SUPPORTED",
            message: "settingsSetValue is not supported on iOS. Use settingsUpdateFromString to load a complete settings document.",
            details: nil
        ))
    }

    private func handleSettingsDispose(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        removeSettings(handle)
        result(nil)
    }

    // MARK: - Context Handle API

    private func handleCreateContext(result: @escaping FlutterResult) {
        // Create an empty settings entry to back this context
        let settingsHandle = storeSettings(SettingsEntry(segments: []))
        let contextHandle = storeContext(settingsHandle: settingsHandle)
        result(contextHandle)
    }

    private func handleCreateContextFromSettings(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let settingsHandle = args["settingsHandle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "settingsHandle is required", details: nil))
            return
        }

        settingsLock.lock()
        let settingsExist = settingsMap[settingsHandle] != nil
        settingsLock.unlock()

        guard settingsExist else {
            result(FlutterError(code: "INVALID_HANDLE", message: "Settings not found", details: nil))
            return
        }

        let contextHandle = storeContext(settingsHandle: settingsHandle)
        result(contextHandle)
    }

    private func handleContextDispose(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let handle = args["handle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "handle is required", details: nil))
            return
        }

        removeContext(handle)
        result(nil)
    }

    // MARK: - Enhanced Reader

    private func handleReadFileWithContext(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "path is required", details: nil))
            return
        }

        let contextHandle = args["contextHandle"] as? Int
        let detailed = args["detailed"] as? Bool ?? false
        let dataDirPath = args["dataDir"] as? String
        let dataDir = dataDirPath.map { URL(fileURLWithPath: $0) }

        // Apply settings from context if provided
        if let contextHandle = contextHandle {
            do {
                try applyContextSettings(contextHandle)
            } catch {
                result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
                return
            }
        }

        do {
            if detailed {
                // Use the Reader API for detailed output
                let ext = (path as NSString).pathExtension.lowercased()
                let mimeType = mimeTypeForExtension(ext)
                let stream = try Stream(readFrom: URL(fileURLWithPath: path))
                let reader = try Reader(format: mimeType, stream: stream)
                let json = try reader.detailedJSON()
                result(json)
            } else {
                let url = URL(fileURLWithPath: path)
                let json = try C2PA.readFile(at: url, dataDir: dataDir)
                result(json)
            }
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Enhanced Builder

    private func handleCreateBuilderWithContext(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let contextHandle = args["contextHandle"] as? Int,
              let manifestJson = args["manifestJson"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "contextHandle and manifestJson are required", details: nil))
            return
        }

        // Apply settings from context before creating builder
        do {
            try applyContextSettings(contextHandle)
            let builder = try Builder(manifestJSON: manifestJson)
            let handle = storeBuilder(builder)
            result(handle)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    private func handleCreateBuilderWithSettings(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let manifestJson = args["manifestJson"] as? String,
              let settingsHandle = args["settingsHandle"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "manifestJson and settingsHandle are required", details: nil))
            return
        }

        // Apply settings before creating builder
        do {
            try applySettingsFromHandle(settingsHandle)
            let builder = try Builder(manifestJSON: manifestJson)
            let handle = storeBuilder(builder)
            result(handle)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Certificate Manager

    private func handleCreateSelfSignedCertificateChain(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let keyAlias = args["keyAlias"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "keyAlias is required", details: nil))
            return
        }

        let configMap = args["config"] as? [String: Any]

        let config = CertificateManager.CertificateConfig(
            commonName: configMap?["commonName"] as? String ?? "C2PA Signer",
            organization: configMap?["organization"] as? String ?? "Unknown",
            organizationalUnit: configMap?["organizationalUnit"] as? String ?? "",
            country: configMap?["country"] as? String ?? "US",
            state: configMap?["state"] as? String ?? "",
            locality: configMap?["locality"] as? String ?? "",
            emailAddress: configMap?["emailAddress"] as? String,
            validityDays: configMap?["validityDays"] as? Int ?? 365
        )

        do {
            // Look up the public key from the keychain using the key alias
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keyAlias,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecReturnRef as String: true
            ]

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)

            guard status == errSecSuccess,
                  let privateKey = item as! SecKey? else {
                result(FlutterError(code: "ERROR", message: "Failed to find key '\(keyAlias)' in keychain: \(status)", details: nil))
                return
            }

            guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                result(FlutterError(code: "ERROR", message: "Failed to extract public key from private key", details: nil))
                return
            }

            let certChainPem = try CertificateManager.createSelfSignedCertificateChain(
                for: publicKey,
                config: config
            )

            result(certChainPem)
        } catch {
            result(FlutterError(code: "C2PA_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Key Management

    private func handleIsHardwareSigningAvailable(result: @escaping FlutterResult) {
        #if targetEnvironment(simulator)
        result(false)
        #else
        result(true)
        #endif
    }

    private func handleCreateKey(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let keyAlias = args["keyAlias"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "keyAlias is required", details: nil))
            return
        }

        let useHardware = args["useHardware"] as? Bool ?? false

        if useHardware {
            #if targetEnvironment(simulator)
            result(FlutterError(code: "NOT_AVAILABLE", message: "Secure Enclave not available in Simulator", details: nil))
            #else
            do {
                let config = SecureEnclaveSignerConfig(keyTag: keyAlias, accessControl: [.privateKeyUsage])
                _ = try Signer.createSecureEnclaveKey(config: config)
                result(nil)
            } catch {
                result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
            }
            #endif
        } else {
            createKeychainKey(keyAlias: keyAlias, result: result)
        }
    }

    private func createKeychainKey(keyAlias: String, result: @escaping FlutterResult) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!
            ]
        ]

        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            let errorMessage = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            result(FlutterError(code: "ERROR", message: "Failed to create key: \(errorMessage)", details: nil))
            return
        }

        result(nil)
    }

    private func handleDeleteKey(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let keyAlias = args["keyAlias"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "keyAlias is required", details: nil))
            return
        }

        let deleted = Signer.deleteSecureEnclaveKey(keyTag: keyAlias)
        if !deleted {
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!
            ]
            SecItemDelete(query as CFDictionary)
        }
        result(nil)
    }

    private func handleKeyExists(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let keyAlias = args["keyAlias"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "keyAlias is required", details: nil))
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyAlias.data(using: .utf8)!,
            kSecReturnRef as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        result(status == errSecSuccess)
    }

    private func handleExportPublicKey(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let keyAlias = args["keyAlias"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "keyAlias is required", details: nil))
            return
        }

        do {
            let pem = try Signer.exportPublicKeyPEM(fromKeychainTag: keyAlias)
            result(pem)
        } catch {
            result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Helper Functions

    private func mapAlgorithm(_ str: String) -> SigningAlgorithm {
        switch str.lowercased() {
        case "es256": return .es256
        case "es384": return .es384
        case "es512": return .es512
        case "ps256": return .ps256
        case "ps384": return .ps384
        case "ps512": return .ps512
        case "ed25519": return .ed25519
        default: return .es256
        }
    }

    private func mapIntent(_ str: String, digitalSourceType: String?) -> BuilderIntent {
        switch str.lowercased() {
        case "create":
            let sourceType = mapDigitalSourceType(digitalSourceType) ?? .digitalCapture
            return .create(sourceType)
        case "edit":
            return .edit
        case "update":
            return .update
        default:
            return .edit
        }
    }

    private func mapDigitalSourceType(_ str: String?) -> DigitalSourceType? {
        guard let str = str else { return nil }
        switch str {
        case "algorithmicallyEnhanced": return .algorithmicallyEnhanced
        case "algorithmicMedia": return .algorithmicMedia
        case "composite": return .composite
        case "compositeCapture": return .compositeCapture
        case "compositeSynthetic": return .compositeSynthetic
        case "compositeWithTrainedAlgorithmicMedia": return .compositeWithTrainedAlgorithmicMedia
        case "dataDrivenMedia": return .dataDrivenMedia
        case "digitalCreation": return .digitalCreation
        case "digitalCapture": return .digitalCapture
        case "humanEdits": return .humanEdits
        case "negativeFilm": return .negativeFilm
        case "positiveFilm": return .positiveFilm
        case "print": return .print
        case "screenCapture": return .screenCapture
        case "trainedAlgorithmicMedia": return .trainedAlgorithmicMedia
        case "virtualRecording": return .virtualRecording
        default: return nil
        }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "gif": return "image/gif"
        case "tiff", "tif": return "image/tiff"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Builder Handle Management

    private func storeBuilder(_ builder: Builder) -> Int {
        builderLock.lock()
        defer { builderLock.unlock() }

        let handle = nextBuilderHandle
        nextBuilderHandle += 1
        builders[handle] = builder
        return handle
    }

    private func getBuilder(_ handle: Int) -> Builder? {
        builderLock.lock()
        defer { builderLock.unlock() }

        return builders[handle]
    }

    private func removeBuilder(_ handle: Int) {
        builderLock.lock()
        defer { builderLock.unlock() }

        builders.removeValue(forKey: handle)
    }

    // MARK: - Settings Handle Management

    private func storeSettings(_ entry: SettingsEntry) -> Int {
        settingsLock.lock()
        defer { settingsLock.unlock() }

        let handle = nextSettingsHandle
        nextSettingsHandle += 1
        settingsMap[handle] = entry
        return handle
    }

    private func getSettings(_ handle: Int) -> SettingsEntry? {
        settingsLock.lock()
        defer { settingsLock.unlock() }

        return settingsMap[handle]
    }

    private func removeSettings(_ handle: Int) {
        settingsLock.lock()
        defer { settingsLock.unlock() }

        settingsMap.removeValue(forKey: handle)
    }

    /// Apply all stored settings segments from a settings handle globally.
    private func applySettingsFromHandle(_ handle: Int) throws {
        guard let entry = getSettings(handle) else {
            throw C2PAError.api("Settings handle not found")
        }

        for segment in entry.segments {
            try Signer.loadSettings(segment.settings, format: segment.format)
        }
    }

    // MARK: - Context Handle Management

    private func storeContext(settingsHandle: Int) -> Int {
        contextLock.lock()
        defer { contextLock.unlock() }

        let handle = nextContextHandle
        nextContextHandle += 1
        contexts[handle] = settingsHandle
        return handle
    }

    private func getContextSettingsHandle(_ handle: Int) -> Int? {
        contextLock.lock()
        defer { contextLock.unlock() }

        return contexts[handle]
    }

    private func removeContext(_ handle: Int) {
        contextLock.lock()
        defer { contextLock.unlock() }

        contexts.removeValue(forKey: handle)
    }

    /// Apply settings from a context handle (resolves context -> settings -> load).
    private func applyContextSettings(_ contextHandle: Int) throws {
        guard let settingsHandle = getContextSettingsHandle(contextHandle) else {
            throw C2PAError.api("Context handle not found")
        }

        try applySettingsFromHandle(settingsHandle)
    }
}
