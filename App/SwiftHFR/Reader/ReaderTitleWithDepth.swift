import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (`toolbarStackIndicatorView`, `toolbarTitleView`) @ 87fe0d1c (`3476-3488`; `3410-3440`
// @ 2fe43da3, `602b900e`). Differences: the tint is the app's accent, not legacy's palette tint; the loading spinner of legacy's title
// stays in the reader's own state overlay; the "back to root" button legacy dropped at `602b900e` is not ported (#682).
/// The title of a reader a followed link pushed: a capsule with the stack depth, then the topic title.
struct ReaderTitleWithDepth: View {
    let depth: Int
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            ReaderStackDepthCapsule(depth: depth)
            Text(title).font(.caption2).fontWeight(.bold).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// The small capsule « ‹ N » on the action tint, shown from depth 1.
struct ReaderStackDepthCapsule: View {
    let depth: Int

    /// What VoiceOver says for `depth`; nil when no capsule shows (legacy `"\(navigationDepth) affichage de messages empilé"`).
    static func accessibilityLabel(depth: Int) -> String? {
        depth > 0 ? "\(depth) affichage de messages empilé" : nil
    }

    var body: some View {
        if let label = Self.accessibilityLabel(depth: depth) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.backward").font(.system(size: 7, weight: .bold))
                Text("\(depth)").font(.system(size: 9, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minHeight: 14)
            .background(Color.accentColor, in: Capsule())
            .accessibilityLabel(label)
        }
    }
}
