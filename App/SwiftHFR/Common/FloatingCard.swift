import SwiftUI

/// The app's one floating card (#693): the 12-pt rounded surface behind a banner or a progress panel. Every card goes through
/// `floatingCard(_:)`, so the shape and the two surfaces are defined here only (`FloatingCardSourceTests` keeps it so).
enum FloatingCard {
    /// The card's shape; the one place the app spells it (the issue's `git grep "RoundedRectangle(cornerRadius: 12)"` finds only it).
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12) }

    /// What the card is made of.
    enum Surface {
        /// A material: the card sits in a list's content layer, where the HIG puts no glass (GAP-222).
        case material
        /// Liquid Glass: the card floats over a page that runs under it (LOT-185, LOT-186).
        case glass
    }
}

extension View {
    /// Puts the view on the floating card; padding stays with the caller (a banner pads 12, a progress panel the default).
    @ViewBuilder
    func floatingCard(_ surface: FloatingCard.Surface = .material) -> some View {
        switch surface {
        case .material: background(.regularMaterial, in: FloatingCard.shape)
        case .glass: glassEffect(.regular, in: FloatingCard.shape)
        }
    }
}

/// HFR's confirmation of a write (a new topic, a private message, a reply), on a floating card above the content, with a close button.
struct ConfirmationBanner: View {
    let text: String
    var surface: FloatingCard.Surface = .material
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(text).scaledFont(.subheadline)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(.rect) // 44 pt target
            }
            .accessibilityLabel("Masquer")
        }
        .padding(12)
        .floatingCard(surface)
        .padding(.horizontal)
    }
}
