import Foundation
import HFRModels
import HFRStorage

/// Where the reader records the reading position (LOT-090's store), so the model is tested without a file.
protocol ReaderPositionRecording: Sendable {
    /// Records `position` in `topic` for the current account; moves forward only.
    func record(_ position: ReadingPosition, in topic: TopicID) async
}

/// The app's recorder: the one process-wide store, scoped to an account.
struct LiveReaderPositionRecorder: ReaderPositionRecording {
    /// One actor per file, so two readers never write it at once.
    static let store = ReadingPositionStore(
        persistence: FileReadingPositionPersistence(fileURL: URL.applicationSupportDirectory.appending(path: "Positions/positions.json"))
    )

    /// The account's key (`md_user` value).
    let account: String

    /// The recorder of `account`, nil when logged out (nothing is recorded for a visitor).
    static func live(account: String?) -> LiveReaderPositionRecorder? {
        account.map { LiveReaderPositionRecorder(account: $0) }
    }

    func record(_ position: ReadingPosition, in topic: TopicID) async {
        // A failed save (unreadable store, full disk) loses a position, never the reading: nothing to show for it.
        _ = try? await Self.store.advance(topic, to: position, account: account)
    }
}
