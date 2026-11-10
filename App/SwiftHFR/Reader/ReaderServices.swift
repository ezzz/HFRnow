import Foundation

// Out of TopicReaderView.swift, which reached SwiftLint's file length with LOT-135's two fields.
/// What the reader shares across pages: the image client, the settings it reads and the position recorder.
struct ReaderServices: Sendable {
    /// Images through the cookie-less client.
    let imageFetcher: ReaderImageFetcher
    /// Image mode and display choices.
    let settings: ReaderSettings
    /// Public profiles opened from a link (LOT-116), fetched without cookies.
    let profiles: any UserProfileSource
    /// Records the reading position of the current account (LOT-111); nil when logged out.
    var positions: (any ReaderPositionRecording)?
    /// Offline reading (LOT-139): saving the open topic and the list of saved ones; nil in the offline reader itself.
    var offline: OfflineServices?
    /// Flag writes of the current account, for "Favoris" (LOT-125) and "Marquer comme non lu" (LOT-127); nil when logged out.
    var flagActions: TopicFlagActions?
    /// The blocklist of the current account and the allowlist (LOT-118): the BL / WL menu entries, the profile buttons and the
    /// editors of Réglages edit them through it; nil in previews.
    var pseudoLists: PseudoListManager?
    /// The moderator alerts of the current account (LOT-135); nil when logged out and in the offline reader.
    var moderatorAlerts: (any ModeratorAlerting)?
    /// The moderation address of the mail fallback, injected at build time (Q-10); nil when the build carries none.
    var moderatorAlertMail: String?
}
