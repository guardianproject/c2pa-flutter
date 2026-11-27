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
// Foundation also declares `Stream` (NSStream); prefer the C2PA type.
import class C2PA.Stream
import Flutter
import UIKit

/// Flutter plugin bridging the Dart C2PA API to c2pa-swift through the
/// Pigeon-generated `C2paHostApi` and `C2paFlutterApi`.
///
/// Threading model: every call that touches a builder, reader, settings or
/// context runs on one serial worker queue, in the order Dart sent it. That
/// keeps the main thread free while signing (callback signers, progress and
/// HTTP resolvers call back into Dart on the main thread while the worker
/// waits), and it means `builderDispose` can never free a builder that an
/// earlier call is still using. Key management runs on a separate queue so a
/// Dart signing callback can use it while the worker waits. `contextCancel`
/// runs immediately, since it must reach an operation occupying the worker.
public class C2paPlugin: NSObject, FlutterPlugin, C2paHostApi {
    private let worker = DispatchQueue(label: "org.guardianproject.c2pa.worker", qos: .userInitiated)
    private let aux = DispatchQueue(label: "org.guardianproject.c2pa.aux", qos: .userInitiated, attributes: .concurrent)

    private let builders = HandleRegistry<Builder>()
    private let settingsHandles = HandleRegistry<C2PASettings>()
    private let contexts = HandleRegistry<C2PAContext>()

    /// Settings applied by `loadSettings` to readers and builders created
    /// without a context. Worker queue only.
    private var defaultSettings: C2PASettings?

