import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

@MainActor
@Observable
private final class DensityBox {
    var density = ListDensity.regular
    var tokens: Set<UUID> = []
}

private struct StateProbeRow: View {
    let box: DensityBox
    @State private var token = UUID()

    var body: some View {
        Text("Ligne").onAppear { box.tokens.insert(token) }
    }
}

private struct ProbeList: View {
    let box: DensityBox
    let margins: Bool

    var body: some View {
        let list = List(0..<3, id: \.self) { _ in StateProbeRow(box: box) }.listStyle(.insetGrouped)
        Group {
            if margins { list.densityListMargins() } else { list }
        }
        .environment(\.listDensity, box.density)
    }
}

/// The side margins of the inset-grouped lists follow the density (#799).
@MainActor
@Suite(.serialized)
struct ListDensityMarginsTests {
    @Test("Regular keeps the system outer margin and the legacy 16 pt inner one")
    func regularMargins() {
        #expect(ListDensity.regular.outerMargin == nil)
        #expect(ListDensity.regular.rowInsets.leading == 16)
        #expect(ListDensity.regular.rowInsets.trailing == 16)
        #expect(ListDensity.regular.innerMarginShift == 0)
    }

    @Test("Compact sets a 10 pt outer margin and a 7 pt inner one")
    func compactMargins() {
        #expect(ListDensity.compact.outerMargin == 10)
        #expect(ListDensity.compact.rowInsets.leading == 7)
        #expect(ListDensity.compact.rowInsets.trailing == 7)
        #expect(ListDensity.compact.innerMarginShift == -9)
    }

    private func firstCellMinX(margins: Bool, density: ListDensity) async -> CGFloat? {
        let box = DensityBox()
        box.density = density
        return await withHost(box, margins: margins) { collection in collection.visibleCells.map(\.frame.minX).min() }
    }

    private func withHost<T>(_ box: DensityBox, margins: Bool, _ body: (UICollectionView) -> T?) async -> T? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: ProbeList(box: box, margins: margins))
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if let collection = Self.collectionView(in: window), !collection.visibleCells.isEmpty { break }
        }
        guard let collection = Self.collectionView(in: window) else { return nil }
        return body(collection)
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
    }

    @Test("The modifier moves the cards to the outer margin in compact and leaves regular on the system layout")
    func cardsFollowTheDensity() async {
        let system = await firstCellMinX(margins: false, density: .regular)
        let regular = await firstCellMinX(margins: true, density: .regular)
        let compact = await firstCellMinX(margins: true, density: .compact)
        #expect(system != nil && system == regular, "system \(String(describing: system)), regular \(String(describing: regular))")
        #expect(compact == 10, "compact \(String(describing: compact))")
    }

    @Test("A density change keeps the list's row state")
    func toggleKeepsState() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            Issue.record("no window scene")
            return
        }
        let box = DensityBox()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: ProbeList(box: box, margins: true))
        window.isHidden = false
        defer { window.isHidden = true }
        try? await Task.sleep(for: .seconds(1))
        let before = box.tokens.count
        box.density = .compact
        try? await Task.sleep(for: .seconds(1))
        window.layoutIfNeeded()
        #expect(before == 3, "rows before \(before)")
        // A row's @State token is created once per row: a rebuilt list would add three more.
        #expect(box.tokens.count == before, "tokens after the toggle \(box.tokens.count)")
    }
}
