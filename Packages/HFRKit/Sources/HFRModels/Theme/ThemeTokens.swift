import Foundation

/// The colours of one theme variant (THEMES.md §3, LOT-188). Every variant defines every required token; the optional
/// table-like tokens (LOT-193) fall back to required ones, so a theme that omits them is unchanged.
public struct ThemeTokens: Sendable, Hashable, Decodable {
    /// Screen background.
    public let background: ThemeRGB
    /// Rows, cards and the reader's page.
    public let surface: ThemeRGB
    /// Bars and sheets.
    public let surfaceRaised: ThemeRGB
    /// Titles drawn on `background`.
    public let title: ThemeRGB
    /// Section headers drawn on `background`.
    public let sectionHeader: ThemeRGB
    /// Body text on `surface`.
    public let textPrimary: ThemeRGB
    /// Dates, counters and read MP titles (#651) on `surface`.
    public let textSecondary: ThemeRGB
    /// Fills only: badges, toggles, selection.
    public let accent: ThemeRGB
    /// Content drawn on `accent`.
    public let onAccent: ThemeRGB
    /// The accent used as text or glyph.
    public let accentText: ThemeRGB
    /// Links in messages.
    public let link: ThemeRGB
    /// Separators (one definition, #572).
    public let separator: ThemeRGB
    /// The selected row.
    public let selection: ThemeRGB
    /// Reader quote block background.
    public let quoteBackground: ThemeRGB
    /// Reader quote block border.
    public let quoteBorder: ThemeRGB
    /// Reader `[code]` block background (always monospace).
    public let codeBackground: ThemeRGB
    /// Reader `[code]` block text.
    public let codeText: ThemeRGB
    /// Reader spoiler block background.
    public let spoilerBackground: ThemeRGB
    /// Reader spoiler block text.
    public let spoilerText: ThemeRGB
    /// Unread badge and capsule fill (#646).
    public let unread: ThemeRGB
    /// Text on `unread`.
    public let onUnread: ThemeRGB

    /// Optional: the header band of a table-like theme; `surfaceRaised` when absent.
    public let headerBand: ThemeRGB?
    /// Optional: the alternate cell of a table-like theme; `surface` when absent.
    public let alternateCell: ThemeRGB?
    /// Optional: meta text (author, date) of a table-like theme; `textSecondary` when absent.
    public let meta: ThemeRGB?
    /// Optional: the page bar of a table-like theme; `surfaceRaised` when absent.
    public let pageBar: ThemeRGB?
    /// Optional: counters of a table-like theme; `textSecondary` when absent.
    public let counter: ThemeRGB?

