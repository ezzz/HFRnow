import Foundation
import Synchronization
import UIKit

/// A one-shot event any thread may fire, awaited with a deadline (issue #801). A wait ends at the event or at the deadline,
/// never later: the deadline runs on a detached task, so a starved main actor or a callback that never comes cannot hang the
/// test job. Unlike a polling loop, a passing wait adds no work to the main actor while it waits.
final class TestEvent: Sendable {
    private struct State {
        var fired = false
        var waiters: [Int: CheckedContinuation<Bool, Never>] = [:]
        /// Waits whose deadline passed before their continuation was registered.
        var expired: Set<Int> = []
        var nextID = 0
    }

    private enum Registration { case fired, expired, waiting }

    private let state = Mutex(State())

    var hasFired: Bool { state.withLock { $0.fired } }

    func fire() {
        let waiters: [CheckedContinuation<Bool, Never>] = state.withLock { state in
            guard !state.fired else { return [] }
            state.fired = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume(returning: true) }
    }

    /// True once the event fired, false when `timeout` passed first.
    func wait(timeout: Duration) async -> Bool {
        let id: Int = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        let deadline = Task.detached { [self] in
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            expire(id)
        }
        defer { deadline.cancel() }
        return await withCheckedContinuation { continuation in
            let registered: Registration = state.withLock { state in
                if state.fired { return .fired }
                if state.expired.remove(id) != nil { return .expired }
                state.waiters[id] = continuation
                return .waiting
            }
            switch registered {
            case .fired: continuation.resume(returning: true)
            case .expired: continuation.resume(returning: false)
            case .waiting: break
            }
        }
    }

    private func expire(_ id: Int) {
        let waiter: CheckedContinuation<Bool, Never>? = state.withLock { state in
            if let waiter = state.waiters.removeValue(forKey: id) { return waiter }
            state.expired.insert(id)
            return nil
        }
        waiter?.resume(returning: false)
    }
}

/// A wait that passed its deadline: the test fails with what it waited for instead of hanging.
struct WaitTimeout: Error, CustomStringConvertible {
    let what: String
    let timeout: Duration
    var description: String { "no answer from \(what) within \(timeout)" }
}

/// The result of `operation`, or `WaitTimeout` after `timeout`. For WebKit calls whose answer may never come (a web content
/// process that died or is suspended): the test fails at the deadline instead of hanging the job (issue #801).
@MainActor
func answer<T>(
    of what: String, within timeout: Duration = .seconds(120), _ operation: @escaping @MainActor () async throws -> T
) async throws -> T {
    let box = AnswerBox<T>()
    let answered = TestEvent()
    Task { @MainActor in
        do {
            box.result = .success(try await operation())
        } catch {
            box.result = .failure(error)
        }
        answered.fire()
    }
    guard await answered.wait(timeout: timeout), let result = box.result else { throw WaitTimeout(what: what, timeout: timeout) }
    return try result.get()
}

@MainActor
private final class AnswerBox<T> {
    var result: Result<T, any Error>?
}

/// Puts `view` in a window of the app's scene, as on screen: WebKit throttles a web view that is in no window, which on a
/// busy CI simulator made a single load take minutes (issue #801). Keep the window for as long as the view must stay shown.
@MainActor
func hostInWindow(_ view: UIView) -> UIWindow? {
    guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
        return nil
    }
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
    view.frame = window.bounds
    window.addSubview(view)
    window.isHidden = false
    return window
}
