import Foundation
import HFRClient
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing

/// A scripted searcher: answers with a closure and records the queries.
private final class ScriptedSearcher: TopicSearching, @unchecked Sendable {
    typealias Handler = @Sendable (TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult
    private let lock = NSLock()
    private var recorded: [TopicSearchQuery] = []
    private let handler: Handler

    init(_ handler: @escaping Handler) { self.handler = handler }

    var queries: [TopicSearchQuery] { lock.withLock { recorded } }

    func search(_ query: TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult {
        lock.withLock { recorded.append(query) }
        return try await handler(query)
    }
}

/// `R52a`'s `Location`, absolute.
private let matchURL = url(
    "https://forum.hardware.fr/forum2.php?post=28563&cat=13&config=hfr.inc&cache=&page=1&sondage=0&owntopic=0"
        + "&word=NAPOLITAINE&spseudo=&currentnum=2666649#t2666649"
)

/// LOT-113: the in-topic search sheet's rules.
@MainActor
struct TopicSearchModelTests {
    private func model(_ searcher: ScriptedSearcher) -> TopicSearchModel {
        TopicSearchModel(topic: readerTopic, searcher: searcher)
    }

    @Test func aMatchOpensAtItsMessageNumber() async {
        let searcher = ScriptedSearcher { _ in .match(matchURL) }
        let sheet = model(searcher)
        sheet.word = " napolitaine "
        let target = await sheet.submit()
        // The Location's `page=1` is not trusted: the message number lets HFR pick the page (R25).
        #expect(target == ReaderTarget(source: .topic(readerTopic), anchor: 2_666_649, numreponse: 2_666_649))
        #expect(sheet.state == .idle)
        #expect(searcher.queries == [TopicSearchQuery(topic: readerTopic, word: "napolitaine", author: "", filterEnabled: false)])
    }

    @Test func theTargetReadsTheMessageNumberAndNotThePage() throws {
        // `R52a`'s Location as HFR sends it, resolved against the forum by the flow: `page=1`, message 2666649.
        let target = try #require(ReaderTarget(searchMatch: matchURL, topic: readerTopic))
        #expect(target.page == 1)
        #expect(target.anchor == 2_666_649)
        #expect(target.numreponse == 2_666_649)
        // A `page=` that differs from the message's page changes nothing.
        let other = try #require(ReaderTarget(
            searchMatch: url("https://forum.hardware.fr/forum2.php?post=28563&cat=13&page=7&currentnum=42#t42"), topic: readerTopic
        ))
        #expect(other == ReaderTarget(source: .topic(readerTopic), anchor: 42, numreponse: 42))
        // The topic is the searched one, never the link's.
        let foreign = try #require(ReaderTarget(
            searchMatch: url("https://forum.hardware.fr/forum2.php?post=1&cat=1&page=1#t42"), topic: readerTopic
        ))
        #expect(foreign.source == .topic(readerTopic))
        #expect(ReaderTarget(searchMatch: url("https://forum.hardware.fr/forum2.php?post=28563&cat=13#bas"), topic: readerTopic) == nil)
    }

    @Test func aMatchWithoutMessageNumberIsAMessageNotATarget() async {
        let searcher = ScriptedSearcher { _ in .match(url("https://forum.hardware.fr/forum2.php?post=28563&cat=13&page=1")) }
        let sheet = model(searcher)
        sheet.word = "a"
        #expect(await sheet.submit() == nil)
        #expect(sheet.state == .failed("Réponse inattendue du forum."))
    }

    @Test func noMatchIsAMessageInTheSheet() async {
        let sheet = model(ScriptedSearcher { _ in .noMatch })
        sheet.author = "someone"
        #expect(await sheet.submit() == nil)
        #expect(sheet.state == .failed("Aucun résultat n'a été trouvé."))
    }

    @Test func anAuthorAloneIsASearch() async {
        let searcher = ScriptedSearcher { _ in .noMatch }
        let sheet = model(searcher)
        sheet.author = " user1 "
        #expect(sheet.canSubmit)
        _ = await sheet.submit()
        #expect(searcher.queries.first?.author == "user1")
        #expect(searcher.queries.first?.word == "")
    }

    @Test func noCriterionSendsNothing() async {
        let searcher = ScriptedSearcher { _ in .noMatch }
        let sheet = model(searcher)
        sheet.word = "  "
        sheet.author = "\n"
        #expect(!sheet.canSubmit)
        #expect(await sheet.submit() == nil)
        #expect(searcher.queries.isEmpty)
        #expect(sheet.state == .idle)
    }

    @Test(arguments: [
        (TopicSearchError.missingToken, "Connecte-toi pour rechercher dans ce sujet."),
        (TopicSearchError.notLoggedIn(message: nil), "Connecte-toi pour rechercher dans ce sujet."),
        (TopicSearchError.rejected(message: "Token invalide"), "Token invalide"),
        (TopicSearchError.rejected(message: nil), "Le forum a refusé la recherche."),
        (TopicSearchError.network(.offline), "Impossible de joindre le forum."),
        (TopicSearchError.unrecognizedAnswer(message: nil), "Réponse inattendue du forum."),
        (TopicSearchError.invalidLocation(matchURL), "Réponse inattendue du forum.")
    ])
    func aFailureIsToldAndNeverOpensAnything(error: TopicSearchError, message: String) async {
        let sheet = model(ScriptedSearcher { (_) async throws(TopicSearchError) -> TopicSearchResult in throw error })
        sheet.word = "a"
        #expect(await sheet.submit() == nil)
        #expect(sheet.state == .failed(message))
        #expect(sheet.canSubmit) // the user can fix the criteria and try again
    }

    @Test func aSecondSubmitWhileSearchingSendsNothing() async {
        let gate = ReaderGate()
        let searcher = ScriptedSearcher { _ in await gate.wait(); return .noMatch }
        let sheet = model(searcher)
        sheet.word = "a"
        let first = Task { await sheet.submit() }
        await gate.untilArrived()
        #expect(sheet.state == .searching)
        #expect(!sheet.canSubmit)
        #expect(await sheet.submit() == nil)
        await gate.open()
        _ = await first.value
        #expect(searcher.queries.count == 1)
    }

    @Test func closingTheSheetDropsTheAnswer() async {
        let gate = ReaderGate()
        let searcher = ScriptedSearcher { _ in await gate.wait(); return .match(matchURL) }
        let sheet = model(searcher)
        sheet.word = "a"
        let running = Task { await sheet.submit() }
        await gate.untilArrived()
        sheet.cancel()
        #expect(sheet.state == .idle)
        await gate.open()
        #expect(await running.value == nil)
        #expect(sheet.state == .idle)
    }

    @Test func aCancelledSearchIsNotAFailure() async {
        let sheet = model(ScriptedSearcher { (_) async throws(TopicSearchError) -> TopicSearchResult in
            throw TopicSearchError.network(.cancelled)
        })
        sheet.word = "a"
        #expect(await sheet.submit() == nil)
        #expect(sheet.state == .idle)
    }

    @Test func aMatchOnThePageShownScrollsInPlace() async throws {
        let pages = FakeTopicPages()
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "Sujet", source: pages)
        await reader.onAppear()
        // `readerPage(page: 1)` holds messages 100 and 101.
        let target = try #require(ReaderTarget(
            searchMatch: url("https://forum.hardware.fr/forum2.php?post=28563&cat=13&page=1&currentnum=101#t101"), topic: readerTopic
        ))
        reader.follow(target)
        #expect(pages.requests.count == 1)
        #expect(reader.scrollRequest?.anchor == 101)
        #expect(reader.linkedReader == nil)
    }

    @Test func aMatchOnAnotherPageOpensAReaderAboveAtItsMessage() async throws {
        let pages = FakeTopicPages()
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "Sujet", source: pages)
        await reader.onAppear()
        let target = try #require(ReaderTarget(
            searchMatch: url("https://forum.hardware.fr/forum2.php?post=28563&cat=13&page=1&currentnum=301#t301"), topic: readerTopic
        ))
        reader.follow(target)
        #expect(reader.linkedReader?.requested == ReaderTarget(source: .topic(readerTopic), anchor: 301, numreponse: 301))
        #expect(pages.requests.count == 1) // the pushed reader loads when it appears
    }
}
