/// Pseudo comparison form used in draft keys: zero-width spaces removed, lower-cased (same rule as the blocklist
/// matching of LOT-061, kept private here so that the two lots stay independent).
enum DraftNameNormalizer {
    static func normalize(_ name: String) -> String {
        name.filter { $0 != "\u{200B}" }.lowercased()
    }
}
