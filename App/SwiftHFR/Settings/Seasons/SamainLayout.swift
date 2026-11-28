import CoreGraphics
import Foundation
import HFRModels

// No legacy counterpart @ 87fe0d1c (legacy has no Halloween theme; GAP row of LOT-191).
/// Where the Samain themes put their art on a screen's background, behind the content (THEMES.md §2, §4 rule 7, §6; board
/// `theme-samain.jpg`). Spooktober soft keeps to the top trailing corner under the navigation row and the home indicator's
/// inset, at full opacity, so the bat and the rest keep their contrast on the dark variant (§4 rule 7); Spooktober abusé covers
/// more of the screen and is drawn at `fullOpacity`, so the text native screens draw on its background stays readable. Each
/// column of a split view lays out its own.
/// Pure, so the limits are tested. Coordinates are the screen's, origin top leading, insets included.
nonisolated enum SamainLayout {
    /// What a decoration is: the asset and its aspect ratio (the trimmed render, `tooling/art/noel-crossings/derive.swift samain`).
    enum Art: String, CaseIterable, Sendable {
        case web = "SamainWeb"
        case candelabra = "SamainCandelabra"
        case bat = "SamainBat"
        case moon = "SamainMoon"
        case pumpkin = "SamainPumpkin"
        case pumpkinPlain = "SamainPumpkinPlain"

        /// Width over height of the trimmed render.
        var aspectRatio: Double {
            switch self {
            case .web, .moon: 1
            case .candelabra: 527.0 / 792
            case .bat: 808.0 / 225
            case .pumpkin, .pumpkinPlain: 736.0 / 653
            }
        }
    }

    /// One piece of art at its frame; `mirrored` turns it round the vertical axis (the web's render sits in a top leading corner).
    struct Piece: Equatable, Sendable {
        var art: Art
        var frame: CGRect
        var mirrored = false
    }

    /// The two backdrops: the soft theme's (`samain-soft`) and the abusé theme's (`samain-full`).
    enum Kind: String, Sendable {
        case soft = "samain-soft"
        case full = "samain-full"

        /// The art's opacity over the background. The abusé art is faded so that even a white pixel under the system label, its
        /// secondary label (60 % of #EBEBF5, the section headers) and the tint keeps ≥ 4.5:1 on Spooktober abusé's `background`
        /// (5.09:1 at 14 %, the tightest, tested). The soft art is not faded: it stays in the corners and beside the title.
        var opacity: Double { self == .soft ? 1 : SamainLayout.fullOpacity }
    }

    static let fullOpacity = 0.14

    /// The soft theme's bat is drawn as a silhouette in the operator's draft colours (`docs/assets/themes/tokens/themes.json`,
    /// `decorationColors.bat`, 2026-10-28): near black on the light variant, the grey-violet `textSecondary` on the dark one
    /// (7.13:1 on its background; black was 1.11:1).
    static let batOnLight = ThemeRGB(red: 0x14, green: 0x0A, blue: 0x1F)
    static let batOnDark = ThemeRGB(red: 0xA9, green: 0x9A, blue: 0xAD)

    /// A screen narrower or shorter than this carries no art: the pieces would sit on the text.
    static let minimumWidth: CGFloat = 240
    static let minimumHeight: CGFloat = 320

    /// The pieces of `kind` on a screen of `size` whose status bar is `topInset` high and home indicator `bottomInset` high.
    static func pieces(_ kind: Kind, in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> [Piece] {
        guard size.width >= minimumWidth, size.height >= minimumHeight else { return [] }
        let screen = CGRect(origin: .zero, size: size)
        let all = switch kind {
        case .soft: soft(in: size, topInset: topInset, bottomInset: bottomInset)
        case .full: full(in: size, topInset: topInset, bottomInset: bottomInset)
        }
        // A piece that would leave the screen (a narrow column) is dropped, never squeezed.
        return all.filter { screen.contains($0.frame) }
    }

    /// The soft theme keeps its art out of the chrome and of the text (THEMES.md §4 rules 7 and 9): a web in the top trailing
    /// corner under the navigation bar and its large title (clear of the status bar, the toolbar buttons and the title), and a
    /// candelabra with a small bat standing on the home indicator's inset, below the tab bar. A screen without that inset has no
    /// candelabra.
    private static func soft(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> [Piece] {
        let web = min(72, size.width * 0.2)
        var pieces = [
            Piece(art: .web, frame: CGRect(x: size.width - web, y: topInset + titleRows, width: web, height: web), mirrored: true)
        ]
        guard bottomInset >= minimumInset else { return pieces }
        let height = min(bottomInset, 34)
        let floor = size.height
        let candelabra = frame(.candelabra, height: height, trailing: size.width - 16, bottom: floor)
        pieces.append(Piece(art: .candelabra, frame: candelabra))
        pieces.append(Piece(art: .bat, frame: frame(.bat, height: 12, trailing: candelabra.minX - 8, bottom: floor - (height - 12) / 2)))
        return pieces
    }

    /// The height of a navigation bar's own row and of the large title under it: the soft web hangs below both, so a long title
    /// never runs over its strands (review of #1441), and the smallest home indicator inset that can hold the candelabra.
    static let navigationRow: CGFloat = 44
    static let largeTitleRow: CGFloat = 56
    static let titleRows = navigationRow + largeTitleRow
    static let minimumInset: CGFloat = 24

    /// Webs in both top corners (below the status bar), the moon behind the title with two bats, pumpkins and the candelabra
    /// standing on the home indicator's inset.
    private static func full(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> [Piece] {
        let web = min(130, size.width * 0.34)
        let moon = min(170, size.width * 0.42)
        let moonFrame = CGRect(x: size.width * 0.5 - moon / 2, y: topInset + 24, width: moon, height: moon)
        let floor = size.height - bottomInset
        var pieces = [
            Piece(art: .web, frame: CGRect(x: 0, y: topInset, width: web, height: web)),
            Piece(art: .web, frame: CGRect(x: size.width - web, y: topInset, width: web, height: web), mirrored: true),
            Piece(art: .moon, frame: moonFrame),
            Piece(art: .bat, frame: frame(.bat, height: 22, trailing: moonFrame.minX + 6, top: moonFrame.minY + moon * 0.2)),
            Piece(art: .bat, frame: frame(.bat, height: 16, trailing: moonFrame.maxX + 40, top: moonFrame.minY - 6))
        ]
        guard size.height >= 480 else { return pieces }
        let pumpkin = frame(.pumpkin, height: 70, leading: 8, bottom: floor)
        pieces.append(Piece(art: .pumpkin, frame: pumpkin))
        pieces.append(Piece(art: .pumpkinPlain, frame: frame(.pumpkinPlain, height: 52, leading: pumpkin.maxX + 4, bottom: floor)))
        pieces.append(Piece(art: .candelabra, frame: frame(.candelabra, height: 120, trailing: size.width - 12, bottom: floor)))
        return pieces
    }

    private static func frame(_ art: Art, height: CGFloat, trailing: CGFloat, top: CGFloat) -> CGRect {
        let width = height * art.aspectRatio
        return CGRect(x: trailing - width, y: top, width: width, height: height)
    }

    private static func frame(_ art: Art, height: CGFloat, trailing: CGFloat, bottom: CGFloat) -> CGRect {
        let width = height * art.aspectRatio
        return CGRect(x: trailing - width, y: bottom - height, width: width, height: height)
    }

    private static func frame(_ art: Art, height: CGFloat, leading: CGFloat, bottom: CGFloat) -> CGRect {
        CGRect(x: leading, y: bottom - height, width: height * art.aspectRatio, height: height)
    }
}
