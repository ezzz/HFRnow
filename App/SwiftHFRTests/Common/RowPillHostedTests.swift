@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The highlight of a list row is a pill inset inside the block, not a full-cell background (#803): measured on pixels of a real
/// `List`, so putting `listRowBackground` back at a call site turns these red.
@MainActor
@Suite(.serialized)
struct RowPillHostedTests {
    private func cells(in view: UIView) -> [UIView] {
        if view is UICollectionViewCell || view is UITableViewCell { return [view] }
        return view.subviews.flatMap { cells(in: $0) }
    }

    /// A list of a tinted row (`rowPill`, or for the control the old `listRowBackground`) above a plain one, at a density and
    /// colour scheme, the rows on the density's `rowInsets` as the topic lists have them; returns the window image and the
    /// frames of the two cells in it.
    private func render(
        useListRowBackground: Bool, density: ListDensity = .regular, dark: Bool = false, shortRow: Bool = false
    ) async -> (UIImage, [CGRect])? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return nil }
        let tint = RowTint(tint: .red, weight: 4)
        let list = List {
            if useListRowBackground {
                row("Ligne").listRowInsets(density.rowInsets).listRowBackground(tint)
            } else {
                (shortRow ? AnyView(Text("Ligne")) : AnyView(row("Ligne"))).listRowInsets(density.rowInsets).rowPill(tint)
            }
            row("Simple").listRowInsets(density.rowInsets)
        }
        .listStyle(.insetGrouped)
        .environment(\.listDensity, density)
        let host = UIHostingController(rootView: list)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 400)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var frames: [CGRect] = []
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let found = cells(in: host.view)
            if found.count >= 2 { frames = found.map { $0.convert($0.bounds, to: window) }.sorted { $0.minY < $1.minY }; break }
        }
        guard frames.count >= 2 else { return nil }
        try? await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        // Read again: a late re-layout would move the cells.
        frames = cells(in: host.view).map { $0.convert($0.bounds, to: window) }.sorted { $0.minY < $1.minY }
        guard frames.count >= 2 else { return nil }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return (image, frames)
    }

    private func row(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    /// The pixel's sRGB channels, 0 to 255, red first.
    private func channels(_ image: UIImage, _ point: CGPoint) -> [Int]? {
        guard let source = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let scale = image.scale
        let x = Int(point.x * scale), y = Int(point.y * scale)
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // The 1x1 context shows the image pixel at (x, y); Core Graphics counts rows from the bottom.
            context.draw(source, in: CGRect(x: -x, y: y + 1 - source.height, width: source.width, height: source.height))
            return true
        }
        return drawn ? [Int(bytes[0]), Int(bytes[1]), Int(bytes[2])] : nil
    }

    /// The row's red pill tint: its channels differ clearly (the block and the page behind it are grey or white).
    private func isRed(_ image: UIImage, _ point: CGPoint) -> Bool {
        guard let pixel = channels(image, point) else { return false }
        return (pixel.max() ?? 0) - (pixel.min() ?? 0) > 25
    }

    private func samePixel(_ image: UIImage, _ one: CGPoint, _ other: CGPoint) -> Bool {
        guard let first = channels(image, one), let second = channels(image, other) else { return false }
        return zip(first, second).allSatisfy { abs($0 - $1) <= 2 }
    }

    /// The pill's 4 pt gap at the block edge shows the block's own colour (the plain row's), and the pill begins past it. The
    /// block edge is the cell's own minX: the cell spans the block.
    private func checkGap(density: ListDensity, dark: Bool) async throws {
        let (image, frames) = try #require(await render(useListRowBackground: false, density: density, dark: dark))
        let tinted = frames[0], plain = frames[1]
        let edge = tinted.minX
        let y = tinted.midY, plainY = plain.midY
        #expect(samePixel(image, CGPoint(x: edge + 2, y: y), CGPoint(x: edge + 2, y: plainY)), "the gap is the block's colour")
        #expect(isRed(image, CGPoint(x: edge + 6, y: y)), "the pill starts after the 4 pt gap")
        #expect(!isRed(image, CGPoint(x: edge + 6, y: plainY)))
    }

    @Test("Regular rows: the pill is 4 pt short of the block edge, the block's own colour shows through")
    func pillIsInsetInsideTheBlock() async throws { try await checkGap(density: .regular, dark: false) }

    @Test("Compact rows (#804, inset 7): the 4 pt gap remains")
    func pillIsInsetInCompactRows() async throws { try await checkGap(density: .compact, dark: false) }

    @Test("Dark: the gap keeps the block's colour, no base colour under the pill (#647's device check stays in the PR)")
    func darkGapKeepsTheBlockColour() async throws {
        try await checkGap(density: .regular, dark: true)
        try await checkGap(density: .compact, dark: true)
    }

    @Test("A row with a short title still gets a pill spanning the block, 4 pt short of its trailing edge (#803)")
    func pillSpansAShortRow() async throws {
        for density in [ListDensity.regular, .compact] {
            let (image, frames) = try #require(await render(useListRowBackground: false, density: density, shortRow: true))
            let tinted = frames[0], plain = frames[1]
            #expect(isRed(image, CGPoint(x: tinted.maxX - 6, y: tinted.midY)), "the pill reaches the trailing edge minus the gap")
            #expect(samePixel(image, CGPoint(x: tinted.maxX - 2, y: tinted.midY), CGPoint(x: plain.maxX - 2, y: plain.midY)), "4 pt gap")
        }
    }

    @Test("Control: a listRowBackground tints the row up to the block edge, which the gap test must refuse")
    func listRowBackgroundReachesTheEdge() async throws {
        let (image, frames) = try #require(await render(useListRowBackground: true))
        let edge = frames[0].minX
        #expect(isRed(image, CGPoint(x: edge + 2, y: frames[0].midY)), "the tint fills the row to the block edge")
    }
}
