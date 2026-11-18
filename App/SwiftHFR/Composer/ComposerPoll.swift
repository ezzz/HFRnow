import HFRClient

// Port of HFRswift/Swift/AnswerView.swift:324-328 (`canCreatePoll`, `hasLoadedPollCapability`, `pollCapabilityError`,
// `createdPollDraft`) @ 87fe0d1c (GAP-099). Differences: none; the draft is held by the composer model instead of the view.
/// The poll of a composer (LOT-100): whether the form allows one, and the poll the user set, if any.
struct ComposerPoll: Equatable, Sendable {
    /// Whether the composer's form can add a poll.
    enum Availability: Equatable, Sendable {
        /// The form is being read (a new topic's, `loadSubcategories`).
        case loading
        /// The form adds a poll (`ForumForm.offersPollCreation`).
        case offered
        /// The form has no poll to add: a new topic (`R45a`), a topic that has one, a form changed since.
        case notOffered
        /// The form could not be read.
        case failed
    }

    /// Unknown until the form is read.
    private(set) var availability = Availability.loading
    /// The poll to send with the message; nil when none was set.
    private(set) var draft: PollDraft?

    /// A message can be sent: no poll, or one the form allows and that is complete (legacy `AnswerView.swift:434`, `:1481`).
    var isSendable: Bool {
        guard let draft else { return true }
        return availability == .offered && draft.problem() == nil
    }

    mutating func beginLoading() {
        availability = .loading
    }

    /// Takes what the form says; a poll already set stays on screen even when the form no longer allows it, so the user
    /// sees it and removes it (Send waits for that).
    mutating func apply(offers: Bool) {
        availability = offers ? .offered : .notOffered
    }

    mutating func fail() {
        availability = .failed
    }

    /// Sets the poll, only when the form allows one; returns whether it did.
    mutating func set(_ newDraft: PollDraft) -> Bool {
        guard availability == .offered else { return false }
        draft = newDraft
        return true
    }

    /// "Retirer".
    mutating func remove() {
        draft = nil
    }
}
