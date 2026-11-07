import os

/// Debug trace of the reader's lifecycle (issue #566), for a device check: `subsystem:SwiftHFR category:reader` in the
/// console. Messages carry numbers and tokens only, never a URL, a pseudo or a cookie; release builds log nothing.
enum ReaderLog {
    #if DEBUG
    private static let logger = Logger(subsystem: "SwiftHFR", category: "reader")
    #endif

    /// Logs `message` in debug builds; the text is built only there.
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.debug("\(text, privacy: .public)")
        #endif
    }
}

/// Identifies one reader view instance, so the model knows which view's disappearance may stop its load (issue #566).
enum ReaderViewerID {
    private static let last = OSAllocatedUnfairLock(initialState: 0)

    /// A number no other view instance of this run holds.
    static func next() -> Int {
        last.withLock { value in
            value += 1
            return value
        }
    }
}
