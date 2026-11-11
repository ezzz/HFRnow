import Foundation

/// A theme as its `theme.json` describes it (THEMES.md §3, LOT-188): identity, credit, font design and its colour variants.
public struct ThemeDefinition: Sendable, Hashable, Identifiable, Decodable {
    /// The id of the Legacy theme: today's app (LOT-121/122). Its file carries no tokens and the engine overrides nothing.
    public static let legacyID = "legacy"

    /// The text style family the theme asks for.
    public enum FontDesign: String, Sendable, Hashable, Decodable {
        case `default`, rounded, monospaced
    }

    /// The colour variants: one per appearance, or one for both.
    public enum Variants: Sendable, Hashable {
        /// A light and a dark variant, chosen by the appearance (LOT-121's picker or iOS).
        case lightDark(light: ThemeTokens, dark: ThemeTokens)
        /// One variant for both appearances (« clair = sombre »).
        case single(ThemeTokens)

        /// The tokens shown in light.
        public var light: ThemeTokens {
            switch self {
            case let .lightDark(light, _): light
            case let .single(tokens): tokens
            }
        }

        /// The tokens shown in dark.
        public var dark: ThemeTokens {
            switch self {
            case let .lightDark(_, dark): dark
            case let .single(tokens): tokens
            }
        }
    }

    /// Unique id; the folder name and the stored `theme_id`.
    public let id: String
    /// Name shown in the gallery.
    public let name: String
    /// Gallery family (« Classiques », « Rétro », « OG Web », or a seasonal one).
    public let family: String
    /// Author shown as « par <auteur> », or nil.
    public let author: String?
    /// The text design of the whole app.
    public let fontDesign: FontDesign
    /// Decorations id (THEMES.md §4, LOT-166), or nil.
    public let decorations: String?
    /// The colours; nil only for the Legacy theme, which keeps the app's own (LOT-121/122).
    public let variants: Variants?

    /// Creates a theme; `variants` may be nil only for `legacyID`.
    public init(
        id: String, name: String, family: String, author: String?, fontDesign: FontDesign = .default, decorations: String? = nil,
        variants: Variants?
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.author = author
        self.fontDesign = fontDesign
        self.decorations = decorations
        self.variants = variants
    }

    /// Whether this is the Legacy theme.
    public var isLegacy: Bool { id == Self.legacyID }

    private enum CodingKeys: String, CodingKey {
        case id, name, family, author, fontDesign, decorations, variants
    }

    private enum VariantKeys: String, CodingKey {
        case light, dark, any
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        guard id.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Theme id must be kebab-case: \(id)")
        }
        name = try container.decode(String.self, forKey: .name)
        family = try container.decode(String.self, forKey: .family)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        fontDesign = try container.decodeIfPresent(FontDesign.self, forKey: .fontDesign) ?? .default
        decorations = try container.decodeIfPresent(String.self, forKey: .decorations)
        guard container.contains(.variants), try !container.decodeNil(forKey: .variants) else {
            guard id == Self.legacyID else {
                throw DecodingError.keyNotFound(
                    CodingKeys.variants, .init(codingPath: container.codingPath, debugDescription: "Only Legacy has no variants")
                )
            }
            variants = nil
            return
        }
        guard id != Self.legacyID else {
            throw DecodingError.dataCorruptedError(
                forKey: .variants, in: container, debugDescription: "Legacy keeps the app's own colours: no variants"
            )
        }
        let nested = try container.nestedContainer(keyedBy: VariantKeys.self, forKey: .variants)
        let light = try nested.decodeIfPresent(ThemeTokens.self, forKey: .light)
        let dark = try nested.decodeIfPresent(ThemeTokens.self, forKey: .dark)
        let any = try nested.decodeIfPresent(ThemeTokens.self, forKey: .any)
        switch (light, dark, any) {
        case let (light?, dark?, nil): variants = .lightDark(light: light, dark: dark)
        case let (nil, nil, any?): variants = .single(any)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .variants, in: container, debugDescription: "Variants are light + dark, or any alone"
            )
        }
    }

    /// The contrast rules each variant breaks, named `light`, `dark` or `any`; empty when the theme meets THEMES.md §3.
    public var contrastViolations: [(variant: String, violation: ThemeTokens.Violation)] {
        switch variants {
        case nil: []
        case let .lightDark(light, dark)?:
            light.contrastViolations.map { ("light", $0) } + dark.contrastViolations.map { ("dark", $0) }
        case let .single(tokens)?: tokens.contrastViolations.map { ("any", $0) }
        }
    }

    /// The gallery's families in their order (THEMES.md §1); a family not listed here comes after them, by name.
    public static let familyOrder = ["Classiques", "Rétro", "OG Web"]

    /// The seasonal families (THEMES.md §5): shown only inside their window, which LOT-166 owns; hidden until then.
    public static let seasonalFamilies: Set = ["Noël", "Samain"]
}
