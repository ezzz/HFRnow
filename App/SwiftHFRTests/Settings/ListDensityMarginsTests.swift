import HFRModels
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

@MainActor
@Observable
private final class DensityBox {
    var density = ListDensity.regular
    var tokens: Set<UUID> = []
    /// Window x of the content of the views that report it, by name.
    var xs: [String: CGFloat] = [:]
}

private extension View {
    func reportX(_ name: String, to box: DensityBox) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { box.xs[name] = $0 }
    }
}

/// A section with a header and a row, as the app builds them.
private struct SectionProbe: View {
    let box: DensityBox

    var body: some View {
        List {
            Section {
                Text("Ligne").reportX("row", to: box).densityRowMargin()
            } header: {
                Text("En-tête").reportX("header", to: box).densityHeaderMargin()
            }
        }
        .listStyle(.insetGrouped)
        .densityListMargins()
        .environment(\.listDensity, box.density)
    }
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
        #expect(ListDensity.regular.rowSideInset == nil)
    }

    @Test("Compact sets a 10 pt outer margin and a 7 pt inner one")
    func compactMargins() {
        #expect(ListDensity.compact.outerMargin == 10)
        #expect(ListDensity.compact.rowInsets.leading == 7)
        #expect(ListDensity.compact.rowInsets.trailing == 7)
        #expect(ListDensity.compact.rowSideInset == 7)
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

    /// Offsets from the card's left edge of the header and a row, in a window of the given size class.
    private func offsets(_ density: ListDensity, regularClass: Bool) async -> [String: CGFloat] {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return [:]
        }
        let box = DensityBox()
        box.density = density
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: SectionProbe(box: box))
        host.traitOverrides.horizontalSizeClass = regularClass ? .regular : .compact
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if box.xs.count == 2 { break }
        }
        let card = Self.collectionView(in: window)?.visibleCells.map(\.frame.minX).min() ?? 0
        return box.xs.mapValues { $0 - card }
    }

    @Test("In compact, headers and rows sit 7 pt from the card, in both size classes", arguments: [false, true])
    func compactTextSitsOnTheInnerMargin(regularClass: Bool) async {
        let found = await offsets(.compact, regularClass: regularClass)
        #expect(found["header"] == 7, "\(found)")
        #expect(found["row"] == 7, "\(found)")
    }

    @Test("In regular, headers and rows keep the system layout, aligned with each other", arguments: [false, true])
    func regularHeadersAlignWithRows(regularClass: Bool) async {
        let found = await offsets(.regular, regularClass: regularClass)
        #expect(found["header"] != nil && found["header"] == found["row"], "\(found)")
    }

    private func searchRowTextInset(_ density: ListDensity) async -> CGFloat? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return nil
        }
        let topic = TopicSummary(
            topicID: TopicID(category: .forum(13), topic: 1), title: "MMMM", path: "/r", starterOrInterlocutors: "", readState: .read
        )
        let list = List { SearchResultRow(topic: topic) {} }.listStyle(.insetGrouped).densityListMargins()
            .environment(\.listDensity, density)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = UIHostingController(rootView: list)
        window.isHidden = false
        defer { window.isHidden = true }
        try? await Task.sleep(for: .seconds(1))
        window.layoutIfNeeded()
        guard let cell = Self.collectionView(in: window)?.visibleCells.first else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let data = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data), let cg = image.cgImage else { return nil }
        let rect = cell.convert(cell.bounds, to: window)
        let rowBytes = cg.bytesPerRow, pixel = cg.bitsPerPixel / 8
        // The first column from the card's left edge that differs from the card's background: the text of the row.
        let midY = Int(rect.midY)
        let background = (0..<3).map { Int(bytes[midY * rowBytes + (Int(rect.maxX) - 6) * pixel + $0]) }
        for x in Int(rect.minX) + 3..<Int(rect.midX) {
            for y in midY - 4..<midY + 4 {
                let differs = (0..<3).contains { abs(Int(bytes[y * rowBytes + x * pixel + $0]) - background[$0]) > 60 }
                if differs { return CGFloat(x) - rect.minX }
            }
        }
        return nil
    }

    @Test("In compact, a search result's text sits near 7 pt from the card, 9 pt closer than in regular")
    func searchResultsFollowTheDensity() async {
        let regular = await searchRowTextInset(.regular)
        let compact = await searchRowTextInset(.compact)
        guard let regular, let compact else {
            Issue.record("no ink found: regular \(String(describing: regular)), compact \(String(describing: compact))")
            return
        }
        #expect(abs((regular - compact) - 9) <= 1, "regular \(regular), compact \(compact)")
        #expect(compact <= 9, "compact \(compact)")
    }
}
