import SwiftUI

/// Presents one of the reader's composers (a reply, an edit, the author menu's MP) at its `ComposerPlacement`. Docked (the
/// modern composer only, #904), the composer is a bottom bar of the reader (`safeAreaInset`, so it rides on the keyboard and
/// the page's safe area ends above it) until it closes, whatever the keyboard does; as a sheet, the system's. Both are always
/// attached and the content is never wrapped in a branch: a change of width while writing (a rotation) moves the composer
/// between them without rebuilding the page. The presenter alone watches the composer's close (once, whichever view shows it,
/// `initial` for a close that landed before), and clears the binding, which removes the bar or dismisses the sheet. The page
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
            .onPreferenceChange(DockedComposerHeightKey.self) { dockedHeight = $0 }
            .animation(.snappy, value: composer?.id)
            .sheet(item: sheetComposer) { model in ReplyComposerView(model: model) }
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

    private var isDocked: Bool {
        (placement ?? .reader(horizontalSizeClass: horizontalSizeClass, experimental: experimental)) == .docked
    }

    /// The composer while it is a sheet. A sheet dismissed because the composer became docked (a rotation) keeps it: SwiftUI
    /// calls the setter of the binding it was presented with, whose own `isDocked` is from before the rotation, so it reads the
    /// placement of the latest update.
    private var sheetComposer: Binding<ReplyComposerModel?> {
        live.isDocked = isDocked // every update builds this binding: the latest placement
        return Binding(get: { isDocked ? nil : composer }, set: { [live] in if $0 == nil, !live.isDocked { composer = nil } })
    }

    /// The placement of the presenter's latest update, for a setter SwiftUI calls on an older binding.
    @MainActor
    private final class LivePlacement {
        var isDocked = false
    }
}
