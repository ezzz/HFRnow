import Foundation

/// Display rewrite of a topic title: the one place that abbreviates "Topic Unique" and its spellings to "TU".
///
/// Port of `-[NSString filterTU]` (`SuperHFRplus/Helpers/RangeOfCharacters.m:330-343` @ 87fe0d1c), which legacy applies in
/// `Topic -setATitle:` (`Topic.m:90-94`) and to the reader title (`OnlineMessagesTableViewController.m`, `-setTopicName:`).
/// Parsers keep the raw title (LOT-022 D4); views show `TopicTitle.displayed(_:)`. Idempotent: "TU" matches no spelling.
public enum TopicTitle {
    /// Spellings in legacy order; each is a case-insensitive literal match (`NSCaseInsensitiveSearch`, no regex meaning
    /// for the dots of "T.U."). Order matters only for overlaps, and none of them overlap.
    private static let spellings = [
        "topic unique", "T.U.", "topik unique", "toupik ounik", "topique unique",
        "topic unik", "topik unik", "topic officiel", "TOPIKUNIK"
    ]

    /// The title as legacy shows it: every spelling replaced by "TU".
    public static func displayed(_ title: String) -> String {
        spellings.reduce(title) { result, spelling in
            result.replacingOccurrences(of: spelling, with: "TU", options: .caseInsensitive)
        }
    }
}
