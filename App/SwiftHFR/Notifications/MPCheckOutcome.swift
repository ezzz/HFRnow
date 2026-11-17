/// How a background MP check ended (LOT-140), for tests and the log; it never carries a pseudo, a subject or a count.
enum MPCheckOutcome: Sendable, Equatable {
    /// "Vérifier les messages" is set to Jamais.
    case disabled
    /// No account is stored, or the store could not be read.
    case noAccount
    /// The last check is more recent than the chosen interval, or the ledger could not be written.
    case notDue
    /// The forum gave no count: logged out, an unknown page, an expired session or a failure. Nothing was recorded.
    case noInformation
    /// The forum was read; `notifications` were shown.
    case checked(notifications: Int)

    /// The kind alone, for the log.
    var logLabel: String {
        switch self {
        case .disabled: "disabled"
        case .noAccount: "no account"
        case .notDue: "not due"
        case .noInformation: "no information"
        case .checked: "checked"
        }
    }
}
