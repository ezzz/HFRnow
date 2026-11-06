/// The `mp_list_display` setting (LOT-171): one Messages list, or one-to-one and group conversations apart.
/// A new key, no legacy counterpart: absent or unknown reads as `.single`, so nothing changes until the member opts in.
public enum MPListDisplay: String, Sendable, Codable, CaseIterable {
    /// "Tout en un": every conversation in one list (the default, LOT-126's list).
    case single
    /// "Deux listes": a switch "MP" / "MP multiples" splits the list.
    case split
}
