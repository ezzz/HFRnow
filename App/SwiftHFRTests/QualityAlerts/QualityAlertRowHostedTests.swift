import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1160: VoiceOver hears « Nouvelle » on a new alert, through the real row (a `Button` around the combined element, as the
/// list builds it), not only through the model's string.
@MainActor
@Suite(.serialized)
struct QualityAlertRowHostedTests {
    typealias Support = QualityAlertsTestSupport

    /// The accessibility values of every element of the hosted row whose label holds the row's title.
    private func values(of row: QualityAlertsModel.Row) async throws -> [String] {
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 400)
        window.rootViewController = UIHostingController(rootView: List { QualityAlertRow(row: row, now: .now) {} })
        window.isHidden = false
        defer { window.isHidden = true }
        var found: [NSObject] = []
        for _ in 0..<100 where found.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            found = HostedAccessibility.elements(under: window).filter { $0.accessibilityLabel?.contains(row.title) == true }
        }
        try #require(!found.isEmpty, "the row is not in the accessibility tree")
        return found.map { $0.accessibilityValue ?? "" }
    }

    @Test(.timeLimit(.minutes(1)))
    func aNewRowIsSpokenAsNewAndASeenOneIsNot() async throws {
        // With the oracle's last check two rows are new and 23 are seen; an empty store would make all 25 new.
        let store = InMemorySettingsStore()
        store.set(Support.lastCheckOfTheOracle, for: SettingKey.aqLastCheck)
        let model = Support.model(source: FakeQualityAlertsSource(items: try Support.capturedItems()), store: store)
        await model.load()
        let new = try #require(model.rows.first(where: { $0.isNew && $0.target != nil }))
        let seen = try #require(model.rows.first(where: { !$0.isNew && $0.target != nil }))
        #expect(try await values(of: new).contains("Nouvelle"))
        #expect(try await !values(of: seen).contains("Nouvelle"))
    }
}
