import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Hands out each wait the timer asks for and ends it on demand, so no test sleeps for real. A wait ended by `finish`
/// returns normally even when its task was cancelled: the timer must not rely on cancellation alone.
@MainActor
final class ManualSleeper {
    private(set) var asked: [Duration] = []
    private var waits: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async throws {
        asked.append(duration)
        await withCheckedContinuation { waits.append($0) }
    }

    /// Ends the `index`-th wait (0 = the first one asked) and lets its task run.
    func finish(_ index: Int) async {
        guard waits.indices.contains(index) else { Issue.record("no wait \(index) was asked"); return }
        waits[index].resume()
        for _ in 0..<5 { await Task.yield() }
    }

    /// Lets the timer's task reach its wait. Bounded: a timer that never waits fails the test instead of hanging the run.
    func waitUntilAsked(_ count: Int) async {
        for _ in 0..<1_000 where asked.count < count { await Task.yield() }
        #expect(asked.count >= count, "the timer never started its wait")
    }
}

/// A success confirmation goes by itself after 4 s; the cross, an error and a newer confirmation are not undone by it (#864).
@MainActor
struct ConfirmationAutoDismissTests {
    @Test func theDelayIsWithinTheRangeTheOperatorAsked() {
        #expect(ConfirmationAutoDismiss.delay >= .seconds(3))
        #expect(ConfirmationAutoDismiss.delay <= .seconds(5))
    }

    @Test func aConfirmedReplyClearsItselfOnceTheDelayHasPassed() async throws {
        let (reader, sleeper) = try await readerWithConfirmation("Votre réponse a été postée avec succès !")
        #expect(sleeper.asked == [ConfirmationAutoDismiss.delay])
        #expect(reader.replyConfirmation == "Votre réponse a été postée avec succès !")
        await sleeper.finish(0)
        #expect(reader.replyConfirmation == nil)
    }

    @Test func theCrossClearsItAtOnceAndTheTimerThenChangesNothing() async throws {
        let (reader, sleeper) = try await readerWithConfirmation("Message effacé avec succès !")
        reader.clearReplyConfirmation()
        #expect(reader.replyConfirmation == nil)
        reader.showConfirmation("Un autre message")
        await sleeper.waitUntilAsked(2)
        // The first wait ends now: it belongs to the confirmation the cross removed.
        await sleeper.finish(0)
        #expect(reader.replyConfirmation == "Un autre message")
        await sleeper.finish(1)
        #expect(reader.replyConfirmation == nil)
    }

    @Test func aNewConfirmationIsNotClearedByTheOldTimer() async throws {
        let (reader, sleeper) = try await readerWithConfirmation("Votre message a été édité avec succès !")
        reader.showConfirmation("Message effacé avec succès !")
        await sleeper.waitUntilAsked(2)
        await sleeper.finish(0)
        #expect(reader.replyConfirmation == "Message effacé avec succès !")
        await sleeper.finish(1)
        #expect(reader.replyConfirmation == nil)
    }

    @Test func aReplyThatHFRDidNotConfirmShowsNothingAndArmsNoTimer() async throws {
        let sleeper = ManualSleeper()
        let pages = FakeTopicPages { target in readerPage(page: target.page) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "", source: pages)
        reader.confirmationTimer.sleep = sleeper.sleep
        await reader.onAppear()
        await reader.composerDidClose(.checkTopic)
        #expect(reader.replyConfirmation == nil)
        #expect(sleeper.asked.isEmpty)
    }

    @Test func aConfirmedTopicAndAConfirmedMessageGoByThemselvesToo() async throws {
        let sleeper = ManualSleeper()
        let source = FakeDataSource()
        source.topicHandler = { _, number in topicPage(page: number) }
        let list = TopicListModel(source: .forum(.forum(13), title: "Discussions"), dataSource: source, isLoggedIn: { true })
        list.confirmationTimer.sleep = sleeper.sleep
        await list.loadIfNeeded()
        await list.newTopicDidClose(.sent(newTopicConfirmed))
        #expect(list.sentConfirmation != nil)
        await sleeper.waitUntilAsked(1)
        await sleeper.finish(0)
        #expect(list.sentConfirmation == nil)

        let messages = MessageListModel(source: FakePrivateMessages(), isLoggedIn: { true })
        messages.confirmationTimer.sleep = sleeper.sleep
        await messages.newMessageDidClose(.sent(newMessageConfirmed), subject: "Sujet")
        #expect(messages.sentConfirmation != nil)
        await sleeper.waitUntilAsked(2)
        await sleeper.finish(1)
        #expect(messages.sentConfirmation == nil)
    }

    @Test func underVoiceOverTheConfirmationStaysUntilTheCross() async throws {
        let sleeper = ManualSleeper()
        let pages = FakeTopicPages { target in readerPage(page: target.page) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "", source: pages)
        reader.confirmationTimer.sleep = sleeper.sleep
        reader.confirmationTimer.isVoiceOverRunning = { true }
        await reader.onAppear()
        reader.showConfirmation("Votre réponse a été postée avec succès !")
        for _ in 0..<50 { await Task.yield() }
        #expect(sleeper.asked.isEmpty)
        #expect(reader.replyConfirmation != nil)
        reader.clearReplyConfirmation()
        #expect(reader.replyConfirmation == nil)
    }

    @Test func withoutVoiceOverTheConfirmationIsArmed() async throws {
        let (reader, sleeper) = try await readerWithConfirmation("Message effacé avec succès !")
        #expect(sleeper.asked.count == 1)
        _ = reader
    }

    private func readerWithConfirmation(_ sentence: String) async throws -> (TopicReaderModel, ManualSleeper) {
        let sleeper = ManualSleeper()
        let pages = FakeTopicPages { target in readerPage(page: target.page) }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "", source: pages)
        reader.confirmationTimer.sleep = sleeper.sleep
        reader.confirmationTimer.isVoiceOverRunning = { false }
        await reader.onAppear()
        reader.showConfirmation(sentence)
        await sleeper.waitUntilAsked(1)
        return (reader, sleeper)
    }
}
