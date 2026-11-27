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
import Foundation

/// An error reported to Dart with an explicit code.
struct PluginError: Error {
    let code: String
    let message: String

    static func invalidArgument(_ message: String) -> PluginError {
        PluginError(code: "INVALID_ARGUMENT", message: message)
    }

    static func invalidHandle(_ kind: String) -> PluginError {
        PluginError(code: "INVALID_HANDLE", message: "Invalid \(kind) handle")
    }

    static func notImplemented(_ message: String) -> PluginError {
        PluginError(code: "NOT_IMPLEMENTED_IOS", message: message)
    }
}

/// Thread-safe map from Dart-visible integer handles to native objects.
final class HandleRegistry<T> {
    private var items: [Int: T] = [:]
    private var next = 1
    private let lock = NSLock()

    func reserve() -> Int {
        lock.lock(); defer { lock.unlock() }
        let handle = next
        next += 1
        return handle
    }

    func put(_ handle: Int, _ item: T) {
        lock.lock(); defer { lock.unlock() }
        items[handle] = item
    }

    func store(_ item: T) -> Int {
        let handle = reserve()
        put(handle, item)
        return handle
    }

    func get(_ handle: Int) -> T? {
        lock.lock(); defer { lock.unlock() }
        return items[handle]
    }

    @discardableResult
    func remove(_ handle: Int) -> T? {
        lock.lock(); defer { lock.unlock() }
        return items.removeValue(forKey: handle)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        items.removeAll()
    }
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path)
}

/// Opens an existing file for reading; a missing file is an argument error.
func openForRead(_ path: String) throws -> Stream {
    guard FileManager.default.fileExists(atPath: path) else {
        throw PluginError.invalidArgument("File not found: \(path)")
    }
    return try Stream(readFrom: fileURL(path))
}

/// Opens a destination file for writing, replacing anything already there.
func openForWrite(_ path: String) throws -> Stream {
    let url = fileURL(path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    return try Stream(writeTo: url)
}

/// A write-only stream that collects everything written to it.
final class DataSink {
    private(set) var data = Data()

    func stream() throws -> Stream {
        try Stream(
            write: { [unowned self] buffer, count in
                self.data.append(Data(bytes: buffer, count: count))
                return count
            },
            flush: { 0 }
        )
    }
}

/// A temporary file for sign destinations, removed when the value is released.
final class TempFile {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func contents() throws -> Data {
        try Data(contentsOf: url)
    }
}

func mimeTypeForPath(_ path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "webp": return "image/webp"
    case "avif": return "image/avif"
    case "heic": return "image/heic"
    case "heif": return "image/heif"
    case "gif": return "image/gif"
    case "tiff", "tif": return "image/tiff"
    case "dng": return "image/x-adobe-dng"
    case "mp4", "m4v": return "video/mp4"
    case "mov": return "video/quicktime"
    case "m4a": return "audio/mp4"
    case "mp3": return "audio/mpeg"
    case "wav": return "audio/wav"
    case "pdf": return "application/pdf"
    case "svg": return "image/svg+xml"
    default: return "application/octet-stream"
    }
}

extension SigningAlgorithmMessage {
    var sdk: SigningAlgorithm {
        switch self {
        case .es256: return .es256
        case .es384: return .es384
        case .es512: return .es512
        case .ps256: return .ps256
        case .ps384: return .ps384
        case .ps512: return .ps512
        case .ed25519: return .ed25519
        }
    }

    /// The algorithm's name as Dart spells it, for messages.
    var dartName: String { String(describing: self) }
}

/// IPTC digital source type URL for a Dart `DigitalSourceType` name.
func digitalSourceTypeURL(_ name: String) -> String {
    "http://cv.iptc.org/newscodes/digitalsourcetype/\(name)"
}

/// Maps a Dart `DigitalSourceType` name to the c2pa-swift enum. Returns nil
/// for the types c2pa-swift does not model (empty, trainedAlgorithmicData,
/// computationalCapture).
func parseDigitalSourceType(_ name: String) -> DigitalSourceType? {
    DigitalSourceType(rawValue: digitalSourceTypeURL(name))
}

func hashTypeMessage(_ type: HashType) -> HashTypeMessage {
    switch type {
    case .dataHash: return .dataHash
    case .bmffHash: return .bmffHash
    case .boxHash: return .boxHash
    }
}

func progressPhaseName(_ phase: ProgressPhase) -> String {
    switch phase {
    case .reading: return "reading"
    case .verifyingManifest: return "verifyingManifest"
    case .verifyingSignature: return "verifyingSignature"
    case .verifyingIngredient: return "verifyingIngredient"
    case .verifyingAssetHash: return "verifyingAssetHash"
    case .addingIngredient: return "addingIngredient"
    case .thumbnail: return "thumbnail"
    case .hashing: return "hashing"
    case .signing: return "signing"
    case .embedding: return "embedding"
    case .fetchingRemoteManifest: return "fetchingRemoteManifest"
    case .writing: return "writing"
    case .fetchingOCSP: return "fetchingOcsp"
    case .fetchingTimestamp: return "fetchingTimestamp"
    case .unknown: return "unknown"
    }
}

