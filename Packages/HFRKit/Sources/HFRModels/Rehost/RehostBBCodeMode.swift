/// How an uploaded image is pasted into a post; raw values are the legacy `rehost_use_link` setting.
public enum RehostBBCodeMode: Int, Sendable, Codable {
    /// `[url=FULL][img]URL[/img][/url]` (legacy default).
    case imageWithLink = 0
    /// `[img]URL[/img]`.
    case imageNoLink = 1
    /// The bare URL.
    case linkOnly = 2
}
