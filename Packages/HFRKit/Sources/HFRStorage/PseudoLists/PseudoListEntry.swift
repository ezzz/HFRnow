/// One entry of the blocklist or the allowlist.
///
/// The persisted keys (`word`, `alias`, `mode`) are the legacy plist ones (`BlackList.m:43`), so importing the old
/// files is a plain mapping. `alias` and `mode` are not used by the UI (`mode` 0 is the legacy `kTerminator`) but kept.
public struct PseudoListEntry: Sendable, Hashable, Codable {
    /// The pseudo as the user added it (comparison goes through `PseudoNormalizer`).
    public var pseudo: String
    /// Legacy alias, empty today.
    public var alias: String
    /// Legacy mode, 0 today.
    public var mode: Int

    /// Creates an entry.
    public init(pseudo: String, alias: String = "", mode: Int = 0) {
        self.pseudo = pseudo
        self.alias = alias
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case pseudo = "word"
        case alias
        case mode
    }
}
