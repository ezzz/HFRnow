import Foundation
import Testing
@testable import HFRStorage

/// `ReadingPosition.isAhead(of:)`: what counts as moving forward in a topic.
@Suite struct ReadingPositionOrderTests {
    private static let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func position(_ page: Int, _ message: Int? = nil, _ offset: Int? = nil) -> ReadingPosition {
        ReadingPosition(page: page, messageNumber: message, offset: offset, updatedAt: Self.date)
    }

    @Test func aLaterMessageIsAheadEvenOnAnEarlierPage() {
        // After deletions, a later message can sit on an earlier page.
        #expect(position(3, 900).isAhead(of: position(4, 800)))
        #expect(!position(4, 800).isAhead(of: position(3, 900)))
    }

    @Test func theOffsetDecidesWithinOneMessage() {
        #expect(position(2, 500, 120).isAhead(of: position(2, 500, 40)))
        #expect(position(2, 500, 1).isAhead(of: position(2, 500)))
        #expect(!position(2, 500, 40).isAhead(of: position(2, 500, 40)))
        #expect(!position(2, 500).isAhead(of: position(2, 500, 0)))
    }

    @Test func withoutBothMessageNumbersThePageDecides() {
        #expect(position(5).isAhead(of: position(4, 800)))
        #expect(position(5, 10).isAhead(of: position(4)))
        #expect(!position(4).isAhead(of: position(4)))
        #expect(!position(3).isAhead(of: position(4, 800)))
    }

    @Test func aKnownMessageBeatsAnUnknownOneOnTheSamePage() {
        #expect(position(4, 800).isAhead(of: position(4)))
        #expect(!position(4).isAhead(of: position(4, 800)))
    }

    @Test func theDatePlaysNoPart() {
        let older = ReadingPosition(page: 6, updatedAt: Self.date)
        let newer = ReadingPosition(page: 5, updatedAt: Self.date.addingTimeInterval(3_600))
        #expect(older.isAhead(of: newer))
        #expect(!newer.isAhead(of: older))
    }

    @Test(
        "Out-of-range numbers are invalid",
        arguments: [(0, nil, nil), (-1, nil, nil), (1, 0, nil), (1, -5, nil), (1, 10, -1)] as [(Int, Int?, Int?)]
    )
    func invalidPositions(page: Int, message: Int?, offset: Int?) {
        #expect(!position(page, message, offset).isValid)
    }

    @Test func inRangeNumbersAreValid() {
        #expect(position(1).isValid)
        #expect(position(1, 1, 0).isValid)
    }
}