    private let bridge = DartBridge()
    private lazy var signers = SignerFactory(bridge: bridge)
    private let keys = KeyManagement()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = C2paPlugin()
        let messenger = registrar.messenger()
        instance.bridge.api = C2paFlutterApi(binaryMessenger: messenger)
        C2paHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
    }

    // MARK: - Lanes and result plumbing

    /// Runs [body] on the serial worker and completes on the main thread.
    private func onWorker<T>(
        _ completion: @escaping (Result<T, Error>) -> Void,
        _ body: @escaping () throws -> T
    ) {
        worker.async { Self.deliver(completion, body) }
    }

    /// Runs [body] on the key-management queue and completes on the main thread.
    private func onAux<T>(
        _ completion: @escaping (Result<T, Error>) -> Void,
        _ body: @escaping () throws -> T
    ) {
        aux.async { Self.deliver(completion, body) }
    }

    private static func deliver<T>(
        _ completion: @escaping (Result<T, Error>) -> Void,
        _ body: () throws -> T
    ) {
        let result: Result<T, Error>
        do {
            result = .success(try body())
        } catch {
            result = .failure(pigeonError(error))
        }
        DispatchQueue.main.async { completion(result) }
    }

    /// Maps a failure to the error codes Dart's C2paException understands.
    static func pigeonError(_ error: Error) -> PigeonError {
        switch error {
        case let error as PigeonError:
            return error
        case let error as PluginError:
            return PigeonError(code: error.code, message: error.message, details: nil)
        case let error as C2PAError:
            return PigeonError(code: "C2PA_ERROR", message: error.errorDescription ?? "\(error)", details: nil)
        default:
            return PigeonError(code: "ERROR", message: error.localizedDescription, details: nil)
        }
    }

    // MARK: - Version and MIME types

    func getPlatformVersion() throws -> String {
        "iOS " + UIDevice.current.systemVersion
    }

    func getVersion(completion: @escaping (Result<String, Error>) -> Void) {
        onWorker(completion) { C2PA.version }
    }

    func getSupportedReadMimeTypes(completion: @escaping (Result<[String], Error>) -> Void) {
        onWorker(completion) { Reader.supportedMimeTypes }
    }

    func getSupportedSignMimeTypes(completion: @escaping (Result<[String], Error>) -> Void) {
        onWorker(completion) { Builder.supportedMimeTypes }
    }

    // MARK: - Reading

    func readFile(
        path: String,
        mimeType: String?,
        format: ReadFormatMessage,
        contextHandle: Int64?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.output(try self.pathReader(path, mimeType: mimeType, contextHandle: contextHandle), format)
        }
    }

    func readBytes(
        data: FlutterStandardTypedData,
        mimeType: String,
        format: ReadFormatMessage,
        contextHandle: Int64?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onWorker(completion) {
            let reader = try self.newReader(contextHandle, format: mimeType, stream: try Stream(data: data.data))
            return try self.output(reader, format)
        }
    }

    func readWithManifest(
        path: String?,
        data: FlutterStandardTypedData?,
        mimeType: String?,
        manifestData: FlutterStandardTypedData,
        format: ReadFormatMessage,
        contextHandle: Int64?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onWorker(completion) {
            let stream: Stream
            let assetFormat: String
            switch (path, data) {
            case let (nil, data?):
                guard let mimeType = mimeType else {
                    throw PluginError.invalidArgument("mimeType is required")
                }
                stream = try Stream(data: data.data)
                assetFormat = mimeType
            case let (path?, nil):
                stream = try openForRead(path)
                assetFormat = mimeType ?? mimeTypeForPath(path)
            default:
                throw PluginError.invalidArgument("Provide exactly one of path or data")
            }
            let reader: Reader
            if let context = try self.contextFor(contextHandle) {
                reader = try Reader(context: context, format: assetFormat, stream: stream, manifest: manifestData.data)
            } else {
                reader = try Reader(format: assetFormat, stream: stream, manifest: manifestData.data)
            }
            return try self.output(reader, format)
        }
    }

    func readFragment(
        initPath: String,
        fragmentPath: String,
        mimeType: String?,
        format: ReadFormatMessage,
        contextHandle: Int64?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onWorker(completion) { () throws -> String in
            throw PluginError.notImplemented("Fragmented BMFF reading is not available in c2pa-swift")
        }
    }

    func extractResource(
        data: FlutterStandardTypedData,
        mimeType: String,
        uri: String,
        contextHandle: Int64?,
        completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
    ) {
        onWorker(completion) {
            let reader = try self.newReader(contextHandle, format: mimeType, stream: try Stream(data: data.data))
            let sink = DataSink()
            try reader.resource(uri: uri, to: try sink.stream())
            return FlutterStandardTypedData(bytes: sink.data)
        }
    }

    func getRemoteUrl(path: String, mimeType: String?, completion: @escaping (Result<String?, Error>) -> Void) {
        onWorker(completion) {
            try self.pathReader(path, mimeType: mimeType, contextHandle: nil).remote()?.absoluteString
        }
    }

    func isManifestEmbedded(path: String, mimeType: String?, completion: @escaping (Result<Bool, Error>) -> Void) {
        onWorker(completion) {
            try self.pathReader(path, mimeType: mimeType, contextHandle: nil).isEmbedded()
        }
    }

    private func output(_ reader: Reader, _ format: ReadFormatMessage) throws -> String {
        switch format {
        case .json: return try reader.json()
        case .detailed: return try reader.detailedJSON()
        case .crJson: return try reader.crJSON()
        }
    }

    private func pathReader(_ path: String, mimeType: String?, contextHandle: Int64?) throws -> Reader {
        try newReader(
            contextHandle,
            format: mimeType ?? mimeTypeForPath(path),
            stream: try openForRead(path)
        )
    }

    // MARK: - One-shot signing

    func signBytes(
        sourceData: FlutterStandardTypedData,
        mimeType: String,
        manifestJson: String,
        signer: SignerMessage,
        completion: @escaping (Result<SignResultMessage, Error>) -> Void
    ) {
        onWorker(completion) {
            let dest = TempFile()
            let manifest = try self.oneShotSign(
                manifestJson: manifestJson,
                signer: signer,
                format: mimeType,
                source: try Stream(data: sourceData.data),
                destination: try Stream(writeTo: dest.url)
            )
            return Self.signResult(manifest: manifest, signedData: try dest.contents())
        }
    }

    func signFile(
        sourcePath: String,
        destPath: String,
        manifestJson: String,
        signer: SignerMessage,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            _ = try self.oneShotSign(
                manifestJson: manifestJson,
                signer: signer,
                format: mimeTypeForPath(sourcePath),
                source: try openForRead(sourcePath),
                destination: try openForWrite(destPath)
            )
        }
    }

    private func oneShotSign(
        manifestJson: String,
        signer: SignerMessage,
        format: String,
        source: Stream,
        destination: Stream
    ) throws -> Data {
        if let settingsSigner = signer as? SettingsSignerMessage {
            let settings = try defaultLabelSettings()
            try load(into: settings, settingsSigner.settings, format: settingsSigner.format)
            let builder = try Builder(context: try C2PAContext(settings: settings), manifestJSON: manifestJson)
            return try builder.sign(format: format, source: source, destination: destination)
        }
        return try sign(
            try newBuilder(nil, manifestJson),
            signer: signer,
            format: format,
            source: source,
            destination: destination
        )
    }

    func getSignerReserveSize(signer: SignerMessage, completion: @escaping (Result<Int64, Error>) -> Void) {
        onWorker(completion) { Int64(try self.signers.create(signer).reserveSize()) }
    }

    func composeManifest(
        manifestBytes: FlutterStandardTypedData,
        mimeType: String,
        completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
    ) {
        onWorker(completion) {
            FlutterStandardTypedData(bytes: try Builder.composeManifest(manifestBytes.data, format: mimeType))
        }
    }

    // MARK: - Builder lifecycle and configuration

    func createBuilder(manifestJson: String, contextHandle: Int64?, completion: @escaping (Result<Int64, Error>) -> Void) {
        onWorker(completion) { Int64(self.builders.store(try self.newBuilder(contextHandle, manifestJson))) }
    }

    func createBuilderWithSettings(
        manifestJson: String,
        settingsHandle: Int64,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        onWorker(completion) {
            let context = try C2PAContext(settings: try self.settingsFor(settingsHandle))
            return Int64(self.builders.store(try Builder(context: context, manifestJSON: manifestJson)))
        }
    }

    func createBuilderFromArchive(
        archiveData: FlutterStandardTypedData,
        contextHandle: Int64?,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        onWorker(completion) {
            let stream = try Stream(data: archiveData.data)
            if let context = try self.contextFor(contextHandle) {
                return Int64(self.builders.store(try Builder(context: context, archiveStream: stream)))
            }
            return Int64(self.builders.store(try Builder(archiveStream: stream)))
        }
    }

    func builderDispose(handle: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { self.builders.remove(Int(handle)) }
    }

    func builderSetIntent(
        handle: Int64,
        intent: ManifestIntentMessage,
        digitalSourceType: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            let builder = try self.builder(handle)
            switch intent {
            case .create:
                if let name = digitalSourceType, parseDigitalSourceType(name) == nil {
                    // c2pa-swift's DigitalSourceType lacks this IPTC type, so
                    // declare the created action directly instead of via intent.
                    try builder.addAction(Action(
                        action: "c2pa.created",
                        digitalSourceType: digitalSourceTypeURL(name)
                    ))
                } else {
                    try builder.setIntent(.create(digitalSourceType.flatMap(parseDigitalSourceType) ?? .digitalCapture))
                }
            case .edit:
                try builder.setIntent(.edit)
            case .update:
                try builder.setIntent(.update)
            }
        }
    }

    func builderSetNoEmbed(handle: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { try self.builder(handle).setNoEmbed() }
    }

    func builderSetRemoteUrl(handle: Int64, url: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) {
            guard let remote = URL(string: url) else {
                throw PluginError.invalidArgument("Invalid url: \(url)")
            }
            try self.builder(handle).setRemote(url: remote)
        }
    }

    func builderSetBasePath(handle: Int64, path: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { try self.builder(handle).setBasePath(fileURL(path)) }
    }

    func builderAddResource(
        handle: Int64,
        uri: String,
        data: FlutterStandardTypedData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).addResource(uri: uri, stream: try Stream(data: data.data))
        }
    }

    func builderAddIngredient(
        handle: Int64,
        data: FlutterStandardTypedData,
        mimeType: String,
        ingredientJson: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).addIngredient(
                json: ingredientJson ?? "{}",
                format: mimeType,
                from: try Stream(data: data.data)
            )
        }
    }

    func builderAddIngredientFromFile(
        handle: Int64,
        path: String,
        mimeType: String?,
        ingredientJson: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).addIngredient(
                json: ingredientJson ?? "{}",
                format: mimeType ?? mimeTypeForPath(path),
                from: try openForRead(path)
            )
        }
    }

    func builderAddIngredientFromArchive(
        handle: Int64,
        archiveData: FlutterStandardTypedData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).addIngredient(fromArchive: try Stream(data: archiveData.data))
        }
    }

    func builderWriteIngredientArchive(
        handle: Int64,
        ingredientId: String,
        completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
    ) {
        onWorker(completion) {
            let sink = DataSink()
            try self.builder(handle).writeIngredientArchive(id: ingredientId, to: try sink.stream())
            return FlutterStandardTypedData(bytes: sink.data)
        }
    }

    func builderAddAction(handle: Int64, actionJson: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { try self.builder(handle).addAction(try self.parseAction(actionJson)) }
    }

    func builderToArchive(handle: Int64, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        onWorker(completion) {
            let sink = DataSink()
            try self.builder(handle).writeArchive(to: try sink.stream())
            return FlutterStandardTypedData(bytes: sink.data)
        }
    }

    // MARK: - Builder signing

    func builderSign(
        handle: Int64,
        sourceData: FlutterStandardTypedData,
        mimeType: String,
        signer: SignerMessage?,
        completion: @escaping (Result<SignResultMessage, Error>) -> Void
    ) {
        onWorker(completion) {
            let dest = TempFile()
            let manifest = try self.sign(
                try self.builder(handle),
                signer: signer,
                format: mimeType,
                source: try Stream(data: sourceData.data),
                destination: try Stream(writeTo: dest.url)
            )
            return Self.signResult(manifest: manifest, signedData: try dest.contents())
        }
    }

    func builderSignFile(
        handle: Int64,
        sourcePath: String,
        destPath: String,
        mimeType: String?,
        signer: SignerMessage?,
        completion: @escaping (Result<SignResultMessage, Error>) -> Void
    ) {
        onWorker(completion) {
            let manifest = try self.sign(
                try self.builder(handle),
                signer: signer,
                format: mimeType ?? mimeTypeForPath(sourcePath),
                source: try openForRead(sourcePath),
                destination: try openForWrite(destPath)
            )
            return Self.signResult(manifest: manifest, signedData: nil)
        }
    }

    /// Signs with [signer], or with the builder's context signer when nil.
    private func sign(
        _ builder: Builder,
        signer: SignerMessage?,
        format: String,
        source: Stream,
        destination: Stream
    ) throws -> Data {
        guard let signer = signer else {
            return try builder.sign(format: format, source: source, destination: destination)
        }
        return try builder.sign(
            format: format,
            source: source,
            destination: destination,
            signer: try signers.create(signer)
        )
    }

    private static func signResult(manifest: Data, signedData: Data?) -> SignResultMessage {
        SignResultMessage(
            signedData: signedData.map { FlutterStandardTypedData(bytes: $0) },
            manifestBytes: FlutterStandardTypedData(bytes: manifest),
            manifestSize: Int64(manifest.count)
        )
    }

    // MARK: - Embeddable / data-hash / BMFF flows

    func builderNeedsPlaceholder(handle: Int64, mimeType: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onWorker(completion) { try self.builder(handle).needsPlaceholder(format: mimeType) }
    }

    func builderPlaceholder(
        handle: Int64,
        mimeType: String,
        completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
    ) {
        onWorker(completion) { FlutterStandardTypedData(bytes: try self.builder(handle).placeholder(format: mimeType)) }
    }

    func builderSetDataHashExclusions(
        handle: Int64,
        exclusions: [DataHashExclusionMessage],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            let ranges = try exclusions.map { exclusion -> (start: UInt64, length: UInt64) in
                guard exclusion.start >= 0, exclusion.length >= 0 else {
                    throw PluginError.invalidArgument("Exclusion start and length must not be negative")
                }
                return (start: UInt64(exclusion.start), length: UInt64(exclusion.length))
            }
            try self.builder(handle).setDataHashExclusions(ranges)
        }
    }

    func builderUpdateHashFromBytes(
        handle: Int64,
        mimeType: String,
        data: FlutterStandardTypedData,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).updateHashFromStream(format: mimeType, stream: try Stream(data: data.data))
        }
    }

    func builderUpdateHashFromFile(
        handle: Int64,
        path: String,
        mimeType: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).updateHashFromStream(
                format: mimeType ?? mimeTypeForPath(path),
                stream: try openForRead(path)
            )
        }
    }

    func builderSignEmbeddable(
        handle: Int64,
        mimeType: String,
        completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
    ) {
        onWorker(completion) {
            FlutterStandardTypedData(bytes: try self.builder(handle).signEmbeddable(format: mimeType))
        }
    }

    func builderHashType(handle: Int64, mimeType: String, completion: @escaping (Result<HashTypeMessage, Error>) -> Void) {
        onWorker(completion) { hashTypeMessage(try self.builder(handle).hashType(format: mimeType)) }
    }

    func builderSetFixedSizeMerkle(handle: Int64, fixedSizeKb: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { try self.builder(handle).setFixedSizeMerkle(Int(fixedSizeKb)) }
    }

    func builderHashMdatBytes(
        handle: Int64,
        mdatId: Int64,
        data: FlutterStandardTypedData,
        largeSize: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) {
            try self.builder(handle).hashMdatBytes(mdatId: Int(mdatId), data: data.data, largeSize: largeSize)
        }
    }

    // MARK: - Key management

    func isHardwareSigningAvailable(completion: @escaping (Result<Bool, Error>) -> Void) {
        onAux(completion) { self.keys.isHardwareSigningAvailable() }
    }

    func createKey(
        keyAlias: String,
        algorithm: SigningAlgorithmMessage,
        useHardware: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onAux(completion) { try self.keys.createKey(keyAlias, algorithm: algorithm, useHardware: useHardware) }
    }

    func deleteKey(keyAlias: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onAux(completion) { self.keys.deleteKey(keyAlias) }
    }

    func keyExists(keyAlias: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        onAux(completion) { self.keys.keyExists(keyAlias) }
    }

    func exportPublicKey(keyAlias: String, completion: @escaping (Result<String, Error>) -> Void) {
        onAux(completion) { try self.keys.exportPublicKey(keyAlias) }
    }

    func importKey(
        keyAlias: String,
        privateKeyPem: String,
        certificateChainPem: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onAux(completion) { try self.keys.importKey(keyAlias, privateKeyPem: privateKeyPem) }
    }

    func createCSR(keyAlias: String, config: CertificateConfigMessage, completion: @escaping (Result<String, Error>) -> Void) {
        onAux(completion) { try self.keys.createCSR(keyAlias, config: config) }
    }

    func enrollHardwareKey(
        keyAlias: String,
        signingServerUrl: String,
        bearerToken: String?,
        commonName: String?,
        organization: String?,
        useStrongBox: Bool,
        completion: @escaping (Result<HardwareKeyEnrollmentMessage, Error>) -> Void
    ) {
        onAux(completion) {
            try self.keys.enrollHardwareKey(
                keyAlias,
                signingServerURL: signingServerUrl,
                bearerToken: bearerToken,
                commonName: commonName,
                organization: organization
            )
        }
    }

    func createSelfSignedCertificateChain(
        keyAlias: String,
        config: CertificateConfigMessage?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onAux(completion) { try self.keys.createSelfSignedCertificateChain(keyAlias, config: config) }
    }

    // MARK: - Settings

    func loadSettings(settings: String, format: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) {
            let defaults = try self.defaultSettings ?? self.defaultLabelSettings()
            try self.load(into: defaults, settings, format: format)
            self.defaultSettings = defaults
        }
    }

    func createSettings(completion: @escaping (Result<Int64, Error>) -> Void) {
        onWorker(completion) { Int64(self.settingsHandles.store(try C2PASettings(json: "{\"version\":1}"))) }
    }

    func settingsUpdateFromString(
        handle: Int64,
        settings: String,
        format: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        onWorker(completion) { try self.load(into: try self.settingsFor(handle), settings, format: format) }
    }

    func settingsSetValue(handle: Int64, path: String, jsonValue: String, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) {
            guard let data = jsonValue.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                throw PluginError.invalidArgument("Setting value for \(path) is not valid JSON")
            }
            try self.settingsFor(handle).setValue(value, forPath: path)
        }
    }

    func settingsDispose(handle: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { self.settingsHandles.remove(Int(handle)) }
    }

    // MARK: - Contexts

    func createContext(
        settingsHandle: Int64?,
        signer: SignerMessage?,
        reportProgress: Bool,
        httpResolver: HttpResolverModeMessage?,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        onWorker(completion) {
            Int64(try self.makeContext(
                settingsHandle: settingsHandle,
                signer: signer,
                reportProgress: reportProgress,
                httpResolver: httpResolver
            ))
        }
    }

    private func makeContext(
        settingsHandle: Int64?,
        signer signerMessage: SignerMessage?,
        reportProgress: Bool,
        httpResolver: HttpResolverModeMessage?
    ) throws -> Int {
        let settings = try settingsHandle.map { try settingsFor($0) }
        let handle = contexts.reserve()
        let bridge = self.bridge
        let signer = try signerMessage.map { try signers.create($0) }

        var onProgress: (@Sendable (ProgressUpdate) -> ProgressDisposition)?
        if reportProgress {
            onProgress = { @Sendable (update: ProgressUpdate) -> ProgressDisposition in
                bridge.progress(
                    contextHandle: Int64(handle),
                    phase: progressPhaseName(update.phase),
                    step: Int64(update.step),
                    total: Int64(update.total)
                )
                return ProgressDisposition.continue
            }
        }

        let context: C2PAContext
        switch httpResolver {
        case nil:
            context = try C2PAContext(settings: settings, signer: signer, onProgress: onProgress, httpResolver: nil)
        case .native?:
            context = try C2PAContext(
                settings: settings,
                signer: signer,
                onProgress: onProgress,
                urlSession: URLSession(configuration: .default)
            )
        case .callback?:
            let resolver: @Sendable (HTTPRequest) throws -> HTTPResponse = { (request: HTTPRequest) throws -> HTTPResponse in
                let response = try bridge.resolveHttp(
                    contextHandle: Int64(handle),
                    request: HttpRequestMessage(
                        url: request.url.absoluteString,
                        method: request.method,
                        headers: request.headers,
                        body: request.body.map { FlutterStandardTypedData(bytes: $0) }
                    )
                )
                guard let status = Int(exactly: response.status), (0...999).contains(status) else {
                    throw C2PAError.api("HTTP resolver status \(response.status) is out of range")
                }
                return HTTPResponse(status: status, body: response.body?.data ?? Data())
            }
            context = try C2PAContext(settings: settings, signer: signer, onProgress: onProgress, httpResolver: resolver)
        }
        contexts.put(handle, context)
        return handle
    }

    func contextCancel(handle: Int64) throws {
        do {
            guard let context = contexts.get(Int(handle)) else {
                throw PluginError.invalidHandle("context")
            }
            try context.cancel()
        } catch {
            throw Self.pigeonError(error)
        }
    }

    func contextDispose(handle: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        onWorker(completion) { self.contexts.remove(Int(handle)) }
    }

    // MARK: - Handle lookup and factories

    private func builder(_ handle: Int64) throws -> Builder {
        guard let builder = builders.get(Int(handle)) else {
            throw PluginError.invalidHandle("builder")
        }
        return builder
    }

    private func settingsFor(_ handle: Int64) throws -> C2PASettings {
        guard let settings = settingsHandles.get(Int(handle)) else {
            throw PluginError.invalidHandle("settings")
        }
        return settings
    }

    /// The context for [handle], a fresh one built from the default settings,
    /// or nil to let the SDK use its own default context.
    private func contextFor(_ handle: Int64?) throws -> C2PAContext? {
        if let handle = handle {
            guard let context = contexts.get(Int(handle)) else {
                throw PluginError.invalidHandle("context")
            }
            return context
        }
        if let defaults = defaultSettings {
            return try C2PAContext(settings: defaults)
        }
        return nil
    }

    private func newReader(_ contextHandle: Int64?, format: String, stream: Stream) throws -> Reader {
        if let context = try contextFor(contextHandle) {
            return try Reader(context: context, format: format, stream: stream)
        }
        return try Reader(format: format, stream: stream)
    }

    /// Builders created without a context get the settings c2pa-android's
    /// `Builder.fromJson` applies, so both platforms record the same
    /// assertions as created rather than gathered.
    private func newBuilder(_ contextHandle: Int64?, _ manifestJson: String) throws -> Builder {
        if let context = try contextFor(contextHandle) {
            return try Builder(context: context, manifestJSON: manifestJson)
        }
        let context = try C2PAContext(settings: try defaultLabelSettings())
        return try Builder(context: context, manifestJSON: manifestJson)
    }

    /// The assertion labels c2pa-android's `Builder.DEFAULT_CREATED_ASSERTION_LABELS` lists.
    private static let defaultCreatedAssertionLabels = [
        "c2pa.actions",
        "c2pa.actions.v2",
        "c2pa.thumbnail.claim",
        "c2pa.thumbnail.ingredient",
        "c2pa.ingredient",
        "c2pa.ingredient.v3",
    ]

    /// Fresh settings carrying only the default created-assertion labels.
    private func defaultLabelSettings() throws -> C2PASettings {
        let settings: [String: Any] = [
            "version": 1,
            "builder": ["created_assertion_labels": Self.defaultCreatedAssertionLabels],
        ]
        let data = try JSONSerialization.data(withJSONObject: settings)
        return try C2PASettings(json: String(decoding: data, as: UTF8.self))
    }

    private func load(into settings: C2PASettings, _ text: String, format: String) throws {
        switch format.lowercased() {
        case "json": try settings.load(json: text)
        case "toml": try settings.load(toml: text)
        default: throw PluginError.invalidArgument("format must be 'json' or 'toml'")
        }
    }

    private func parseAction(_ json: String) throws -> Action {
        guard let data = json.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["action"] as? String else {
            throw PluginError.invalidArgument("actionJson must be an object with an 'action' string")
        }
        let parameters = (dict["parameters"] as? [String: Any])?.mapValues { AnyCodable($0) }
        let softwareAgent: AnyCodable? = dict["softwareAgent"].flatMap { $0 is NSNull ? nil : AnyCodable($0) }
        return Action(
            action: name,
            digitalSourceType: dict["digitalSourceType"] as? String,
            softwareAgent: softwareAgent,
            parameters: parameters,
            when: dict["when"] as? String
        )
    }
}
