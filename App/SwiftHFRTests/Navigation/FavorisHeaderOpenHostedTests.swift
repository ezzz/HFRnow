import Foundation
import HFRModels
import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

// Diagnostic for #979 (test only, no fix): a tap on a section title in Favoris freezes the app on the device (compact
// density, sectioned). This hosts the Favoris `TopicsColumn`, drives what the header's button calls
// (`NavigationModel.openCategory`) and logs each step to stderr, so a hang shows where it stops. A watchdog thread reports a
// stalled main thread and ends the run.

/// Where the main actor last was, readable from the watchdog thread.
private final class HangProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var step = "start"
    private var beat = Date()
    private var stopped = false

    func mark(_ name: String) {
        lock.withLock {
            step = name
            beat = Date()
        }
        FileHandle.standardError.write(Data("[#979] \(name)\n".utf8))
    }

    func heartbeat() { lock.withLock { beat = Date() } }

    /// Ends the watch with the test: a watchdog that outlives it would end the host process in the middle of another test.
    func stop() { lock.withLock { stopped = true } }

    private var isStopped: Bool { lock.withLock { stopped } }

    var snapshot: (step: String, silence: TimeInterval) { lock.withLock { (step, Date().timeIntervalSince(beat)) } }

    /// Ends the run, naming the step, when the main actor stays silent for `limit` seconds.
    func watch(limit: TimeInterval) {
        Thread.detachNewThread { [self] in
            while !isStopped {
                Thread.sleep(forTimeInterval: 1)
                if isStopped { return }
                let state = snapshot
                if state.silence > limit {
                    let line = "[#979] HANG: main actor silent \(Int(state.silence)) s after step '\(state.step)'\n"
                    FileHandle.standardError.write(Data(line.utf8))
                    exit(1)
                }
            }
        }
    }
}

@MainActor
@Suite(.serialized)
struct FavorisHeaderOpenHostedTests {
    @Test(
        "A section title opens its category on the Favoris stack, in compact and regular density (#979)",
        .timeLimit(.minutes(1)), arguments: [ListDensity.compact, ListDensity.regular]
    )
    func openingACategoryFromTheHeaderPushesIt(density: ListDensity) async throws {
        let progress = HangProgress()
        progress.watch(limit: 45)
        defer { progress.stop() }
        progress.mark("\(density): setup")
        let data = FakeDataSource()
        data.favoritesHandler = { _ in
            FavoritesPage(sections: [
                favoriteSection(13, [favoriteTopic(1), favoriteTopic(2)]), favoriteSection(14, [favoriteTopic(3, category: 14)])
            ])
        }
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.groupedByCategory = true
        let filter = TopicFilterModel(settings: InMemorySettingsStore())
        let navigation = NavigationModel(dataSource: data, startupSource: .flagged, favorites: options, topicFilter: filter)

        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            Issue.record("no window scene")
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(
            rootView: ThemedNavigationStack { TopicsColumn(navigation: navigation, composer: nil) }.environment(\.listDensity, density)
        )
        window.isHidden = false
        defer { window.isHidden = true }

        // Wait for the sections to load and render.
        let list = navigation.topicList(for: .flagged)
        for _ in 0..<100 where list.displayedGroups.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            progress.heartbeat()
        }
        progress.mark("\(density): favourites loaded, \(list.displayedGroups.count) sections")
        let category = try #require(list.displayedGroups.first?.opens, "the section names its category")

        // What the header's button does (`TopicListView.header` -> `NavigationModel.openCategory`), step by step.
        progress.mark("\(density): before the topicFilter write")
        filter.flag = .favorites
        progress.mark("\(density): after the topicFilter write")
        navigation.openedCategory = category
        progress.mark("\(density): after openedCategory")

        // The pushed list loads its topics once on screen.
        for _ in 0..<100 where !data.requests.contains(where: { $0.hasPrefix("topics:") }) {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            progress.heartbeat()
        }
        progress.mark("\(density): requests \(data.requests)")
        #expect(data.requests.contains { $0.hasPrefix("topics:") }, "the category list was pushed and asked for its topics")
        progress.mark("\(density): done")
    }
}
