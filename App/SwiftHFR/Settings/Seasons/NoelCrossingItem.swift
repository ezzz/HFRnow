import CoreGraphics

/// The art that crosses the screen in Noël soft (THEMES.md §4 rule 4, §5), from the operator's validated renders
/// (`docs/assets/themes/renders/`, 2026-11-10; CREDITS.md « Seasonal art »).
enum NoelCrossingItem: String, CaseIterable, Sendable {
    /// Santa's sleigh pulled by two reindeer harnessed in front, drawn facing the trailing edge: the arrival, and a small one.
    case sleigh
    case star
    case gift
    case giftBlue
    case giftGold
    case ornament
    case snowflake

    /// The items that cross now and then; the sleigh among them, small (THEMES.md tokens `crossingItems.noel-soft`).
    static let crossing: [NoelCrossingItem] = [.sleigh, .star, .gift, .giftBlue, .giftGold, .ornament, .snowflake]

    /// The image in the asset catalog.
    var assetName: String {
        switch self {
        case .sleigh: "NoelSleigh"
        case .star: "NoelStar"
        case .gift: "NoelGift"
        case .giftBlue: "NoelGiftBlue"
        case .giftGold: "NoelGiftGold"
        case .ornament: "NoelOrnament"
        case .snowflake: "NoelSnowflake"
        }
    }

    /// Width over height of the image (the render, trimmed by `tooling/art/noel-crossings/derive.swift`).
    var aspectRatio: Double {
        switch self {
        case .sleigh: 807.0 / 285
        case .star: 793.0 / 767
        case .gift, .giftBlue, .giftGold: 718.0 / 762
        case .ornament: 564.0 / 738
        case .snowflake: 809.0 / 712
        }
    }

    /// The art has a front: it faces its travel, mirrored as a whole when it goes the other way (THEMES.md §6 rule 3). The
    /// others (a star, a gift, an ornament, a flake) have none and stay upright.
    var isDirectional: Bool { self == .sleigh }

    /// Its size for a height of `height` points.
    func size(height: CGFloat) -> CGSize { CGSize(width: height * aspectRatio, height: height) }
}
