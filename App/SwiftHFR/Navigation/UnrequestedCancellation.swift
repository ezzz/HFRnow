import HFRNetwork

/// Runs `operation` and, when it fails with `cancelled` while the calling task was not cancelled, runs it once more: the
/// transport reports every `URLError.cancelled` as a cancellation, also one nobody asked for (issues #566, #1191). A second
/// such failure is thrown as is; the caller shows it as a failure when its task is still not cancelled, never as "stopped", so
/// no screen is left with no content, no load and no error.
///
/// Only for requests that may be sent twice (reads): a write, or a search whose first step is a POST, must not be retried.
/// It runs on the caller's actor, so `operation` needs not be `Sendable`.
func retryingUnrequestedCancellation<Value, Failure: Error & Equatable>(
    isolation: isolated (any Actor)? = #isolation,
    cancelledAs cancelled: Failure,
    _ operation: () async throws(Failure) -> Value
) async throws(Failure) -> Value {
    do throws(Failure) {
        return try await operation()
    } catch {
        guard error == cancelled, !Task.isCancelled else { throw error }
        // DO NOT MERGE (#1276): the #1230 retry fired.
        T1276.log("retry #1230 unrequested cancellation: second attempt of \(Value.self)")
        return try await operation()
    }
}
