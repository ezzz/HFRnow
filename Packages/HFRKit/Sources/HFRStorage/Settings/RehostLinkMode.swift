/// The `rehost_use_link` setting: which BBCode the rehost upload inserts (legacy `RehostBBCodeMode`, `ReplyService.swift:1735`).
public enum RehostLinkMode: Int, Sendable, Codable, CaseIterable {
    /// Image wrapped in a link to the full-size file (default).
    case imageWithLink = 0
    /// Image alone.
    case imageNoLink = 1
    /// Link alone.
    case linkOnly = 2
}
