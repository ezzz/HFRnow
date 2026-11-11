import Foundation

/// Why a legacy import step could not complete. Carries no stored value (no pseudo, cookie, token or text).
public enum LegacyImportError: Error, Sendable, Equatable {
    /// The legacy data exists but is not in a legacy format: the legacy app would have shown nothing either. Not retried.
    case sourceUnreadable
    /// The legacy data cannot be read now (Keychain locked, file unreadable): retried at the next run.
    case sourceUnavailable
    /// A SwiftHFR store refused the data (failed load, newer version) or could not save it: retried at the next run.
    case destinationFailed
}

/// The steps of the import, in the order they run (LOT-067 spec, "Steps").
public enum LegacyImportStep: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case accounts
    case pseudoLists
    case superFavorites
    case collapsedSections
    case smileyFavorites
    case smileySearchHistory
    case uploadHistory
    case drafts
    case mpStorageSwitch
    case pageCache

    /// Steps that write into the account receiving the legacy app's global items (ADR 0013 §5, decision D3).
    var needsGlobalAccount: Bool {
        self == .superFavorites || self == .smileyFavorites || self == .drafts
    }

    /// Steps that write under an account's pseudo, so they read the erased accounts first (LOT-157).
    var writesForAnAccount: Bool {
        needsGlobalAccount || self == .accounts || self == .pseudoLists
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}

/// What one step did in one run.
public enum LegacyImportOutcome: Sendable, Equatable {
    /// Items written or set aside in the pending lists (super-favourites, reply drafts); already-present ones not counted.
    case imported(Int)
    /// No legacy data for this step.
    case nothingToImport
    /// Done in an earlier run: never redone, so an item removed since does not come back.
    case alreadyDone
    /// Waits for an account to receive the global items (no legacy account, nobody logged in yet), or, for the pseudo
    /// lists, for the accounts step: the `accounts` outcome of the same report gives the reason.
    case waitingForAccount
    /// The step did not complete and runs again at the next run (`sourceUnavailable`, `destinationFailed`), or the
    /// legacy data was unreadable and is not retried (`sourceUnreadable`).
    case failed(LegacyImportError)

    /// Whether the step is finished for good.
    var isDone: Bool {
        switch self {
        case .imported, .nothingToImport, .alreadyDone, .failed(.sourceUnreadable): true
        case .waitingForAccount, .failed: false
        }
    }
}

/// The legacy MPStorage switch as one run read it.
public enum LegacyMPStorageSwitch: String, Sendable, Hashable, Codable {
    /// Absent from the legacy settings, or not read yet.
    case notRead
    /// `mpstorage_active` was on.
    case active
    /// `mpstorage_active` was off.
    case inactive
}

/// The result of one `LegacyImporter.run`: one outcome per step, counts only.
public struct LegacyImportReport: Sendable, Equatable {
    /// The outcome of each step.
    public var outcomes: [LegacyImportStep: LegacyImportOutcome]
    /// Legacy accounts or list entries left out because LOT-061/065 refuse them (empty or logged-out pseudo,
    /// `md_user` naming another pseudo).
    public var rejectedItems: Int
    /// The legacy `mpstorage_active` switch, read once and kept in the import state, so every report gives it: LOT-130
    /// turns it into each account's sync record (ADR 0013 §7: active → `on`, inactive → `unasked`).
    public var mpStorageSwitch: LegacyMPStorageSwitch

    /// Creates a report.
    public init(
        outcomes: [LegacyImportStep: LegacyImportOutcome] = [:],
        rejectedItems: Int = 0,
        mpStorageSwitch: LegacyMPStorageSwitch = .notRead
    ) {
        self.outcomes = outcomes
        self.rejectedItems = rejectedItems
        self.mpStorageSwitch = mpStorageSwitch
    }

    /// True when every step is done; otherwise the app runs the import again later (next launch, next login).
    public var isComplete: Bool {
        LegacyImportStep.allCases.allSatisfy { outcomes[$0]?.isDone == true }
    }
}
