import Foundation
import HFRClient
import HFRModels
import HFRNetwork

/// Where the Alertes Qualitay list comes from: the AQ feed, every category (hiding one is the model's policy, Q-7).
protocol QualityAlertsSource: Sendable {
    /// The feed items, in the order the service gives them.
    func feed() async throws(AQError) -> [AQFeedItem]
}

/// The live feed: `AQClient` over the cookie-less transport (LOT-055, LOT-071 R1).
struct LiveQualityAlertsSource: QualityAlertsSource {
    let client: AQClient

    func feed() async throws(AQError) -> [AQFeedItem] {
        try await client.feed()
    }

    /// The source for the build's `AQBaseURL` (`App/Config/Info-Keys.plist`, from `AQ_BASE_URL`, ADR 0007); nil when the build
    /// carries none or one `AQConfiguration` refuses, so the entry then shows its list as unavailable instead of guessing a host.
    static func configured(from info: [String: Any]) -> LiveQualityAlertsSource? {
        guard let text = (info[baseURLKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("$("), let url = URL(string: text),
              let configuration = try? AQConfiguration(baseURL: url) else { return nil }
        return LiveQualityAlertsSource(client: AQClient(configuration: configuration))
    }

    /// The Info.plist key holding the AQ origin.
    static let baseURLKey = "AQBaseURL"
}
