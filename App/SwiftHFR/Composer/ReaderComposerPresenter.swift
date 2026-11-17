import SwiftUI

/// Presents one of the reader's composers (a reply, an edit, the author menu's MP) at its `ComposerPlacement`. Docked (the
/// modern composer only, #904), the composer is a bottom bar of the reader (`safeAreaInset`, so it rides on the keyboard and
/// the page's safe area ends above it) until it closes, whatever the keyboard does; as a sheet, the system's; as legacy's
/// full-screen cover (an iPhone with the option off, #855), the system's `fullScreenCover`. All three are always attached and
/// the content is never wrapped in a branch: a change of width while writing (a rotation) moves the composer between the bar
/// and a sheet without rebuilding the page. The presenter alone watches the composer's close (once, whichever view shows it,
/// `initial` for a close that landed before), and clears the binding, which removes the bar or dismisses the sheet or cover. The page
/// learns about the bar through `dockedComposer`, set only while this presenter's composer is docked. A move between the bar
/// and a sheet rebuilds the composer's view: its text, draft and history are the model's and stay; the "Aa" bar, the chosen
/// height and an image upload in flight are the view's and start over.
struct ReaderComposerPresenter: ViewModifier {
    @Binding var composer: ReplyComposerModel?
    /// Forces a placement (tests); nil follows the device, the width and « Composer moderne ».
    var placement: ComposerPlacement?
    /// Called once with the composer and the reason, right before it goes away.
    let onClose: (ReplyComposerModel, ReplyComposerModel.CloseReason) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Réglages › Expérimental (#903); nil keeps each option's default (hosted tests, previews).
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?
    @State private var dockedHeight: ComposerHeight?
    @State private var live = LivePlacement()

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.dockedComposer) { value in
                if let docked = Self.docked(isDocked: isDocked, composerIsOpen: composer != nil, height: dockedHeight) {
                    value = docked
                }
            }
            // EXPERIMENTAL(modernComposer, #904): replaces the composer sheet, on an iPhone in compact width with the option on,
            // by a bar docked on the keyboard (#853); with the option off `isDocked` is false and only the sheet below shows.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isDocked, let model = composer {
                    ReplyComposerView(model: model, placement: .docked)
                        .id(model.id)
                        .transition(.move(edge: .bottom))
                }
            }
            // The action is `@Sendable` (iOS 18.2 SDK on): it writes through the state's binding, never the main-actor view.
            .onPreferenceChange(DockedComposerHeightKey.self) { [height = $dockedHeight] in height.wrappedValue = $0 }
            // The bar's slide only: a sheet animates itself, and the reader under it must not animate what changes with it.
            .animation(isDocked ? .snappy : nil, value: composer?.id)
            .sheet(item: presented(.sheet)) { model in ReplyComposerView(model: model) }
            // Legacy's composer (`MessagesView.swift:5429-5443`, `coverVerticalFullScreen` @ 87fe0d1c, #855).
            .fullScreenCover(item: presented(.cover)) { model in ReplyComposerView(model: model, placement: .cover) }
            .onChange(of: composer?.closeReason, initial: true) { _, reason in
                guard let reason, let model = composer else { return }
                onClose(model, reason)
                composer = nil
            }
    }

    /// What the page sees of this presenter's composer: docked and open, its height (partial until the composer says).
    static func docked(isDocked: Bool, composerIsOpen: Bool, height: ComposerHeight?) -> DockedComposer? {
        guard isDocked, composerIsOpen else { return nil }
        return height == .full ? .full : .partial
    }

    private var current: ComposerPlacement {
        placement ?? .reader(horizontalSizeClass: horizontalSizeClass, experimental: experimental)
    }

    private var isDocked: Bool { current == .docked }

    /// The composer while it is shown as `presentation` (a sheet or the cover). One dismissed because the composer moved
    /// elsewhere (a rotation) keeps it: SwiftUI calls the setter of the binding it was presented with, whose own placement is
    /// from before the move, so it reads the placement of the latest update.
    private func presented(_ presentation: ComposerPlacement) -> Binding<ReplyComposerModel?> {
        let current = current
        live.placement = current // every update builds this binding: the latest placement
        return Binding(
            get: { current == presentation ? composer : nil },
            set: { [live] in if $0 == nil, live.placement == presentation { composer = nil } }
        )
    }

    /// The placement of the presenter's latest update, for a setter SwiftUI calls on an older binding.
    @MainActor
    private final class LivePlacement {
        var placement = ComposerPlacement.sheet
    }
}
