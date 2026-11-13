import SwiftUI
import UIKit

/// Where the reader shows its composers (#853, operator 2026-11-13; reference: the Messages and Claude apps' input bars). On an
/// iPhone whose reader fills the width, a reply, the edit of one's message and the author menu's MP are a bar docked at the
/// bottom of the reader, on the keyboard: the page above it is the reader's own scroll view, so it scrolls with the keyboard
/// up, and dragging it down pulls the keyboard down with the finger while the bar stays. A sheet below full height could not do
/// that: iOS moves a sheet to its largest detent when the keyboard rises, and with one detent left the page under it inert
/// (device, 2026-11-13). The bar's "Plein écran" fills the reader instead (`ComposerHeight.full`).
///
/// A sheet elsewhere: on an iPad, and on an iPhone in regular width (a Pro Max in landscape, the list beside the reader), where
/// the list column stays live beside a docked bar and choosing another topic there would tear the reader down with the
/// composer in it, mid-send included; a sheet is modal. The lists' composers (a new topic, a new MP) keep their sheet too:
/// their page has no guard against its taps.
enum ComposerPlacement: Equatable {
    /// A bar at the bottom of the reader, on the keyboard.
    case docked
    /// A sheet over the reader.
    case sheet

    /// The reader's composers: docked on an iPhone whose reader is alone in compact width, a sheet otherwise.
    static func reader(isPhone: Bool, horizontalSizeClass: UserInterfaceSizeClass?) -> ComposerPlacement {
        isPhone && horizontalSizeClass == .compact ? .docked : .sheet
    }

    /// The reader's placement on this device at this width.
    @MainActor static func reader(horizontalSizeClass: UserInterfaceSizeClass?) -> ComposerPlacement {
        reader(isPhone: UIDevice.current.userInterfaceIdiom == .phone, horizontalSizeClass: horizontalSizeClass)
    }
}

/// The reader's open docked composer, as its page sees it (#853): at partial height the bar sits on the keyboard over the page's
/// bottom; at full height it covers the whole page.
enum DockedComposer: Equatable {
    case partial
    case full
}

extension EnvironmentValues {
    /// The reader's open docked composer; nil when none is open (or the composer is a sheet).
    @Entry var dockedComposer: DockedComposer?
}

/// The docked composer's height, reported to its presenter (`ComposerHeight`).
struct DockedComposerHeightKey: PreferenceKey {
    static let defaultValue: ComposerHeight? = nil

    static func reduce(value: inout ComposerHeight?, nextValue: () -> ComposerHeight?) {
        value = value ?? nextValue()
    }
}

/// Presents one of the reader's composers (a reply, an edit, the author menu's MP) at its `ComposerPlacement`: docked, the
/// composer is a bottom bar of the reader (`safeAreaInset`, so it rides on the keyboard and the page's safe area ends above
/// it) until it closes, whatever the keyboard does; as a sheet, the system's. Both are always attached and the content is never
/// wrapped in a branch: a change of width while writing (a rotation) moves the composer between them without rebuilding the
/// page. The presenter alone watches the composer's close (once, whichever view shows it, `initial` for a close that landed
/// before), and clears the binding, which removes the bar or dismisses the sheet. The page learns about the bar through
/// `dockedComposer`, set only while this presenter's composer is docked. A move between the bar and a sheet rebuilds the
/// composer's view: its text, draft and history are the model's and stay; the "Aa" bar, the chosen height and an image upload
/// in flight are the view's and start over.
struct ReaderComposerPresenter: ViewModifier {
    @Binding var composer: ReplyComposerModel?
    /// Forces a placement (tests); nil follows the device and the width.
    var placement: ComposerPlacement?
    /// Called once with the composer and the reason, right before it goes away.
    let onClose: (ReplyComposerModel, ReplyComposerModel.CloseReason) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var dockedHeight: ComposerHeight?
    @State private var live = LivePlacement()

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.dockedComposer) { value in
                if let docked = Self.docked(isDocked: isDocked, composerIsOpen: composer != nil, height: dockedHeight) {
                    value = docked
                }
            }
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

    private var isDocked: Bool { (placement ?? .reader(horizontalSizeClass: horizontalSizeClass)) == .docked }

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

/// The reader's docked composer bar (#853): opaque down to the screen's bottom edge (under the home indicator, and under the
/// keyboard as it moves), touches on it never reach the page under it, it reports its height to its presenter, and at full
/// height ("Plein écran", or an iPhone in landscape) the reader's navigation bar is hidden, so the composer has the screen as
/// the full-height sheet had. Nothing for a sheet, which has its own.
struct DockedComposerBar: ViewModifier {
    let isDocked: Bool
    let height: ComposerHeight

    func body(content: Content) -> some View {
        if isDocked {
            content
                .background { Rectangle().fill(.background).ignoresSafeArea() }
                .contentShape(.rect)
                .preference(key: DockedComposerHeightKey.self, value: height)
                .toolbar(height == .full ? .hidden : .automatic, for: .navigationBar)
        } else {
            content
        }
    }
}
