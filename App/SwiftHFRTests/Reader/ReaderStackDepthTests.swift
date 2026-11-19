import HFRModels
@testable import SwiftHFR
import Testing

/// The count of readers stacked below the one on screen (#682, legacy `navigationDepth`).
@MainActor
struct ReaderStackDepthTests {
    private func root() -> TopicReaderModel {
        TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), title: "Sujet", source: FakeTopicPages())
    }

    private let elsewhere = ReaderTarget(source: .topic(TopicID(category: .forum(5), topic: 77)), page: 2)

    @Test func aReaderOpenedFromAListHasDepthZero() {
        #expect(root().depth == 0)
    }

    @Test func eachFollowedLinkPushesAReaderOneDeeperThanItsOpener() throws {
        let first = root()
        first.follow(elsewhere)
        let second = try #require(first.linkedReader)
        #expect(second.depth == 1)
        second.follow(ReaderTarget(source: .topic(TopicID(category: .forum(6), topic: 78)), page: 1))
        let third = try #require(second.linkedReader)
        #expect(third.depth == 2)
    }

    @Test func goingBackThenFollowingAgainStartsFromTheOpenersDepth() throws {
        let first = root()
        first.follow(elsewhere)
        first.closeLinkedReader()
        #expect(first.linkedReader == nil)
        first.follow(elsewhere)
        #expect(try #require(first.linkedReader).depth == 1)
        #expect(first.depth == 0, "the opener's own depth never changes")
    }

    @Test func aNegativeDepthIsRaisedToZero() {
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic)), source: FakeTopicPages(), depth: -3)
        #expect(reader.depth == 0)
    }

    @Test func theCapsuleIsLabelledFromDepthOneOnly() {
        #expect(ReaderStackDepthCapsule.accessibilityLabel(depth: 0) == nil)
        #expect(ReaderStackDepthCapsule.accessibilityLabel(depth: 1) == "1 affichage de messages empilé")
        #expect(ReaderStackDepthCapsule.accessibilityLabel(depth: 3) == "3 affichage de messages empilé")
    }
}
