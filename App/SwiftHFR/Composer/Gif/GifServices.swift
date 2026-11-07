import Foundation
import HFRNetwork
import HFRStorage

/// What the GIF panel needs: the Giphy client (nil when this build has no key), its host name and the settings.
struct GifServices: Sendable {
    /// The Giphy client; nil when the build carries no key (ADR 0007): the composer then shows no GIF button.
    let client: GiphyClient?
    /// The host's name for the first-use notice (N1), from the injected base URL.
    let hostName: String?
    /// Holds the notice flag.
    let settings: any SettingsStore

    /// Build settings read from the app's `Info.plist`: `GiphyBaseURL` and `GiphyAPIKey` (ADR 0007, `App/Config/`).
    static let baseURLKey = "GiphyBaseURL"
    static let apiKeyKey = "GiphyAPIKey"

    /// This build can search (a key was injected): the entry point is shown only then.
    var isAvailable: Bool { client != nil }

    /// The app's live services: the key comes from the bundle, never from the source. Nothing is contacted here.
    static func live(bundle: Bundle = .main) -> GifServices {
        let configuration = Self.configuration(from: bundle.infoDictionary ?? [:])
        return GifServices(
            client: configuration.map { GiphyClient(configuration: $0) },
            hostName: configuration?.baseURL.host,
            settings: UserDefaultsSettingsStore()
        )
    }

    /// The injected configuration, nil when a value is absent, blank or an unexpanded `$(NAME)` build setting.
    static func configuration(from info: [String: Any]) -> GiphyConfiguration? {
        guard let base = (info[baseURLKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (info[apiKeyKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.hasPrefix("$("), !key.hasPrefix("$("), let url = URL(string: base) else { return nil }
        return try? GiphyConfiguration(baseURL: url, apiKey: key)
    }
}

/// Which media URLs the picker previews and posts: Giphy's own CDN over `https`, nothing else (LOT-098 edge case: the client only
/// checks `https`, so an altered API host could point a GIF anywhere).
enum GifMediaPolicy {
    /// `https` on `giphy.com` or one of its subdomains, without user info.
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user() == nil, url.password() == nil,
              let host = url.host()?.lowercased() else { return false }
        return host == "giphy.com" || host.hasSuffix(".giphy.com")
    }
}
