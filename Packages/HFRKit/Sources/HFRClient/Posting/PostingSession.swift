import HFRNetwork

/// The account session a write runs in: its cookies send the form request and the POST, and it records the form's token.
///
/// `HFRSession` is the real one; tests script the answers. Being an actor gives a `PostingForm` a session identity it
/// can keep, so a form is always submitted through the session that fetched it (decision Q-8).
protocol PostingSession: Actor, HTTPTransport {
    /// Records the `hash_check` read from a form page (HFR-PROTOCOL §5: refreshed from parse results by `HFRClient`).
    func updateHashCheck(_ value: String?)
}

extension HFRSession: PostingSession {}
