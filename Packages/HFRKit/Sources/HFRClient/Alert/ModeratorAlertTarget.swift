import Foundation
import HFRModels

/// The message an alert link names, read from its parameters, never from a substring (LOT-031's alert link).
public struct ModeratorAlertTarget: Sendable, Hashable {
    /// The forum topic of the message.
    public let topic: TopicID
    /// The message's `numreponse`.
    public let numreponse: Int

    /// Nil unless `link` is an `https` page of the forum (LESSONS 37, 43) whose path is exactly `/user/modo.php`, with
    /// `config=hfr.inc` and a single forum `cat`, `post` and `numreponse`, as on `R21` and `R46`. A private conversation
    /// has no alert link (`RA1`-`RA4`), so `cat=prive` is refused.
    init?(_ link: URL) {
        guard
            PostingFlow.isForumPage(link),
            let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
            components.percentEncodedPath == Self.path,
            let items = components.queryItems,
            Self.single("config", in: items) == "hfr.inc",
            case .forum(let category)? = Self.single("cat", in: items).flatMap(CategoryID.init(queryValue:)), category > 0,
            let post = Self.single("post", in: items).flatMap(Self.positiveInteger),
            let numreponse = Self.single("numreponse", in: items).flatMap(Self.positiveInteger)
        else { return nil }
        self.topic = TopicID(category: .forum(category), topic: post)
        self.numreponse = numreponse
    }

    /// Path of the alert page and of its form's action (`R46`).
    static let path = "/user/modo.php"

    /// The value of `name` when it appears exactly once: a repeated parameter is ambiguous.
    private static func single(_ name: String, in items: [URLQueryItem]) -> String? {
        let values = items.filter { $0.name == name }
        guard values.count == 1 else { return nil }
        return values.first?.value
    }

    /// Decimal digits only, no sign, greater than zero.
    private static func positiveInteger(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(text), number > 0 else { return nil }
        return number
    }
}
