import Foundation
import HFRModels
import HFRNetwork

/// The check was cancelled; nothing is returned, not even the source that had already answered.
public struct CheckUpdatesCancelled: Error, Sendable, Equatable {
    /// Creates the error.
    public init() {}
}

/// One read-only check of what is new for an account: its unread private messages and its flagged topics (LOT-092).
///
/// At most two requests, in this order, both through probe sessions that never write to the account (`MPUnreadPoll`,
/// `FlaggedTopicsPoll`): `GET /` for the MP count, then `GET /forum1f.php?owntopic=1` for the flags. Neither is a topic page,
/// the only page that moves a flag (HFR-PROTOCOL §7, E25). Neither request follows redirects: a redirect answer is
/// `.failed(.page(.malformed))` for its source, so the account's cookies never reach a topic page and no third request exists.
/// When the first answer is HFR's stale-session page the second request is not sent: it would get the same answer.
///
/// Each source reports its own outcome (`UpdateOutcome`): one failing does not hide the other, and a source that gave no
/// information is `noInformation`, never zero news and never proof of an expiry. Only the stale-session page (#383) is
/// reported as `sessionExpired`. When to check, how often (politeness) and what was already notified are the app's (LESSONS 48).
public struct CheckUpdatesFlow: Sendable {
    typealias MessagesRead = @Sendable () async throws(MPUnreadPollError) -> Int?
    typealias FlagsRead = @Sendable () async throws(FlaggedTopicsPollError) -> [TopicSummary]?

    private let readMessages: MessagesRead
    private let readFlags: FlagsRead

    /// Creates a flow that reads with the cookies of `session`, without ever changing it.
    public init(session: HFRSession) {
        self.init(messages: MPUnreadPoll(session: session, redirectPolicy: .doNotFollow), flags: FlaggedTopicsPoll(session: session))
    }

    /// Creates a flow over scripted probes, through the same polls and policies as the public init (tests).
    init(
        session: HFRSession,
        makeHomeProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport,
        makeFlagsProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport
    ) {
        self.init(
            messages: MPUnreadPoll(session: session, redirectPolicy: .doNotFollow, makeProbe: makeHomeProbe),
            flags: FlaggedTopicsPoll(session: session, makeProbe: makeFlagsProbe)
        )
    }

    private init(messages: MPUnreadPoll, flags: FlaggedTopicsPoll) {
        self.init(readMessages: { () async throws(MPUnreadPollError) -> Int? in try await messages.unreadCount() },
                  readFlags: { () async throws(FlaggedTopicsPollError) -> [TopicSummary]? in try await flags.flaggedTopics() })
    }

    /// Creates a flow over other readers (tests).
    init(readMessages: @escaping MessagesRead, readFlags: @escaping FlagsRead) {
        self.readMessages = readMessages
        self.readFlags = readFlags
    }

    /// Runs the check.
    /// - Throws: `CheckUpdatesCancelled` when the task is cancelled before, between or during the requests. Every other
    ///   failure is an outcome of its source.
    public func check() async throws(CheckUpdatesCancelled) -> UpdateSummary {
        if Task.isCancelled { throw CheckUpdatesCancelled() }
        let messages = try await readMessagesOutcome()
        if Task.isCancelled { throw CheckUpdatesCancelled() }
        let flags: UpdateOutcome<[TopicSummary]>
        if case .failed(.sessionExpired(let reason)) = messages {
            flags = .failed(.sessionExpired(reason))
        } else {
            flags = try await readFlagsOutcome()
        }
        if Task.isCancelled { throw CheckUpdatesCancelled() }
        return UpdateSummary(unreadPrivateMessages: messages, flaggedTopics: flags)
    }

    private func readMessagesOutcome() async throws(CheckUpdatesCancelled) -> UpdateOutcome<Int> {
        do throws(MPUnreadPollError) {
            return try await readMessages().map { .value($0) } ?? .noInformation
        } catch {
            switch error {
            case .network(.cancelled): throw CheckUpdatesCancelled()
            case .network(let failure): return .failed(.network(failure))
            case .page(let failure): return .failed(.page(failure))
            case .sessionExpired(let reason): return .failed(.sessionExpired(reason))
            }
        }
    }

    private func readFlagsOutcome() async throws(CheckUpdatesCancelled) -> UpdateOutcome<[TopicSummary]> {
        do throws(FlaggedTopicsPollError) {
            return try await readFlags().map { .value($0) } ?? .noInformation
        } catch {
            switch error {
            case .network(.cancelled): throw CheckUpdatesCancelled()
            case .network(let failure): return .failed(.network(failure))
            case .page(let failure): return .failed(.page(failure))
            case .sessionExpired(let reason): return .failed(.sessionExpired(reason))
            }
        }
    }
}
