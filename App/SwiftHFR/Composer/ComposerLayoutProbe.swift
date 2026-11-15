import SwiftUI

/// Where the composer's parts are laid out, for hosted-window layout tests (#854): nil in the app, so no part reports
/// anything. A test sets it in the environment and reads the frames (window coordinates) and the docked card's layout.
struct ComposerLayoutProbe {
    enum Part: Hashable {
        case title, close, drafts, send, card, editor, controls
    }

    let frame: @MainActor (Part, CGRect) -> Void
    let layout: @MainActor (ComposerCardLayout) -> Void
}

extension EnvironmentValues {
    @Entry var composerLayoutProbe: ComposerLayoutProbe?
}

extension View {
    /// Reports this part's frame to the environment's probe, when a test set one.
    func composerProbe(_ part: ComposerLayoutProbe.Part) -> some View {
        modifier(ComposerProbeModifier(part: part))
    }
}

private struct ComposerProbeModifier: ViewModifier {
    let part: ComposerLayoutProbe.Part
    @Environment(\.composerLayoutProbe) private var probe

    func body(content: Content) -> some View {
        if let probe {
            content.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.frame(part, $0) }
        } else {
            content
        }
    }
}
