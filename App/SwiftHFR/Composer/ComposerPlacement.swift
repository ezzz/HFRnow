import SwiftUI
import UIKit

/// Where the reader shows its composers (#853, operator 2026-11-13; reference: the Messages and Claude apps' input bars). On an
/// iPhone a reply, the edit of one's message and the author menu's MP are a bar docked at the bottom of the reader, on the
/// keyboard: the page above it is the reader's own scroll view, so it scrolls with the keyboard up, and dragging it down pulls
/// the keyboard down with the finger while the bar stays. A sheet below full height could not do that: iOS moves a sheet to its
/// largest detent when the keyboard rises, and with one detent left the page under it inert (device, 2026-11-13). The bar's
/// "Plein écran" fills the reader instead (`ComposerHeight.full`). An iPad keeps the sheet; the lists' composers (a new topic,
/// a new MP) keep their sheet too, their page has no guard against its taps.
enum ComposerPlacement: Equatable {
    /// A bar at the bottom of the reader, on the keyboard.
    case docked
    /// A sheet over the reader.
    case sheet

    /// The reader's composers: docked on an iPhone, a sheet on an iPad.
    static func reader(isPhone: Bool) -> ComposerPlacement {
        isPhone ? .docked : .sheet
    }

    /// The page follows the keyboard, its bottom inset and the interactive pull-down, only while a docked composer is open: the
    /// bar sits on the keyboard, so the page's last lines are above both; with a sheet, or no composer, the keyboard (the "Aller
    /// à la page" prompt) never moves the page.
    static func pageFollowsKeyboard(placement: ComposerPlacement, composerIsOpen: Bool) -> Bool {
        placement == .docked && composerIsOpen
    }

    /// The reader's placement on this device.
    @MainActor static var readerOnThisDevice: ComposerPlacement {
        reader(isPhone: UIDevice.current.userInterfaceIdiom == .phone)
    }
}

/// Presents one of the reader's composers (a reply, an edit, the author menu's MP) at its `ComposerPlacement`: docked, the
/// composer is a bottom bar of the reader (`safeAreaInset`, so it rides on the keyboard and the page's safe area ends above
/// it) until it closes, whatever the keyboard does; as a sheet, the system's.
struct ReaderComposerPresenter: ViewModifier {
    @Binding var composer: ReplyComposerModel?
    var placement = ComposerPlacement.readerOnThisDevice
    /// Called once with the composer and the reason, right before it goes away.
    let onClose: (ReplyComposerModel, ReplyComposerModel.CloseReason) -> Void

    func body(content: Content) -> some View {
        switch placement {
        case .docked:
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if let model = composer {
                    ReplyComposerView(model: model, placement: .docked) { reason in
                        onClose(model, reason)
                        composer = nil
                    }
                    .id(model.id)
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.snappy, value: composer?.id)
        case .sheet:
            content.sheet(item: $composer) { model in
                ReplyComposerView(model: model) { onClose(model, $0) }
            }
        }
    }
}

/// The reader's docked composer bar (#853): opaque down to the screen's bottom edge (under the home indicator, and under the
/// keyboard as it moves), and at full height ("Plein écran", or an iPhone in landscape) the reader's navigation bar hidden, so
/// the composer has the screen as the full-height sheet had. Nothing for a sheet, which has its own.
struct DockedComposerBar: ViewModifier {
    let isDocked: Bool
    /// The composer is at full height (`ComposerHeight.full`).
    let fills: Bool

    func body(content: Content) -> some View {
        if isDocked {
            content
                .background { Rectangle().fill(.background).ignoresSafeArea() }
                .toolbar(fills ? .hidden : .automatic, for: .navigationBar)
        } else {
            content
        }
    }
}
