#if canImport(FoundationNetworking)
import Foundation
import FoundationNetworking
import Testing
@testable import HFRNetwork

/// A clock the test moves by hand: no sleeping, no starving of the executor (which every test of the process shares).
private final class HandClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    func advance(_ seconds: Double) {
        lock.lock()
        instant = instant.advanced(by: .seconds(seconds))
        lock.unlock()
    }
}

/// How the Linux idle watcher's delegate ends a request (#1087): a connection that ends in an error after the idle limit with
/// nothing received is a timeout, whatever the watcher (a pool task, possibly starved) did meanwhile. The clock is moved by hand
/// and the delegate's methods are called directly, so these tests are exact and take no time.
struct IdleWatchDelegateTests {
    private static let idle = 0.5
    private let session = URLSession(configuration: .ephemeral)

    /// Runs `script` against a fresh delegate (limit `idle`, not started), then reports how the request ended: the code of the
    /// error it threw, nil if it returned an answer.
    private func ending(
        idle: Double = idle, _ script: (IdleWatchDelegate, URLSessionDataTask, HandClock) -> Void
    ) async -> URLError.Code? {
        let clock = HandClock()
        let delegate = IdleWatchDelegate(follows: true, idle: idle, owner: session, now: { clock.now() })
        let task = session.dataTask(with: URL(fileURLWithPath: "/"))
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), any Error>) in
                _ = delegate.attach(task, continuation)
                script(delegate, task, clock)
            }
            return nil
        } catch {
            return (error as? URLError)?.code
        }
    }

    @Test func aConnectionDroppedAfterTheIdleLimitIsATimeout() async {
        let code = await ending { delegate, task, clock in
            clock.advance(0.7)
            delegate.urlSession(session, task: task, didCompleteWithError: URLError(.badServerResponse))
        }
        #expect(code == .timedOut)
    }

    /// The watcher restarts its own clock when it finds its sleep lasted as long as the limit (a stalled process). That must not
    /// hide from the mapping that the network had sent nothing for the limit: the case the first review of #1088 found.
    @Test func theWatchersRestartDoesNotHideTheSilenceFromTheMapping() async {
        let code = await ending { delegate, task, clock in
            clock.advance(1.0)
            delegate.noteActivity()
            clock.advance(0.25)
            delegate.urlSession(session, task: task, didCompleteWithError: URLError(.badServerResponse))
        }
        #expect(code == .timedOut)
    }

    @Test func anErrorBeforeTheIdleLimitStaysATransportError() async {
        let code = await ending { delegate, task, clock in
            clock.advance(0.4)
            delegate.urlSession(session, task: task, didCompleteWithError: URLError(.badServerResponse))
        }
        #expect(code == .badServerResponse)
    }

    @Test func dataReceivedRestartsTheSilence() async {
        let code = await ending { delegate, task, clock in
            clock.advance(0.4)
            delegate.urlSession(session, dataTask: task, didReceive: Data("x".utf8))
            clock.advance(0.4)
            delegate.urlSession(session, task: task, didCompleteWithError: URLError(.networkConnectionLost))
        }
        #expect(code == .networkConnectionLost)
    }

    /// A cancellation, the caller's or the watcher's own after its timeout, stays a cancellation after a long silence.
    @Test func aCancellationAfterALongSilenceStaysACancellation() async {
        let code = await ending { delegate, task, clock in
            clock.advance(1.0)
            delegate.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
        }
        #expect(code == .cancelled)
    }

    /// A limit of 0 reads as a millisecond, as the watcher reads it: a refused connection, which fails at once, stays one.
    @Test func aZeroLimitDoesNotTurnAnImmediateFailureIntoATimeout() async {
        let code = await ending(idle: 0) { delegate, task, _ in
            delegate.urlSession(session, task: task, didCompleteWithError: URLError(.cannotConnectToHost))
        }
        #expect(code == .cannotConnectToHost)
    }

    /// Only a failure is mapped: an answer that arrived is an answer, whatever it took.
    @Test func anAnswerAfterALongSilenceStaysAnAnswer() async {
        let code = await ending { delegate, task, clock in
            clock.advance(2.0)
            if let url = URL(string: "http://127.0.0.1/"),
               let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
                delegate.urlSession(session, dataTask: task, didReceive: response) { _ in }
            }
            delegate.urlSession(session, dataTask: task, didReceive: Data("ok".utf8))
            delegate.urlSession(session, task: task, didCompleteWithError: nil)
        }
        #expect(code == nil)
    }
}
#endif
