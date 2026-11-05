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

/// Where the uploaded images of the composer are remembered (LOT-064, legacy `RehostUploadHistoryStore`, `ReplyService.swift:1895`
/// @ 2440d79).
protocol ImageUploadHistoryStoring: Sendable {
    /// The remembered uploads, newest first, and whether the stored data is unreadable (writes are then refused, never overwritten).
    func load() async -> (images: [RehostedImage], isUnreadable: Bool)
    /// Remembers an upload at the top.
    func add(_ image: RehostedImage) async throws
    /// Forgets the upload with this `RehostedImage.id`.
    func remove(id: String) async throws
}

/// The history over the engine's `RehostUploadHistoryStore` (versioned file, unreadable data kept aside, never overwritten).
struct LiveImageUploadHistory: ImageUploadHistoryStoring {
    let store: RehostUploadHistoryStore

    /// The file under Application Support. One store per process (one actor per file): see `ImageUploadServices.liveHistory`.
    fileprivate static func make() -> LiveImageUploadHistory {
        LiveImageUploadHistory(store: RehostUploadHistoryStore(
            persistence: FileSmallStorePersistence(fileURL: URL.applicationSupportDirectory.appending(path: "RehostHistory/uploads.json"))
        ))
    }

    func load() async -> (images: [RehostedImage], isUnreadable: Bool) {
        let failure = await store.loadFailure()
        return (await store.images(), failure != nil)
    }

    func add(_ image: RehostedImage) async throws { try await store.add(image) }

    func remove(id: String) async throws { try await store.remove(id: id) }
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

    /// The single history store of the app: two stores over one file could overwrite each other's writes.
    static let liveHistory = LiveImageUploadHistory.make()

    /// The app's live services: the key comes from the bundle, never from the source.
    static func live(bundle: Bundle = .main) -> ImageUploadServices {
        let configuration = Self.configuration(from: bundle.infoDictionary ?? [:])
        return ImageUploadServices(
            uploader: configuration.map { RehostClient(configuration: $0) },
            hostName: configuration?.baseURL.host,
            preparer: ImageIOPreparer(),
            history: liveHistory,
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