    /// Decodes every token; a name that is not a token (a typo of an optional one would otherwise be ignored) is an error.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ThemeFileKey.self)
        let known = Set(Self.requiredNames + Self.optionalNames)
        try ThemeFileKey.refuseUnknown(in: container, known: known, what: "theme token")
        func required(_ name: String) throws -> ThemeRGB {
            try container.decode(ThemeRGB.self, forKey: ThemeFileKey(stringValue: name))
        }
        func optional(_ name: String) throws -> ThemeRGB? {
            try container.decodeIfPresent(ThemeRGB.self, forKey: ThemeFileKey(stringValue: name))
        }
        background = try required("background")
        surface = try required("surface")
        surfaceRaised = try required("surfaceRaised")
        title = try required("title")
        sectionHeader = try required("sectionHeader")
        textPrimary = try required("textPrimary")
        textSecondary = try required("textSecondary")
        accent = try required("accent")
        onAccent = try required("onAccent")
        accentText = try required("accentText")
        link = try required("link")
        separator = try required("separator")
        selection = try required("selection")
        quoteBackground = try required("quoteBackground")
        quoteBorder = try required("quoteBorder")
        codeBackground = try required("codeBackground")
        codeText = try required("codeText")
        spoilerBackground = try required("spoilerBackground")
        spoilerText = try required("spoilerText")
        unread = try required("unread")
        onUnread = try required("onUnread")
        headerBand = try optional("headerBand")
        alternateCell = try optional("alternateCell")
        meta = try optional("meta")
        pageBar = try optional("pageBar")
        counter = try optional("counter")
    }

    /// The names of the required tokens, in the order of THEMES.md §3.
    public static let requiredNames = [
        "background", "surface", "surfaceRaised", "title", "sectionHeader", "textPrimary", "textSecondary", "accent", "onAccent",
        "accentText", "link", "separator", "selection", "quoteBackground", "quoteBorder", "codeBackground", "codeText",
        "spoilerBackground", "spoilerText", "unread", "onUnread"
    ]

    /// The names of the optional tokens.
    public static let optionalNames = ["headerBand", "alternateCell", "meta", "pageBar", "counter"]

    /// `headerBand`, or its fallback.
    public var resolvedHeaderBand: ThemeRGB { headerBand ?? surfaceRaised }
    /// `alternateCell`, or its fallback.
    public var resolvedAlternateCell: ThemeRGB { alternateCell ?? surface }
    /// `meta`, or its fallback.
    public var resolvedMeta: ThemeRGB { meta ?? textSecondary }
    /// `pageBar`, or its fallback.
    public var resolvedPageBar: ThemeRGB { pageBar ?? surfaceRaised }
    /// `counter`, or its fallback.
    public var resolvedCounter: ThemeRGB { counter ?? textSecondary }

    private static let black = ThemeRGB(red: 0, green: 0, blue: 0)
    private static let white = ThemeRGB(red: 255, green: 255, blue: 255)

    /// Whether the variant reads as light: black text contrasts more with its background than white does. A single-variant
    /// theme shows in this appearance whatever the "Thème" picker says, so the system's own text and chrome match it.
    public var isLight: Bool {
        background.contrast(with: Self.black) >= background.contrast(with: Self.white)
    }

    /// One contrast rule of THEMES.md §3: `foreground` must reach `minimum` on `background`.
    public struct ContrastRule: Sendable, Hashable {
        /// The text or glyph token.
        public let foreground: String
        /// The token it is drawn on.
        public let background: String
        /// The WCAG ratio it must reach.
        public let minimum: Double
    }

    /// Every rule a variant must meet (WCAG 2.x, 4.5:1, no large-text exception): THEMES.md §3, then every other pair the app
    /// draws (LOT-188 spec). Three names are derived, not tokens: `systemText` (the system label of the appearance the variant
    /// shows in, black in light, white in dark: native text keeps it), `systemCard` (the system's list card in that appearance,
    /// #FFFFFF or #1C1C1E: native rows keep it, and the tint draws on it) and `readerAlternate` (the reader's even message,
    /// `textPrimary` mixed into `surface` at its strongest, Increase Contrast, strength: 7 % in light, 16 % in dark, `reader.css`).
    public static let contrastRules: [ContrastRule] = [
        // THEMES.md §3.
        ("title", "background"), ("sectionHeader", "background"),
        ("textPrimary", "surface"), ("textSecondary", "surface"),
        ("onAccent", "accent"), ("accentText", "surface"), ("link", "surface"),
        ("textPrimary", "quoteBackground"), ("textSecondary", "quoteBackground"),
        ("codeText", "codeBackground"), ("spoilerText", "spoilerBackground"),
        ("onUnread", "unread"),
        // Native screens: system text on the theme's background and surface, the tint on the system card and on the background
        // (toolbar and plain buttons, empty-state actions).
        ("systemText", "background"), ("systemText", "surface"), ("accentText", "systemCard"), ("accentText", "background"),
        // The reader: links and accents in quotes, spoilers and code, and every text of an even message.
        ("link", "quoteBackground"), ("link", "spoilerBackground"), ("link", "codeBackground"),
        ("textSecondary", "codeBackground"), ("accentText", "codeBackground"), ("accentText", "quoteBackground"),
        ("textPrimary", "readerAlternate"), ("textSecondary", "readerAlternate"), ("link", "readerAlternate"),
        ("accentText", "readerAlternate"),
        // Optional table tokens (LOT-193), on what they sit on.
        ("meta", "surface"), ("meta", "alternateCell"), ("counter", "surface"), ("counter", "alternateCell"),
        ("textPrimary", "alternateCell"), ("textPrimary", "headerBand"), ("textPrimary", "pageBar")
    ].map { ContrastRule(foreground: $0.0, background: $0.1, minimum: 4.5) }

    /// A rule the variant breaks, or a token of a rule that is not opaque.
    public struct Violation: Sendable, Hashable, CustomStringConvertible {
        /// The rule.
        public let rule: ContrastRule
        /// The measured ratio (0 when a colour is not opaque).
        public let ratio: Double

        public var description: String {
            let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX"))
            let measured = ratio == 0 ? "not opaque" : "\(ratio.formatted(style)):1"
            return "\(rule.foreground) on \(rule.background): \(measured), needs \(rule.minimum):1"
        }
    }

    /// Every token by name; an optional one gives its resolved value (its fallback when absent).
    static let tokensByName: [String: KeyPath<ThemeTokens, ThemeRGB> & Sendable] = [
        "background": \.background, "surface": \.surface, "surfaceRaised": \.surfaceRaised, "title": \.title,
        "sectionHeader": \.sectionHeader, "textPrimary": \.textPrimary, "textSecondary": \.textSecondary, "accent": \.accent,
        "onAccent": \.onAccent, "accentText": \.accentText, "link": \.link, "separator": \.separator, "selection": \.selection,
        "quoteBackground": \.quoteBackground, "quoteBorder": \.quoteBorder, "codeBackground": \.codeBackground,
        "codeText": \.codeText, "spoilerBackground": \.spoilerBackground, "spoilerText": \.spoilerText, "unread": \.unread,
        "onUnread": \.onUnread, "headerBand": \.resolvedHeaderBand, "alternateCell": \.resolvedAlternateCell,
        "meta": \.resolvedMeta, "pageBar": \.resolvedPageBar, "counter": \.resolvedCounter
    ]

    /// The colour of the token `name`, or of a derived name of `contrastRules`, for a variant shown in light (`inLight`) or
    /// dark; nil for an unknown name.
    public func color(named name: String, inLight: Bool) -> ThemeRGB? {
        switch name {
        case "systemText": inLight ? Self.black : Self.white
        case "systemCard": inLight ? Self.white : ThemeRGB(red: 0x1C, green: 0x1C, blue: 0x1E)
        case "readerAlternate": surface.mixed(with: textPrimary, amount: inLight ? 0.07 : 0.16)
        default: Self.tokensByName[name].map { self[keyPath: $0] }
        }
    }

    /// The rules this variant breaks, shown in light (`inLight`, a `light` slot or a light single variant) or in dark; empty when
    /// it meets them all.
    public func contrastViolations(inLight: Bool) -> [Violation] {
        Self.contrastRules.compactMap { rule in
            guard let foreground = color(named: rule.foreground, inLight: inLight),
                  let background = color(named: rule.background, inLight: inLight) else {
                return Violation(rule: rule, ratio: 0)
            }
            guard foreground.isOpaque, background.isOpaque else { return Violation(rule: rule, ratio: 0) }
            let ratio = foreground.contrast(with: background)
            return ratio >= rule.minimum ? nil : Violation(rule: rule, ratio: ratio)
        }
    }
}

/// Any key of a theme file, to refuse the names a theme file does not know (a typo would otherwise be ignored).
struct ThemeFileKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }

    /// Throws if `container` holds a key outside `known`.
    static func refuseUnknown(in container: KeyedDecodingContainer<ThemeFileKey>, known: Set<String>, what: String) throws {
        if let unknown = container.allKeys.first(where: { !known.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: unknown, in: container, debugDescription: "Unknown \(what) \(unknown.stringValue)"
            )
        }
    }
}
