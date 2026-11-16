/// Offline save is disabled (operator, 2026-11-14, #822: legacy removed it for low use and maintenance cost): its code and the
/// pages testers saved are kept for a later design (#846), but no entry reaches it, and there is no setting for it.
enum OfflineSaveAvailability {
    // DISABLED(offline, #822): kept for a later design (#846), not reachable
    /// Whether any screen offers offline saving or the saved topics: false, so the reader's "…" overflow has no "Hors ligne"
    /// items, the reader creates no saver (no progress banner), and Réglages has no "Hors ligne" section.
    static let isReachable = false
}
