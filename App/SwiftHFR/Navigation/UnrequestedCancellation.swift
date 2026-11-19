/// Runs `operation` and, when it fails with a cancellation (`isCancellation`) while the calling task was not cancelled, runs it
/// once more: the transport reports every `URLError.cancelled` as `.cancelled`, also one nobody asked for (issues #566, #1191).
/// A second such failure is thrown as is; the caller shows it as a failure when its task is still not cancelled, never as
/// "stopped", so no screen is left with no content, no load and no error.
///
/// It runs on the caller's actor, so `operation` needs not be `Sendable`.
func retryingUnrequestedCancellation<Value, Failure: Error>(
    isolation: isolated (any Actor)? = #isolation,
    isCancellation: (Failure) -> Bool,
    _ operation: () async throws(Failure) -> Value
) async throws(Failure) -> Value {
    do throws(Failure) {
        return try await operation()
    } catch {
        guard isCancellation(error), !Task.isCancelled else { throw error }
        return try await operation()
    }
}
