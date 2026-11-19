import Observation

/// Loads one value with the rules every list screen shares: one load at a time, the content stays while a reload runs
/// or fails, and a superseded load can never overwrite a newer one (LOTS "Issues to open" #6 and #7).
@MainActor
@Observable
final class ContentLoader<Value: Sendable> {
    /// The last value loaded successfully; kept while reloading and after a failed reload.
    private(set) var value: Value?
    /// A load is running.
    private(set) var isLoading = false
    /// Failure of the latest load; cleared by the next success.
    private(set) var error: ListLoadError?

    private var generation = 0
    private var task: Task<Bool, Never>?

    /// Runs `operation` as the current load, superseding any load in flight, and returns when it has been applied or dropped:
    /// true only when this call's value is now `value` (a superseded or failed load returns false).
    ///
    /// The work runs in its own task so that cancelling the caller (a pull-to-refresh that is dismissed) does not leave the
    /// screen in a half-loaded state; only a newer `load` or `cancel()` supersedes it. A `.cancelled` that neither asked for is
    /// retried once, then shown as `.other` (#1191).
    @discardableResult
    func load(_ operation: @escaping @Sendable () async throws(ListLoadError) -> Value) async -> Bool {
        task?.cancel()
        generation += 1
        let mine = generation
        isLoading = true
        let task = Task { [weak self] in
            let result: Result<Value, ListLoadError>
            do throws(ListLoadError) {
                // A cancellation nobody asked for is asked once more (`cancel()` and a newer load cancel this task; #1191).
                result = .success(try await retryingUnrequestedCancellation(isCancellation: { $0 == .cancelled }, operation))
            } catch {
                result = .failure(error)
            }
            return self?.finish(result, generation: mine) ?? false
        }
        self.task = task
        return await task.value
    }

    /// Stops the load in flight without changing the content.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isLoading = false
    }

    /// Stops the load in flight and forgets the value and the failure (a new query must not show the previous one's rows).
    func reset() {
        cancel()
        value = nil
        error = nil
    }

    /// Applies `result` unless a newer load superseded it; true when it applied a value.
    private func finish(_ result: Result<Value, ListLoadError>, generation mine: Int) -> Bool {
        // A superseded load is dropped whatever it carries.
        guard mine == generation else { return false }
        isLoading = false
        switch result {
        case .success(let loaded):
            value = loaded
            error = nil
            return true
        case .failure(.cancelled):
            // `cancel()` and a newer load change the generation, so this one was not asked for and came twice: a failure,
            // never a screen left with no value, no load and no error (#1191, the reader's rule of #566).
            error = .other
            return false
        case .failure(let failure):
            error = failure
            return false
        }
    }
}
