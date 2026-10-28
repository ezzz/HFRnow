import Foundation
import HFRModels

/// A flag link (`addflag.php`, `delflag.php`) recognised by its parsed path and parameters, never by a substring.
///
/// The link is followed with the account's cookies, so it must be an `https` page of the forum (LESSONS 37, 43) whose
/// path is exactly the write's, with `config=hfr.inc` and a single forum `cat` and `post`, as on `R21`, `P03a` and `P03d`.
struct FlagLink: Equatable {
    /// The link to request, without its fragment.
    let url: URL
    /// The topic named by `cat` and `post`.
    let topic: TopicID

    /// Nil when `link` is not a link of the write whose path is `path`.
    init?(_ link: URL, path: String) {
        guard
            PostingFlow.isForumPage(link),
            var components = URLComponents(url: link, resolvingAgainstBaseURL: false),
            components.percentEncodedPath == path,
            let items = components.queryItems,
            Self.single("config", in: items) == "hfr.inc",
            let category = Self.single("cat", in: items).flatMap(CategoryID.init(queryValue:)),
            case .forum(let number) = category, number > 0,
            let post = Self.single("post", in: items).flatMap(Self.positiveInteger)
        else { return nil }
        components.fragment = nil
        guard let url = components.url else { return nil }
        self.url = url
        self.topic = TopicID(category: category, topic: post)
    }

    /// The value of the parameter `name` when it appears exactly once: a repeated one is ambiguous, the server may read
    /// either copy.
    private static func single(_ name: String, in items: [URLQueryItem]) -> String? {
        let values = items.filter { $0.name == name }
        guard values.count == 1 else { return nil }
        return values[0].value
    }

    /// A positive integer written with ASCII digits only (`Int("+5")` would accept a sign).
    static func positiveInteger(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text), value > 0 else {
            return nil
        }
        return value
    }
}
