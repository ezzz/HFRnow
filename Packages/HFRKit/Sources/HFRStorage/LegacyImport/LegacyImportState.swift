import Foundation

/// What the import already did on this device (`migration.legacyImport.version`, ADR 0013 appendix F). Device-only.
public struct LegacyImportStateDocument: SmallStoreDocument {
    /// The format of this document.
    public static let currentVersion = 1
    /// No step done yet.
    public static var empty: Self { Self() }
    /// The version of the import (`migration.legacyImport.version`); a later import with new steps raises it.
    public static let importVersion = 1

    /// Format version of this document.
    public var version: Int
    /// The import version that last ran.
    public var importVersion: Int
    /// Steps done for good, in step order.
    public var done: [LegacyImportStep]
    /// The pseudo of the account that receives the legacy app's global items, once known (decision D3).
    public var globalAccount: String?

    /// Creates a document.
    public init(
        version: Int = Self.currentVersion,
        importVersion: Int = Self.importVersion,
        done: [LegacyImportStep] = [],
        globalAccount: String? = nil
    ) {
        self.version = version
        self.importVersion = importVersion
        self.done = done
        self.globalAccount = globalAccount
    }
}
