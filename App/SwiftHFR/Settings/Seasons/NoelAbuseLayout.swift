import CoreGraphics
import Foundation

/// Where Noël abusé's art sits on a screen's background, behind the content (THEMES.md §2, §4 rule 7; board `theme-noel.jpg`):
/// a garland along the top with an ornament hanging from each piece, a pattern of small stars, the tree in the bottom trailing
/// corner and gifts in the leading one. Each column of a split view lays out its own. Everything is drawn at `artOpacity`, so
/// the text native screens draw on the background (the system label and secondary label of the dark appearance, the tint)
/// keeps 4.5:1 even over a white pixel of the art. Pure, so the limits are tested.
nonisolated enum NoelAbuseLayout {
    /// The art's opacity over the background: white at this opacity still leaves the system secondary label (60 % white, the
    /// section headers and footers of native lists) ≥ 4.5:1 on Noël abusé's `background`, the tightest text it carries.
    static let artOpacity = 0.08
    /// Distance between two stars of the pattern, and a star's side.
    static let starSpacing: CGFloat = 64
    static let starSide: CGFloat = 14
    /// The garland's height; it repeats along the width.
    static let garlandHeight: CGFloat = 34
    /// Width over height of the trimmed renders (`tooling/art/noel-crossings/derive.swift`).
    static let garlandAspectRatio: Double = 808.0 / 101
    static let treeAspectRatio: Double = 580.0 / 802
    static let giftAspectRatio: Double = 718.0 / 762
    /// The tallest tree.
    static let maxTreeHeight: CGFloat = 260

    /// The star centres: a grid `starSpacing` apart, every other row shifted by half a step (none on an empty screen).
    static func stars(in size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0 else { return [] }
        let rows = Int(size.height / starSpacing)
        let columns = Int(size.width / starSpacing)
        return (0...rows).flatMap { row in
            (0...columns).map { column in
                let shift = row.isMultiple(of: 2) ? starSpacing / 4 : starSpacing * 3 / 4
                return CGPoint(x: CGFloat(column) * starSpacing + shift, y: CGFloat(row) * starSpacing + starSpacing / 2)
            }
        }
        .filter { $0.x < size.width && $0.y < size.height }
    }

    /// The garland pieces, side by side from the leading edge just below `topInset` (the status bar), as many as cover the width.
    static func garland(in size: CGSize, topInset: CGFloat) -> [CGRect] {
        guard size.width > 0, size.height >= topInset + garlandHeight else { return [] }
        let width = garlandHeight * garlandAspectRatio
        let count = Int((size.width / width).rounded(.up))
        return (0..<count).map { CGRect(x: CGFloat($0) * width, y: topInset, width: width, height: garlandHeight) }
    }

    /// An ornament's height; one hangs below the middle of each garland piece.
    static let ornamentHeight: CGFloat = 24
    static let ornamentAspectRatio: Double = 564.0 / 738

    /// The ornaments, one below the middle of each garland piece, cut to the screen (none without a garland, or where the
    /// screen ends before one).
    static func ornaments(in size: CGSize, topInset: CGFloat) -> [CGRect] {
        let width = ornamentHeight * ornamentAspectRatio
        return garland(in: size, topInset: topInset).compactMap { piece in
            let frame = CGRect(x: piece.midX - width / 2, y: piece.maxY, width: width, height: ornamentHeight)
            return frame.maxX <= size.width && frame.maxY <= size.height ? frame : nil
        }
    }

    /// The shortest tree drawn: below it, a screen has neither tree nor gifts.
    static let minTreeHeight: CGFloat = 40

    /// The tree's height: 30 % of the screen, at most `maxTreeHeight`, and small enough for the tree and the gifts to share
    /// 90 % of the width (an iPhone in portrait, a narrow split column).
    static func treeHeight(in size: CGSize) -> CGFloat {
        let fitting = max(size.width, 0) * 0.9 / (treeAspectRatio + giftsWidth(treeHeight: 1))
        return min(max(size.height, 0) * 0.3, maxTreeHeight, fitting)
    }

    /// The tree, standing on `bottomInset` (the home indicator) in the trailing corner; nil when it would be shorter than
    /// `minTreeHeight` or taller than the room above the inset.
    static func tree(in size: CGSize, bottomInset: CGFloat) -> CGRect? {
        let height = treeHeight(in: size)
        let width = height * treeAspectRatio
        guard height >= minTreeHeight, size.height >= height + bottomInset else { return nil }
        return CGRect(x: size.width - width, y: size.height - bottomInset - height, width: width, height: height)
    }

    /// Three gifts in the leading corner, a third of the tree's height and less, standing on `bottomInset`; none without a tree.
    static func gifts(in size: CGSize, bottomInset: CGFloat) -> [CGRect] {
        guard let tree = tree(in: size, bottomInset: bottomInset) else { return [] }
        var x: CGFloat = 0
        return [0.34, 0.26, 0.3].map { share in
            let height = tree.height * share
            let frame = CGRect(x: x, y: tree.maxY - height, width: height * giftAspectRatio, height: height)
            x = frame.maxX
            return frame
        }
    }

    private static func giftsWidth(treeHeight: CGFloat) -> CGFloat { treeHeight * 0.9 * giftAspectRatio }
}
