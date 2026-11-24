import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-159 R12: a post read in the filtered posts sheet can be reported and its author blocked, as in the reader (App Review
/// guideline 1.2; legacy showed the filtered posts with every menu, `MessagesView.swift:4767-4791` @ 87fe0d1c).
@MainActor
struct FilteredPostsMenuModelTests {
    private static let mail = "moderation@example.org"

    private struct PassNormalizer: MessageContentNormalizing {
        func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
            MessageContent(html: contentHTML)
        }
    }

    /// Two posts of `autre` and one of `moi`, read on pages 3, 5 and 5, as the filter hands them (cookie-less: no action link).
    private func result() async throws -> FilteredPostsResult {
        let posts = [(3, 301, "autre"), (5, 502, "autre"), (5, 510, "moi")].map { page, number, author in
            FilteredPost(
                page: page, block: MessageBlock(numreponse: number, author: author, dateText: "27-10-2026", contentHTML: "<p>x</p>"),
                quotes: []
            )
        }
        let batch = FilteredPostsBatch(posts: posts, startPage: 3, endPage: 5, maxPage: 9, isFinished: false)
        return try await FilteredPostsModel.result(of: batch, topic: filterTopic, title: "Sujet", normalizer: PassNormalizer())
    }

    /// The services as `AppEnvironment.make` wires them: the render options read the lists' snapshot, which a toggle refreshes.
    private func services(account: String?, mail: String? = mail) -> (ReaderServices, PseudoListStore) {
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let snapshot = PseudoListsSnapshot(store: store, account: account)
        var services = ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: .live(
                store: InMemorySettingsStore(), isOnWiFi: { true }, pseudo: account, pseudoLists: { snapshot.current }
            ),
            profiles: FakeUserProfiles([])
        )
        services.pseudoLists = PseudoListManager(store: store, account: account, snapshot: snapshot)
        services.moderatorAlertMail = mail
        return (services, store)
    }

    private func menus(
        account: String? = "moi", mail: String? = mail, copied: @escaping @MainActor (URL) -> Void = { _ in }
    ) -> (FilteredPostsMenuModel, PseudoListStore) {
        let (services, store) = services(account: account, mail: mail)
        return (FilteredPostsMenuModel(services: services, copy: copied, openMail: { _ in }), store)
    }

    @Test func theBatchKnowsThePageOfEachPost() async throws {
        #expect(try await result().pages == [301: 3, 502: 5, 510: 5])
    }

    @Test func eachPostLinksToThePageItWasReadOn() async throws {
        let result = try await result()
        #expect(FilteredPostsMenuModel.permalink(of: 502, in: result)?.absoluteString
            == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=5#t502")
        #expect(FilteredPostsMenuModel.permalink(of: 999, in: result) == nil)
    }

    @Test func theDocumentDrawsTheMessageAndAuthorMenus() {
        let options = menus().0.renderOptions()
        #expect(options.showsMessageMenus)
        #expect(options.showsAuthorMenus)
    }

    @Test func anotherMembersPostCanBeReported() async throws {
        let menu = try #require(menus().0.menu(post: 502, source: .message, anchor: nil, in: try await result()))
        #expect(menu.entries == [.link, .alert])
        #expect(menu.context.permalinkURL == FilteredPostsMenuModel.permalink(of: 502, in: try await result()))
    }

    @Test func reportingPreparesTheModeratorsMailWithThePostsLink() async throws {
        let (model, _) = menus()
        let result = try await result()
        let menu = try #require(model.menu(post: 301, source: .message, anchor: nil, in: result))
        await model.perform(.alert, in: menu)
        let mail = try #require(model.alerts?.pendingMail?.absoluteString)
        #expect(mail.hasPrefix("mailto:\(Self.mail)?"))
        #expect(mail.contains("page%3D3%23t301"))
    }

    @Test func anotherMembersAuthorCanBeBlocked() async throws {
        let (model, store) = menus()
        let menu = try #require(model.menu(post: 301, source: .avatar, anchor: nil, in: try await result()))
        #expect(menu.entries == [.blocklist, .allowlist])
        await model.perform(.blocklist, in: menu)
        #expect(await store.blocklist(for: "moi").map(\.pseudo) == ["autre"])
        #expect(model.listsRevision == 1)
        #expect(model.menuFeedback == "BIM! autre ajouté à la liste noire")
    }

    // Fable r1290 #4: the block is seen in the sheet. Built before and after the block, from the model's own document, as
    // `FilteredPostsView.rebuild` does; the rebuild keeps the scroll position.
    @Test func aBlockedAuthorsPostsAreMaskedInTheRebuiltDocument() async throws {
        let (model, _) = menus()
        let result = try await result()
        let before = model.document(for: result, token: 1, keepsScrollPosition: false)
        #expect(!before.html.contains("class=\"message blocked\""))
        let menu = try #require(model.menu(post: 301, source: .avatar, anchor: nil, in: result))
        await model.perform(.blocklist, in: menu)
        let after = model.document(for: result, token: 2, keepsScrollPosition: true)
        #expect(after.keepsScrollPosition)
        #expect(after.html.components(separatedBy: "class=\"message blocked\"").count - 1 == 2, "both posts of autre")
        #expect(!after.html.contains("class=\"message blocked\" id=\"t510\""), "the user's own post stays")
    }

    @Test func loggedOutTheAuthorMenuOffersTheAllowlistOnly() async throws {
        let menu = try #require(menus(account: nil).0.menu(post: 301, source: .avatar, anchor: nil, in: try await result()))
        #expect(menu.entries == [.allowlist])
    }

    @Test func theUsersOwnPostIsNeitherReportedNorListed() async throws {
        let (model, _) = menus(account: "Moi")
        let result = try await result()
        #expect(model.menu(post: 510, source: .message, anchor: nil, in: result)?.entries == [.link])
        #expect(model.menu(post: 510, source: .avatar, anchor: nil, in: result) == nil)
    }

    // Fable r1290 #1: the account key is the URL-encoded `md_user`; the page prints the pseudo.
    @Test func theUsersOwnPostIsFoundFromAURLEncodedAccountKey() async throws {
        let (model, _) = menus(account: "%6Doi")
        let result = try await result()
        #expect(model.menu(post: 510, source: .message, anchor: nil, in: result)?.entries == [.link])
        #expect(model.menu(post: 510, source: .avatar, anchor: nil, in: result) == nil)
    }

    @Test func linkCopiesThePermalink() async throws {
        var copied: URL?
        let (model, _) = menus(copied: { copied = $0 })
        let result = try await result()
        let menu = try #require(model.menu(post: 301, source: .message, anchor: nil, in: result))
        await model.perform(.link, in: menu)
        #expect(copied == FilteredPostsMenuModel.permalink(of: 301, in: result))
        #expect(model.menuFeedback == "Lien copié")
    }

    @Test func aPostTheBatchDoesNotHoldOpensNothing() async throws {
        #expect(menus().0.menu(post: 999, source: .message, anchor: nil, in: try await result()) == nil)
    }
}
