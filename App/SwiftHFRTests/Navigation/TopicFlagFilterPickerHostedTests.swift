import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// The segmented filter hosted in a window (#427): `.disabled` on a segment does nothing on iOS 27, so the binding itself must
/// refuse a choice legacy disables logged out (`MainWindow.swift:683-695` @ 87fe0d1c).
@MainActor
@Suite(.serialized)
struct TopicFlagFilterPickerHostedTests {
    private func segmentedControl(in view: UIView) -> UISegmentedControl? {
        if let control = view as? UISegmentedControl { return control }
        return view.subviews.lazy.compactMap { segmentedControl(in: $0) }.first
    }

    /// Hosts the picker, taps the segment at `index` and returns the persisted flag afterwards.
    private func tap(segment index: Int, canFilter: Bool, stored: TopicListFlag) async -> TopicListFlag? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return nil
        }
        let store = InMemorySettingsStore([SettingKey.topicListFlag.key: .int(stored.rawValue)])
        let filter = TopicFilterModel(settings: store)
        let host = UIHostingController(rootView: TopicFlagFilterPicker(filter: filter, canFilter: canFilter))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 200)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var control: UISegmentedControl?
        for _ in 0..<200 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            control = segmentedControl(in: host.view)
            if control != nil { break }
        }
        guard let control else { return nil }
        control.selectedSegmentIndex = index
        control.sendActions(for: .valueChanged)
        try? await Task.sleep(for: .milliseconds(100))
        return TopicFilterModel(settings: store).flag
    }

    @Test func loggedOutATapOnFavorisLeavesThePersistedChoiceAlone() async {
        #expect(await tap(segment: 1, canFilter: false, stored: .tracked) == .tracked)
    }

    @Test func loggedInATapOnFavorisIsStored() async {
        #expect(await tap(segment: 1, canFilter: true, stored: .all) == .favorites)
    }
}
