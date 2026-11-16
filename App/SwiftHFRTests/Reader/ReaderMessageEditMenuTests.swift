import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// Issue #594 (operator decision of 2026-11-15): the post's "+" opens legacy's horizontal edit-menu callout right at the button
/// (`presentPopupMenu`, `popupAnchor`, `MessagesView.swift:2011-2081` @ 87fe0d1c), never away from it; the author menu keeps
/// its popover.
@MainActor
@Suite(.serialized)
struct ReaderMessageEditMenuTests: ReaderWebTesting {
    private let bounds = CGRect(x: 0, y: 0, width: 390, height: 800)

    private func menu(_ source: MessageMenuSource = .message, anchor: CGRect? = nil, entries: [MessageMenuAction]? = nil)
        -> MessageMenu {
        MessageMenu(
            post: 7, source: source, context: MessageMenuContext(numreponse: 7, author: "auteur", actions: MessageActions()),
            entries: entries ?? [.quote, .quoteSelection(isSelected: false), .favorite, .link, .alert], anchor: anchor
        )
    }

    @Test func midPageTheCalloutOpensAboveTheButtonWithItsArrowOnIt() {
        let button = CGRect(x: 350, y: 480, width: 30, height: 30)
        let placement = ReaderMessageEditMenu.placement(of: button, topInset: 115, in: bounds)
        #expect(placement.target == button)
        #expect(placement.arrow == .down)
        #expect(placement.point == CGPoint(x: button.midX, y: button.minY))
    }

    /// Legacy opens it below a button within 40 points of the bars' edge (`popupAnchor`, :2071-2075 and `:2034`).
    @Test func rightUnderTheBarsTheCalloutOpensBelowTheButton() {
        let button = CGRect(x: 350, y: 130, width: 30, height: 30)
        let placement = ReaderMessageEditMenu.placement(of: button, topInset: 115, in: bounds)
        #expect(placement.arrow == .up)
        #expect(placement.point == CGPoint(x: button.midX, y: button.maxY))
    }

    /// The menu never opens at the top left: no anchor, or one off the web view, falls back to legacy's right edge under the
    /// bars (`popupAnchor`'s `fallbackX`, :2069).
    @Test func withoutAUsableAnchorTheCalloutStaysAtTheRightEdgeUnderTheBars() {
        for anchor in [nil, CGRect(x: 350, y: -500, width: 30, height: 30), CGRect(x: 350, y: 480, width: 0, height: 0)] {
            let placement = ReaderMessageEditMenu.placement(of: anchor, topInset: 115, in: bounds)
            #expect(placement.target.minX >= bounds.maxX - 16, "anchor \(String(describing: anchor))")
            #expect(placement.target.minY >= 115, "anchor \(String(describing: anchor))")
            #expect(bounds.contains(placement.point))
        }
    }

    @Test func aButtonCutByTheEdgeIsAnchoredOnItsVisiblePart() {
        let placement = ReaderMessageEditMenu.placement(of: CGRect(x: 375, y: 480, width: 30, height: 30), topInset: 0, in: bounds)
        #expect(placement.target == CGRect(x: 375, y: 480, width: 15, height: 30))
    }

    /// Legacy order (Citer, Citer ☐, Favoris, Link, then the rest behind "›"); only "Supprimer" is destructive.
    @Test func theCalloutListsTheEntriesInMenuOrder() {
        let entries: [MessageMenuAction] = [.quote, .quoteSelection(isSelected: false), .favorite, .link, .alert, .delete]
        let actions = ReaderMessageEditMenu.actions(for: menu(entries: entries)) { _ in }
        #expect(actions.map(\.title) == ["Citer", "Citer ☐", "Favoris", "Link", "Alerter", "Supprimer"])
        #expect(actions.map(\.title) == entries.map(\.title))
        #expect(actions.last?.attributes.contains(.destructive) == true)
        #expect(actions.dropLast().allSatisfy { !$0.attributes.contains(.destructive) })
    }

    /// The model's message menu goes to the callout, its author menu does not, and a menu the model dropped closes.
    @Test func theControllerShowsOnlyTheMessageMenuAsACallout() async {
        let (controller, _) = makeController(transport: imageTransport())
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), source: FakeTopicPages())
        let shown = menu(anchor: CGRect(x: 350, y: 480, width: 30, height: 30))
        controller.showMessageMenu(shown, of: reader)
        #expect(controller.messageMenu.shownMenu == shown)
        controller.showMessageMenu(nil, of: reader)
        #expect(controller.messageMenu.shownMenu == nil)
        controller.showMessageMenu(menu(.avatar), of: reader)
        #expect(controller.messageMenu.shownMenu == nil)
    }
}
