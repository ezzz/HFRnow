import CoreGraphics

/// The art that crosses the screen in Noël soft and Spooktober soft (THEMES.md §4 rule 4, §5), from the operator's validated
/// renders (`docs/assets/themes/renders/`, 2026-11-10; CREDITS.md « Seasonal art »). The name is Noël's, which came first: the
/// Samain items (LOT-191) share its engine.
enum NoelCrossingItem: String, CaseIterable, Sendable {
    /// Santa's sleigh pulled by two reindeer harnessed in front, drawn facing the trailing edge: the arrival, and a small one.
    case sleigh
    case star
    case gift
    case giftBlue
    case giftGold
    case ornament
    case snowflake
    /// A witch on her broom, drawn facing the leading edge.
    case witch
    case ghost
    case bat
    case vampire
    /// Lightning does not travel: five flashes at random places (`LightningFlash`).
    case lightning

    /// The items that cross Noël soft now and then; the sleigh among them, small (THEMES.md tokens `crossingItems.noel-soft`).
    static let crossing: [NoelCrossingItem] = [.sleigh, .star, .gift, .giftBlue, .giftGold, .ornament, .snowflake]
    /// The items that cross Spooktober soft now and then (tokens `crossingItems.samain-soft`: lightning, ghost, witch on a broom).
    static let samainCrossing: [NoelCrossingItem] = [.lightning, .ghost, .witch]
    /// The items of the Samain arrival, one at random: a witch on a broom, a ghost or a bat or vampire (THEMES.md §5).
    static let samainArrival: [NoelCrossingItem] = [.witch, .ghost, .bat, .vampire]

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
        case .witch: "SamainWitch"
        case .ghost: "SamainGhost"
        case .bat: "SamainBat"
        case .vampire: "SamainVampire"
        case .lightning: "SamainLightning"
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
        case .witch: 809.0 / 643
        case .ghost: 540.0 / 764
        case .bat: 808.0 / 225
        case .vampire: 810.0 / 621
        case .lightning: 380.0 / 796
        }
    }

    /// The art has a front: it faces its travel, mirrored as a whole when it goes the other way (THEMES.md §6 rule 3). The
    /// others (a star, a gift, an ornament, a flake, a ghost, a bat, a vampire, a flash) have none and stay upright.
    var isDirectional: Bool { self == .sleigh || self == .witch }

    /// The render faces the leading edge (the witch), where the sleigh faces the trailing one.
    var facesLeading: Bool { self == .witch }

    /// Its size for a height of `height` points.
    func size(height: CGFloat) -> CGSize { CGSize(width: height * aspectRatio, height: height) }
}
