import Foundation
import HFRModels
import HFRNetwork
import HFRStorage

/// Uploads prepared JPEG bytes to the image host; `RehostClient` in the app, a script in tests.
protocol ImageUploading: Sendable {
    /// Uploads `jpeg` and returns the hosted image, or throws the host's own refusal.
    func upload(jpeg: Data) async throws(RehostError) -> RehostedImage
}

extension RehostClient: ImageUploading {}

/// Where the uploaded images of the composer are remembered (legacy `RehostUploadHistoryStore`, `ReplyService.swift:1895` @ 2440d79).
protocol ImageUploadHistoryStoring: Sendable {
    /// The remembered uploads, newest first; empty when nothing was saved. Throws when the file exists but cannot be read.
    func load() throws -> [RehostedImage]
    /// Replaces the remembered uploads.
    func save(_ images: [RehostedImage]) throws
}

/// The history as one JSON file, written atomically.
struct FileImageUploadHistory: ImageUploadHistoryStoring {
    let fileURL: URL

    func load() throws -> [RehostedImage] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try Self.decoder.decode([RehostedImage].self, from: Data(contentsOf: fileURL))
    }

    func save(_ images: [RehostedImage]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(images).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// What the image panel needs: the uploader (nil when this build has no key), its settings and its notice.
struct ImageUploadServices: Sendable {
    /// The host client; nil when the build carries no key (ADR 0007): uploading is then off, manual links still work.
    let uploader: (any ImageUploading)?
    /// The host's name for the first-use notice (N1), from the injected base URL.
    let hostName: String?
    let preparer: any ImagePreparing
    let history: any ImageUploadHistoryStoring
    /// Holds `rehost_use_link`, `rehost_resize_before_upload` and the notice flag.
    let settings: any SettingsStore

    /// Build settings read from the app's `Info.plist`: `RehostBaseURL` and `RehostAPIKey` (ADR 0007, wired by the Mac check).
    static let baseURLKey = "RehostBaseURL"
    static let apiKeyKey = "RehostAPIKey"

    /// The app's live services: the key comes from the bundle, never from the source.
    static func live(bundle: Bundle = .main) -> ImageUploadServices {
        let configuration = Self.configuration(from: bundle.infoDictionary ?? [:])
        return ImageUploadServices(
            uploader: configuration.map { RehostClient(configuration: $0) },
            hostName: configuration?.baseURL.host,
            preparer: ImageIOPreparer(),
            history: FileImageUploadHistory(fileURL: URL.applicationSupportDirectory.appending(path: "RehostHistory/uploads.json")),
            settings: UserDefaultsSettingsStore()
        )
    }

    /// The injected configuration, nil when a value is absent, blank or an unexpanded `$(NAME)` build setting.
    static func configuration(from info: [String: Any]) -> RehostConfiguration? {
        guard let base = (info[baseURLKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (info[apiKeyKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.hasPrefix("$("), !key.hasPrefix("$("), let url = URL(string: base) else { return nil }
        return try? RehostConfiguration(baseURL: url, apiKey: key)
    }
}
