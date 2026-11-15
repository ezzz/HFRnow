import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR

/// A scripted alert page: no session, no request. `holds` keeps `prepare` suspended until `release()`.
actor ScriptedAlerter: ModeratorAlerting {
    private(set) var links: [URL] = []
    private(set) var isHolding = false
    private let answer: Result<ModeratorAlertPreparation, ModeratorAlertError>
    private let holds: Bool
    private var gates: [CheckedContinuation<Void, Never>] = []

    init(_ answer: Result<ModeratorAlertPreparation, ModeratorAlertError>, holds: Bool = false) {
        self.answer = answer
        self.holds = holds
    }

    func prepare(link: URL) async throws(ModeratorAlertError) -> ModeratorAlertPreparation {
        links.append(link)
        if holds {
            await withCheckedContinuation { continuation in
                gates.append(continuation)
                isHolding = true
            }
        }
        return try answer.get()
    }

    func release() {
        isHolding = false
        // Every held call, so a test whose code under test calls twice fails on its counts instead of hanging.
        gates.forEach { $0.resume() }
        gates = []
    }
}

/// A scripted alert form: records each reason it was sent with and answers `answer`; `holds` suspends the send until
/// `release()`.
actor ScriptedAlertForm {
    private(set) var reasons: [String] = []
    private(set) var isHolding = false
    private var answers: [Result<String, ModeratorAlertError>]
    private let holds: Bool
    private var gates: [CheckedContinuation<Void, Never>] = []

    init(_ answers: Result<String, ModeratorAlertError>..., holds: Bool = false) {
        self.answers = answers
        self.holds = holds
    }

    func send(_ reason: String) async throws(ModeratorAlertError) -> String {
        reasons.append(reason)
        if holds {
            await withCheckedContinuation { continuation in
                gates.append(continuation)
                isHolding = true
            }
        }
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        return try answer.get()
    }

    func release() {
        isHolding = false
        // Every held call, so a test whose code under test calls twice fails on its counts instead of hanging.
        gates.forEach { $0.resume() }
        gates = []
    }

    /// The form as the screen receives it.
    nonisolated var prepared: PreparedModeratorAlert {
        PreparedModeratorAlert { reason async throws(ModeratorAlertError) -> String in try await self.send(reason) }
    }
}

/// `R21`'s alert link of message 2666649 (HFR-PROTOCOL §6c LOT-050).
let alertLink = url("https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649&page=1&ref=1")
/// A placeholder address: tests never carry the forum's real one (Q-10).
let moderationAddress = "moderation@example.org"

/// The menu context of another member's message `post`, with `alert` and `permalink` as given.
func alertContext(alert: URL? = alertLink, permalink: URL? = nil, own: Bool = false, post: Int = 2666649) -> MessageMenuContext {
    let edit = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&numreponse=\(post)")
    return MessageMenuContext(
        numreponse: post, author: "auteur", actions: MessageActions(editURL: own ? edit : nil, alertURL: alert),
        permalinkURL: permalink
    )
}

/// Waits until `condition` holds, yielding to the tasks under test (a bounded loop: a broken test fails, it never hangs).
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}
