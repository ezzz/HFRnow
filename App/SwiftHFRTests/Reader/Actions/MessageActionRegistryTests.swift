import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// A scripted handler: records what it ran with.
@MainActor
final class RecordingHandler: MessageActionHandler {
    let kind: MessageMenuAction.Kind
    var available: Bool
    private(set) var performed: [MessageMenuContext] = []

    init(_ kind: MessageMenuAction.Kind, available: Bool = true) {
        self.kind = kind
        self.available = available
    }

    func isAvailable(for context: MessageMenuContext) -> Bool { available }

    func perform(with context: MessageMenuContext) async { performed.append(context) }
}

/// The handler registry: what no merged lot implements is hidden, and a later lot plugs in without editing the policy.
@MainActor
struct MessageActionRegistryTests {
    private let permalink = url("https://forum.hardware.fr/hfr/c/s-sujet_1_1.htm#t42")

    private func context(_ actions: MessageActions = MessageActions()) -> MessageMenuContext {
        MessageMenuContext(numreponse: 42, author: "auteur", actions: actions, permalinkURL: permalink)
    }

    @Test func anActionWithoutAHandlerIsHidden() {
        let registry = MessageActionRegistry([RecordingHandler(.link)])
        let actions = MessageActions(editURL: url("https://forum.hardware.fr/message.php?e=1"))
        #expect(registry.entries(for: context(actions), source: .message) == [.link])
        #expect(MessageActionRegistry().entries(for: context(actions), source: .message) == [])
        #expect(!MessageActionRegistry().offers(.message) && !MessageActionRegistry().offers(.avatar))
    }

    @Test func eachMenuIsOfferedOnlyWhenOneOfItsActionsHasAHandler() {
        let linkOnly = MessageActionRegistry([RecordingHandler(.link)])
        #expect(linkOnly.offers(.message) && !linkOnly.offers(.avatar))
        let withProfile = MessageActionRegistry([RecordingHandler(.profile)])
        #expect(!withProfile.offers(.message) && withProfile.offers(.avatar))
    }

    @Test func aLaterLotPlugsInWithoutTheMenuPolicyChanging() {
        let actions = MessageActions(editURL: url("https://forum.hardware.fr/message.php?e=1"))
        let before = MessageActionRegistry([RecordingHandler(.link)])
        #expect(before.entries(for: context(actions), source: .message) == [.link])
        // The edit lot registers its handler: the entry appears in its place of the order (own message: no alert).
        let after = MessageActionRegistry([RecordingHandler(.link), RecordingHandler(.edit), RecordingHandler(.alert)])
        #expect(after.entries(for: context(actions), source: .message) == [.edit, .link])
        #expect(after.entries(for: context(), source: .message) == [.link, .alert])
    }

    @Test func aHandlerThatDeclinesHidesItsAction() {
        let link = RecordingHandler(.link, available: false)
        #expect(MessageActionRegistry([link]).entries(for: context(), source: .message) == [])
    }

    @Test func aqAndBookmarkAreOfferedByTheirHandlerOnly() {
        let quality = RecordingHandler(.qualityAlert)
        let bookmark = RecordingHandler(.bookmark, available: false)
        let registry = MessageActionRegistry([quality, bookmark])
        #expect(registry.entries(for: context(), source: .message) == [.qualityAlert])
        bookmark.available = true
        #expect(registry.entries(for: context(), source: .message) == [.qualityAlert, .bookmark])
    }

    @Test func performRunsTheHandlerOfTheKindWithTheContext() async {
        let alert = RecordingHandler(.alert)
        let registry = MessageActionRegistry([alert])
        let ran = await registry.perform(.alert, with: context())
        #expect(ran)
        #expect(alert.performed == [context()])
        let missing = await registry.perform(.delete, with: context())
        #expect(!missing)
    }

    @Test func performNeverRunsAHandlerThatDeclines() async {
        let alert = RecordingHandler(.alert, available: false)
        let ran = await MessageActionRegistry([alert]).perform(.alert, with: context())
        #expect(!ran)
        #expect(alert.performed.isEmpty)
    }

    @Test func linkCopiesThePermalinkAndConfirms() async {
        var copied: [URL] = []
        var confirmations: [String] = []
        let handler = LinkActionHandler(copy: { copied.append($0) }, confirm: { confirmations.append($0) })
        let registry = MessageActionRegistry([handler])
        _ = await registry.perform(.link, with: context())
        #expect(copied == [permalink])
        #expect(confirmations == ["Lien copié"])
    }

    @Test func linkWithoutAPermalinkIsNotOffered() async {
        var copied: [URL] = []
        let registry = MessageActionRegistry([LinkActionHandler(copy: { copied.append($0) }, confirm: { _ in })])
        var bare = context()
        bare.permalinkURL = nil
        #expect(registry.entries(for: bare, source: .message) == [])
        _ = await registry.perform(.link, with: bare)
        #expect(copied.isEmpty)
    }
}
