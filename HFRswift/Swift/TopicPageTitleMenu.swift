//
//  TopicPageTitleMenu.swift
//  HFRswift
//
//  Topic title in the navigation bar: tapping it opens a menu to jump straight to a page.
//

import SwiftUI

struct TopicPageTitleMenu<Label: View>: View {
    let currentPage: Int
    let maxPage: Int
    let onSelectPage: (Int) -> Void
    let onPagePicker: () -> Void
    @ViewBuilder let label: () -> Label

    /// Up to this many pages, every page is listed directly; beyond, by blocks of `blockSize`.
    private static var flatListLimit: Int { 30 }
    private static var blockSize: Int { 50 }

    private var nearbyPages: ClosedRange<Int> {
        max(1, currentPage - 5)...min(maxPage, currentPage + 5)
    }

    private var blocks: [ClosedRange<Int>] {
        stride(from: 1, through: maxPage, by: Self.blockSize).map { start in
            start...min(start + Self.blockSize - 1, maxPage)
        }
    }

    var body: some View {
        Menu {
            Button("Aller à la page…", systemImage: "number", action: onPagePicker)
            if maxPage <= Self.flatListLimit {
                Section {
                    TopicPageMenuButtons(pages: 1...maxPage, currentPage: currentPage, onSelectPage: onSelectPage)
                }
            } else {
                Section {
                    Button("Première page", systemImage: "chevron.left.to.line") { onSelectPage(1) }
                        .disabled(currentPage == 1)
                    Button("Dernière page (\(maxPage.formatted()))", systemImage: "chevron.right.to.line") {
                        onSelectPage(maxPage)
                    }
                    .disabled(currentPage == maxPage)
                }
                Section("Autour de la page \(currentPage.formatted())") {
                    TopicPageMenuButtons(pages: nearbyPages, currentPage: currentPage, onSelectPage: onSelectPage)
                }
                Section("Toutes les pages") {
                    ForEach(blocks, id: \.lowerBound) { block in
                        Menu("Pages \(block.lowerBound.formatted()) – \(block.upperBound.formatted())") {
                            TopicPageMenuButtons(pages: block, currentPage: currentPage, onSelectPage: onSelectPage)
                        }
                    }
                }
            }
        } label: {
            label()
        }
        .accessibilityLabel("Page \(currentPage) sur \(maxPage)")
        .accessibilityHint("Choisir une page")
    }
}

private struct TopicPageMenuButtons: View {
    let pages: ClosedRange<Int>
    let currentPage: Int
    let onSelectPage: (Int) -> Void

    var body: some View {
        ForEach(pages.lowerBound..<(pages.upperBound + 1), id: \.self) { page in
            if page == currentPage {
                Button("Page \(page.formatted())", systemImage: "checkmark") {}
                    .disabled(true)
            } else {
                Button("Page \(page.formatted())") { onSelectPage(page) }
            }
        }
    }
}
