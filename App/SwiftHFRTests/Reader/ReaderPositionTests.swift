import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Collects what the reader records, so a test reads the call itself (LOT-111).
actor RecordingPositions: ReaderPositionRecording {
    private(set) var records: [(position: ReadingPosition, topic: TopicID)] = []

    func record(_ position: ReadingPosition, in topic: TopicID) {
        records.append((position, topic))
    }
}

/// LOT-111: the topmost message the web view reports becomes the reading position (LOT-090), for the page on screen only.
@MainActor
struct ReaderPositionTests {
    private func loadedReader(page: Int = 2, anchor: Int? = nil) async -> (TopicReaderModel, RecordingPositions) {
        let recorder = RecordingPositions()
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic), page: page, anchor: anchor), title: "Sujet",
            source: FakeTopicPages()
        )
        reader.positions = recorder
        await reader.onAppear()
        return (reader, recorder)
    }

    @Test func aReportedMessageIsRecordedWithItsPage() async throws {
        let (reader, recorder) = await loadedReader()
        let token = try #require(reader.document?.token)
        await reader.recordPosition(post: 201, token: token)
        let records = await recorder.records
        #expect(records.count == 1)
        #expect(records.first?.position.page == 2)
        #expect(records.first?.position.messageNumber == 201)
        #expect(records.first?.topic == readerTopic)
    }

    @Test func aReportOfAnOlderDocumentIsIgnored() async throws {
        let (reader, recorder) = await loadedReader()
        let token = try #require(reader.document?.token)
        await reader.goToPage(3)
        await reader.recordPosition(post: 300, token: token)
        #expect(await recorder.records.isEmpty)
    }

    @Test func aMessageOfAnotherPageIsIgnored() async throws {
        let (reader, recorder) = await loadedReader()
        let token = try #require(reader.document?.token)
        await reader.recordPosition(post: 999, token: token)
        #expect(await recorder.records.isEmpty)
    }

    @Test func aContinuationBlockIsNeverRecorded() async throws {
        let recorder = RecordingPositions()
        var built = readerPage(page: 2)
        built.messages[0].isContinuation = true
        let page = built
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(readerTopic), page: 2), title: "Sujet",
            source: FakeTopicPages { _ in page }
        )
        reader.positions = recorder
        await reader.onAppear()
        let token = try #require(reader.document?.token)
        await reader.recordPosition(post: 200, token: token)
        #expect(await recorder.records.isEmpty)
    }

    @Test func theLiveRecorderOnlyMovesForward() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        let recorder = LiveReaderPositionRecorder(account: "compte", store: store)
        await recorder.record(ReadingPosition(page: 2, messageNumber: 201), in: readerTopic)
        await recorder.record(ReadingPosition(page: 2, messageNumber: 200), in: readerTopic)
        #expect(await store.position(of: readerTopic, account: "compte")?.messageNumber == 201)
    }

    @Test func nobodyIsRecordedWhenLoggedOut() {
        #expect(LiveReaderPositionRecorder.live(account: nil) == nil)
    }
}
