/// The flag shown in a topic row's flag cell, derived from the flag image HFR serves.
public enum TopicFlag: String, Sendable, Codable {
    /// `flag0.gif`: topic already read (owntopic=2 list).
    case red
    /// `flag1.gif`: topic with a flag, tracked (owntopic=1 list).
    case blue
    /// `favoris.gif`: topic in the favourites (owntopic=3 list).
    case yellow
}
