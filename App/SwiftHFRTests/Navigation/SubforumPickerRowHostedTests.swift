import HFRModels
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// Where SwiftUI drew a hosted view, in window coordinates.
@MainActor
private final class FrameBox { var frame: CGRect = .zero }

/// One row hosted in an inset-grouped list 402 pt wide at a Dynamic Type size (environment and trait both set, as the system sets
/// both: the list sizes its cells from the trait, the row from the environment), and the same row laid out alone (#1439).
@MainActor
enum HostedListRow {
    /// The row content's frame and the frame of the cell that holds it, both in window coordinates.
    static func frames(of row: some View, at size: DynamicTypeSize) async throws -> (content: CGRect, cell: CGRect) {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let box = FrameBox()
        let measured = row.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { box.frame = $0 })
        let list = List { Section { measured; Text("Tous") } }
            .listStyle(.insetGrouped)
            .environment(\.dynamicTypeSize, size)
        let host = UIHostingController(rootView: list)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(size)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var cell = CGRect.zero
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            guard box.frame != .zero, let collection = collectionView(in: host.view) else { continue }
            let cells = collection.visibleCells.map { $0.convert($0.bounds, to: window) }
            if let holder = cells.first(where: { $0.contains(CGPoint(x: box.frame.midX, y: box.frame.midY)) }) {
                cell = holder
                break
            }
        }
        return (box.frame, cell)
    }

    /// The height `row` takes laid out alone, `width` points wide, at its ideal height.
    static func idealHeight(of row: some View, width: CGFloat, at size: DynamicTypeSize) async throws -> CGFloat {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let box = FrameBox()
        let view = row
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { box.frame = $0 })
            .environment(\.dynamicTypeSize, size)
            .frame(maxHeight: .infinity, alignment: .top)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 2_000)
        window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(size)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<60 where box.frame == .zero {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        return box.frame.height
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
    }
}

/// #1439, item 3: at Accessibilité XL the « Sous-forum » label of a category's list was drawn above its row, clipped by the top
/// edge of the card, and the menu's two-line title was cut. Hosted in a list, the row lies inside its cell and is as tall as it is
/// alone at the same width (nothing in it is squeezed).
@MainActor
@Suite(.serialized)
struct SubforumPickerRowHostedTests {
    private let section = ForumSection(
        id: "hardware", title: "Hardware",
        rows: [
            ForumRow(id: "hardware", title: "Tous les sujets", source: .forum(.forum(1), title: "Hardware")),
            ForumRow(id: "/sub", title: "Carte mère", source: .subforum(path: "/sub", title: "Carte mère"))
        ],
        categoryID: .forum(1)
    )

    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func theLabelAndTheMenuLieInsideTheirRow(size: DynamicTypeSize) async throws {
        let row = SubforumPickerRow(section: section, selection: .constant(section.source))
        let seen = try await HostedListRow.frames(of: row, at: size)
        #expect(seen.cell != .zero, "no cell holds the row: \(seen.content)")
        #expect(seen.content.minY >= seen.cell.minY - 0.5, "content \(seen.content) starts above its cell \(seen.cell)")
        #expect(seen.content.maxY <= seen.cell.maxY + 0.5, "content \(seen.content) ends below its cell \(seen.cell)")
        let alone = try await HostedListRow.idealHeight(of: row, width: seen.content.width, at: size)
        #expect(seen.content.height >= alone - 0.5, "in the list \(seen.content.height) pt, alone \(alone) pt: squeezed")
    }

    @Test func theMenuShowsTheChosenSubforum() {
        let sub = TopicSource.subforum(path: "/sub", title: "Carte mère")
        #expect(SubforumPickerRow(section: section, selection: .constant(section.source)).selectedTitle == "Tous les sous-forums")
        #expect(SubforumPickerRow(section: section, selection: .constant(sub)).selectedTitle == "Carte mère")
    }
}
