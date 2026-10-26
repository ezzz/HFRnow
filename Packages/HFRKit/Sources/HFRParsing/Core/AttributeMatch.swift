/// How an attribute value is compared when searching descendants, mirroring the legacy `HTMLNode` lookups.
///
/// Legacy `findChildWithAttribute:matchingName:allowPartial:` compares the **whole attribute value**
/// (`strcmp`, `allowPartial:NO`) or looks for a **substring** (`strstr`, `allowPartial:YES`)
/// (`SuperHFRplus/Vendor/HTMLParser/HTMLNode.m:105-139, 232-270`). Neither is a CSS class match:
/// `exact("left")` misses `class="left nav"`, and `contains("sujetCase1")` also matches `sujetCase10`.
/// Ported parsers pick the legacy mode the oracle used; new code should prefer `classToken`.
enum AttributeMatch: Sendable, Equatable {
    /// The whole attribute value equals the string (legacy `allowPartial:NO`, `findChildOfClass:`).
    case exact(String)
    /// The attribute value contains the string anywhere (legacy `allowPartial:YES`).
    case contains(String)
    /// One token of the value, split on ASCII whitespace, equals the string (CSS `.name` semantics).
    case classToken(String)

    /// Whether an attribute value satisfies this match.
    func matches(_ value: String) -> Bool {
        switch self {
        case .exact(let expected):
            value == expected
        case .contains(let fragment):
            // `strstr` with an empty needle matches everything; keep that legacy edge.
            fragment.isEmpty || value.contains(fragment)
        case .classToken(let token):
            value.htmlClassTokens.contains { $0 == token }
        }
    }

    /// Short description used in `ParsingError.missingElement`; contains the searched name only.
    func description(attribute: String) -> String {
        switch self {
        case .exact(let name): "\(attribute)=\(name)"
        case .contains(let name): "\(attribute)*=\(name)"
        case .classToken(let name): "\(attribute)~=\(name)"
        }
    }
}
