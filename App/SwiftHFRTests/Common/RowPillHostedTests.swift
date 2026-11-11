@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The highlight of a list row is a pill inset inside the block, not a full-cell background (#803): measured on pixels of a real
/// `List`, so putting `listRowBackground` back at a call site turns these red.
@MainActor
@Suite(.serialized)
struct RowPillHostedTests {
    private func cell(in view: UIView) -> UIView? {
        if view is UICollectionViewCell || view is UITableViewCell { return view }
        return view.subviews.lazy.compactMap { cell(in: $0) }.first
    }

    /// A one-row list drawn with `rowPill` (or, for the control, the old `listRowBackground`); returns the window image and the
    /// cell's frame in it.
    private func render(useListRowBackground: Bool) async -> (UIImage, CGRect)? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return nil }
        let tint = RowTint(tint: .red, weight: 4)
        let list = List {
            if useListRowBackground {
                Text("Ligne").frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).listRowBackground(tint)
            } else {
                Text("Ligne").frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).rowPill(tint)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.listDensity, .regular)
        let host = UIHostingController(rootView: list)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 400)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var frame: CGRect?
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if let found = cell(in: host.view) { frame = found.convert(found.bounds, to: window); break }
        }
        guard let frame else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return (image, frame)
    }

    /// The pixel's sRGB channels, 0 to 255, red first.
    private func channels(_ image: UIImage, _ point: CGPoint) -> [Int]? {
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let scale = image.scale
        let x = Int(point.x * scale), y = Int(point.y * scale)
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // The 1x1 context shows the image pixel at (x, y); Core Graphics counts rows from the bottom.
            context.draw(cg, in: CGRect(x: -x, y: y + 1 - cg.height, width: cg.width, height: cg.height))
            return true
        }
        return drawn ? [Int(bytes[0]), Int(bytes[1]), Int(bytes[2])] : nil
    }

    /// The row's red pill tint: its channels differ clearly (the block and the page behind it are grey or white).
    private func isRed(_ image: UIImage, _ point: CGPoint) -> Bool {
        guard let pixel = channels(image, point) else { return false }
        return (pixel.max() ?? 0) - (pixel.min() ?? 0) > 25
    }

    /// A y inside the red row: 10 pt below the first red pixel down the middle of the window.
    private func rowY(_ image: UIImage) -> CGFloat? {
        stride(from: CGFloat(0), to: image.size.height, by: 1).first { isRed(image, CGPoint(x: image.size.width / 2, y: $0)) }
            .map { $0 + 10 }
    }

    /// The left edge of the block: the first white pixel along the row's middle (the page behind it is grey).
    private func blockEdge(_ image: UIImage, y: CGFloat) -> CGFloat? {
        stride(from: CGFloat(0), to: image.size.width / 2, by: 0.5).first { x in
            channels(image, CGPoint(x: x, y: y)).map { $0.min() ?? 0 > 250 } ?? false
        }
    }

    @Test("The pill sits inside the block and 4 pt short of its edge; the block's own edge shows through")
    func pillIsInsetInsideTheBlock() async throws {
        let (image, _) = try #require(await render(useListRowBackground: false))
        let y = try #require(rowY(image))
        let edge = try #require(blockEdge(image, y: y))
        #expect(!isRed(image, CGPoint(x: edge + 1.5, y: y)), "the gap at the block edge stays the block's")
        #expect(isRed(image, CGPoint(x: edge + 8, y: y)), "the pill starts inside the gap")
    }

    @Test("Control: a listRowBackground tints the row up to the block edge, which the pill test must refuse")
    func listRowBackgroundReachesTheEdge() async throws {
        let (image, _) = try #require(await render(useListRowBackground: true))
        let y = try #require(rowY(image))
        #expect(blockEdge(image, y: y) == nil, "no plain block shows left of the tint: it fills the row to the block edge")
    }
}
