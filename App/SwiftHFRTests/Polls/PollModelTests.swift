import Foundation
import HFRClient
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing

/// A scripted voter: answers with `outcome`, records what it was asked.
private final class ScriptedVoter: PollVoting, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [Int] = []
    private let outcome: Result<PollVoteResult, PollVoteError>

    init(_ outcome: Result<PollVoteResult, PollVoteError>) { self.outcome = outcome }

    var choices: [Int] { lock.withLock { asked } }

    func vote(_ choice: Int, in poll: Poll) async throws(PollVoteError) -> PollVoteResult {
        lock.withLock { asked.append(choice) }
        return try outcome.get()
    }
}

/// Counts reloads of the topic page.
@MainActor
private final class Reloads {
    var calls = 0
}

@MainActor
struct PollModelTests {
    private static let options = [
        PollOption(id: 1, text: "Oui", fieldName: "reponse"), PollOption(id: 2, text: "Non", fieldName: "reponse")
    ]
    private static let votable = Poll(question: "Q ?", kind: .votable(options: options, hiddenFields: ["cat": "13"]))
    private static let confirmation = PollVoteResult(
        topic: readerTopic, choice: 2, message: "Votre vote a bien été pris en compte !",
        refreshURL: url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
    )

    private func make(
        _ poll: Poll = votable, voter: ScriptedVoter?, reloads: Reloads = Reloads()
    ) -> (PollModel, Reloads) {
        (PollModel(poll: poll, voter: voter, reload: { reloads.calls += 1 }), reloads)
    }

    @Test func choosingTwiceClearsAndVoteNeedsAChoice() async {
        let voter = ScriptedVoter(.success(Self.confirmation))
        let (model, _) = make(voter: voter)
        #expect(!model.canVote)
        model.toggle(2)
        #expect(model.canVote)
        model.toggle(2)
        #expect(model.selected == nil)
        await model.vote()
        #expect(voter.choices.isEmpty)
    }

    @Test func anIdThatIsNoAnswerIsIgnored() {
        let (model, _) = make(voter: ScriptedVoter(.success(Self.confirmation)))
        model.toggle(9)
        #expect(model.selected == nil)
    }

    @Test func aConfirmedVoteSendsTheChoiceOnceReloadsAndLocks() async {
        let voter = ScriptedVoter(.success(Self.confirmation))
        let (model, reloads) = make(voter: voter)
        model.toggle(2)
        await model.vote()
        await model.vote()
        #expect(voter.choices == [2])
        #expect(reloads.calls == 1)
        #expect(model.phase == .voted)
        #expect(model.message == "Votre vote a bien été pris en compte !")
        #expect(!model.offersVote)
    }

    @Test func anUnconfirmedVoteReloadsAndIsNeverSentAgain() async {
        let voter = ScriptedVoter(.failure(.unconfirmed(.transport(.timedOut))))
        let (model, reloads) = make(voter: voter)
        model.toggle(1)
        await model.vote()
        #expect(model.phase == .settled)
        #expect(reloads.calls == 1)
        #expect(model.message?.contains("peut-être") == true)
        #expect(!model.canVote)
        await model.vote()
        #expect(voter.choices == [1])
    }

    @Test func alreadyVotedReloadsToShowTheResults() async {
        let (model, reloads) = make(voter: ScriptedVoter(.failure(.alreadyVoted)))
        model.toggle(1)
        await model.vote()
        #expect(model.phase == .settled)
        #expect(reloads.calls == 1)
    }

    @Test(arguments: [
        PollVoteError.network(.offline), .sessionNotConfirmed(.expired(.noIdentityCookie)),
        .sessionNotConfirmed(.unconfirmed(.unrecognizedPage)), .sessionNotConfirmed(.unconfirmed(.sessionChanged)), .notVotable,
        .loginChanged, .missingToken, .invalidChoice,
        .unsupportedPoll, .notLoggedIn, .rejected(message: nil), .rejected(message: "Refus du forum")
    ])
    func aVoteThatDidNotCountKeepsTheSheetOpenForAnotherTry(error: PollVoteError) async {
        let voter = ScriptedVoter(.failure(error))
        let (model, reloads) = make(voter: voter)
        model.toggle(1)
        await model.vote()
        #expect(model.phase == .failed)
        #expect(reloads.calls == 0)
        #expect(model.canVote)
        #expect(model.message?.isEmpty == false)
        await model.vote()
        #expect(voter.choices == [1, 1])
    }

    @Test func aRefusalShowsHFRsOwnSentence() async {
        let (model, _) = make(voter: ScriptedVoter(.failure(.rejected(message: "Refus du forum"))))
        model.toggle(1)
        await model.vote()
        #expect(model.message == "Refus du forum")
    }

    @Test func withoutAnAccountTheAnswersAreShownButNotOffered() async {
        let (model, _) = make(voter: nil)
        model.toggle(1)
        #expect(model.voterMissing)
        #expect(!model.offersVote)
        #expect(model.selected == nil)
        await model.vote()
        #expect(model.phase == .idle)
    }

    @Test func resultsAndMultiChoicePollsOfferNoVote() {
        let voter = ScriptedVoter(.success(Self.confirmation))
        let results = Poll(question: "Q", kind: .results([PollResult(id: 1, label: "Oui", percentage: 100, voteCount: 3)]))
        #expect(!make(results, voter: voter).0.offersVote)
        let multi = Poll(question: "Q", maxChoices: 2, kind: .votable(options: Self.options, hiddenFields: [:]))
        #expect(!make(multi, voter: voter).0.offersVote)
    }

    @Test func theReloadedPollReplacesTheOneShownAndAnUnreadablePageKeepsIt() {
        let (model, _) = make(voter: ScriptedVoter(.success(Self.confirmation)))
        let results = Poll(question: "Q ?", kind: .results([PollResult(id: 1, label: "Oui", percentage: 100, voteCount: 1)]))
        model.pageDidReload(nil)
        #expect(model.poll == Self.votable)
        model.pageDidReload(results)
        #expect(model.poll == results)
        #expect(!model.offersVote)
    }

    @Test func aVoteInFlightOrPossiblyCountedIsKeptForAReopenedSheet() async {
        let (idle, _) = make(voter: ScriptedVoter(.success(Self.confirmation)))
        #expect(!idle.holdsVote)
        let (unconfirmed, _) = make(voter: ScriptedVoter(.failure(.unconfirmed(.unrecognizedAnswer(message: nil)))))
        unconfirmed.toggle(1)
        await unconfirmed.vote()
        #expect(unconfirmed.holdsVote)
        let (failed, _) = make(voter: ScriptedVoter(.failure(.network(.offline))))
        failed.toggle(1)
        await failed.vote()
        #expect(!failed.holdsVote)
    }
}
