import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1158: VoiceOver hears « Conversation de groupe » on a group row, through the real row (combined element, icon hidden).
@MainActor
@Suite(.serialized)
struct MessageRowGroupHostedTests {
    private static let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1"

    private func rows() throws -> [PrivateMessageThread] {
        let body = try LiveTopicPageSourceTests.capture("R13u1-mp-list-recipient-unread.html")
        return try PrivateMessageListParser.parse(try #require(String(data: body, encoding: .utf8)), pageURL: Self.listURL).threads
    }

    /// The accessibility values of every element of the hosted row whose label holds the row's title.
    private func values(of thread: PrivateMessageThread) async throws -> [String] {
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 400)
        let list = List { MessageRowView(thread: thread, isUnread: false) }.listStyle(.plain)
        window.rootViewController = UIHostingController(rootView: list)
        window.isHidden = false
        defer { window.isHidden = true }
        let title = thread.summary.displayTitle
        var found: [NSObject] = []
        for _ in 0..<100 where found.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            found = HostedAccessibility.elements(under: window).filter { $0.accessibilityLabel?.contains(title) == true }
        }
        try #require(!found.isEmpty, "the row is not in the accessibility tree")
        return found.map { $0.accessibilityValue ?? "" }
    }

    @Test(.timeLimit(.minutes(1)))
    func aGroupRowIsSpokenAsAGroupAndAOneToOneRowIsNot() async throws {
        let threads = try rows()
        let group = try #require(threads.first { $0.isGroup })
        let single = try #require(threads.first { !$0.isGroup })
        #expect(try await values(of: group).contains("Conversation de groupe"))
        #expect(try await !values(of: single).contains("Conversation de groupe"))
    }
}
