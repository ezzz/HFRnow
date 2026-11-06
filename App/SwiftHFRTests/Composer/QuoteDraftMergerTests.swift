import Foundation
@testable import SwiftHFR
import Testing

/// How a quote joins the text already written, and the order of a multi-quote's blocks (LOT-086). The merger cases are the
/// four of legacy's `ReplyPostingServiceTests.swift:1330-1368` @ 21173e7, plus the ones this port decides.
struct QuoteDraftMergerTests {
    private let quote = "[quotemsg=1,2,3]Salut[/quotemsg]\n"

    @Test func anEmptyDraftBecomesTheQuoteAsServed() {
        #expect(QuoteDraftMerger.merge(quote, into: "") == quote)
        #expect(QuoteDraftMerger.merge(quote, into: " \n ") == quote)
    }

    @Test func aWrittenDraftKeepsItsTextAndGetsTheQuoteAfterABlankLine() {
        #expect(QuoteDraftMerger.merge(quote, into: "Mon brouillon") == "Mon brouillon\n\n" + quote)
        #expect(QuoteDraftMerger.merge(quote, into: "Mon brouillon\n") == "Mon brouillon\n\n" + quote)
    }

    @Test func aQuoteTheDraftAlreadyHoldsIsNotAddedAgain() {
        let draft = "Mon brouillon\n\n" + quote
        #expect(QuoteDraftMerger.merge(quote, into: draft) == draft)
    }

    @Test func aMultiQuoteAddsOnlyTheBlocksTheDraftLacks() {
        let first = "[quotemsg=10,1,1]A[/quotemsg]\n"
        let second = "[quotemsg=20,1,1]B[/quotemsg]\n"
        let draft = "Mon brouillon\n\n" + first
        #expect(QuoteDraftMerger.merge(first + second, into: draft) == draft + "\n" + second)
        #expect(QuoteDraftMerger.merge(first + second, into: draft + second) == draft + second)
    }

    @Test func aMultiQuoteAddsOnlyTheThirdBlockWhenTheDraftHoldsTwo() {
        let blockA = "[quotemsg=10,1,1]A[/quotemsg]\n"
        let blockB = "[quotemsg=20,1,1]B[/quotemsg]\n"
        let blockC = "[quotemsg=30,1,1]C[/quotemsg]\n"
        let draft = "Mon brouillon\n\n" + blockA + blockB
        #expect(QuoteDraftMerger.merge(blockA + blockB + blockC, into: draft) == draft + "\n" + blockC)
    }

    @Test func aMultiQuoteWhoseBlocksTheDraftHoldsInAnotherOrderChangesNothing() {
        let blockA = "[quotemsg=10,1,1]A[/quotemsg]\n"
        let blockB = "[quotemsg=20,1,1]B[/quotemsg]\n"
        let draft = blockB + "entre deux\n" + blockA
        #expect(QuoteDraftMerger.merge(blockA + blockB, into: draft) == draft)
    }

    @Test func aBlankQuoteChangesNothing() {
        #expect(QuoteDraftMerger.merge(" \n\t ", into: "Mon brouillon") == "Mon brouillon")
        #expect(QuoteDraftMerger.merge("", into: "") == "")
    }

    @Test func aTwiceQuotedMessageWithAnotherPassageIsAddedAsASecondBlock() {
        let first = "[quotemsg=1,2,3]un extrait[/quotemsg]\n"
        let second = "[quotemsg=1,2,3]autre extrait[/quotemsg]\n"
        #expect(QuoteDraftMerger.merge(second, into: first) == first + "\n" + second)
    }

    @Test func theDuplicateTestIsExactNotCaseInsensitive() {
        let draft = "[quotemsg=1,2,3]salut[/quotemsg]\n"
        #expect(QuoteDraftMerger.merge(quote, into: draft) == draft + "\n" + quote)
    }

    // MARK: Order

    private func block(_ number: Int, _ text: String, tail: String = "\n\n") -> String {
        "[quotemsg=\(number),13,900001]\(text)[/quotemsg]" + tail
    }

    @Test func blocksComeOutInAscendingMessageOrder() {
        let served = block(30, "trois") + block(10, "un") + block(20, "deux")
        #expect(MultiQuoteOrder.topicOrder(served) == block(10, "un") + block(20, "deux") + block(30, "trois"))
    }

    @Test func anOrderedPrefillIsReturnedUnchanged() {
        let served = block(10, "un") + block(20, "deux", tail: "\n")
        #expect(MultiQuoteOrder.topicOrder(served) == served)
    }

    @Test func aSingleBlockAndATextWithoutBlocksAreUnchanged() {
        #expect(MultiQuoteOrder.topicOrder(block(10, "un")) == block(10, "un"))
        #expect(MultiQuoteOrder.topicOrder("rien à citer") == "rien à citer")
        #expect(MultiQuoteOrder.topicOrder("") == "")
    }

    @Test func aPrefillWithAnythingElseThanBlocksIsNeverRewritten() {
        let served = block(30, "trois") + "du texte entre\n" + block(10, "un")
        #expect(MultiQuoteOrder.topicOrder(served) == served)
        let trailing = block(30, "trois") + block(10, "un") + "après"
        #expect(MultiQuoteOrder.topicOrder(trailing) == trailing)
    }

    @Test func blocksAreMovedWholeWithTheirLineBreaksAndTags() {
        let one = "[QUOTEMSG=10,13,900001]ligne 1\r\nligne 2[/QUOTEMSG]\n\n"
        let two = block(5, "deux")
        #expect(MultiQuoteOrder.topicOrder(one + two) == two + one)
    }

    @Test func equalNumbersKeepTheirOrder() {
        let first = block(10, "a")
        let second = block(10, "b")
        #expect(MultiQuoteOrder.topicOrder(first + second) == first + second)
    }
}
