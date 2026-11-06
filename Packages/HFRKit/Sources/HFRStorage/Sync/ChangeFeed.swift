/// Tells every caller of a store's `changes()` that the store saved a change (LOT-172).
///
/// A signal, not the change: a listener reads the store again, so the newest signal is the only one worth keeping and a
/// slow listener never makes the store wait. A stream that ended is dropped at the next signal.
struct ChangeFeed {
    private var continuations: [AsyncStream<Void>.Continuation] = []

    /// A new stream of signals.
    mutating func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        continuations.append(continuation)
        return stream
    }

    /// Signals a saved change to every live stream.
    mutating func signal() {
        continuations.removeAll { continuation in
            if case .terminated = continuation.yield(()) { return true }
            return false
        }
    }
}
