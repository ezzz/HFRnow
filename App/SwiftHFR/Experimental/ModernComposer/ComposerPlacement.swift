import SwiftUI
import UIKit

/// Where the reader shows its composers (#853, operator 2026-11-13; reference: the Messages and Claude apps' input bars). On an
/// iPhone whose reader fills the width, a reply, the edit of one's message and the author menu's MP are a bar docked at the
/// bottom of the reader, on the keyboard: the page above it is the reader's own scroll view, so it scrolls with the keyboard
/// up, and dragging it down pulls the keyboard down with the finger while the bar stays. A sheet below full height could not do
/// that: iOS moves a sheet to its largest detent when the keyboard rises, and with one detent left the page under it inert
/// (device, 2026-11-13). The bar's "Plein écran" fills the reader instead (`ComposerHeight.full`). The author menu's MP,
/// new content, opens at that full height with no toggle (#1137): it covers the reader's page, not scrollable behind it.
///
/// Part of the modern composer (#904, Réglages › Expérimental › « Composer moderne », #903). With the option off (the default
/// since #855) an iPhone's reader composers are legacy's full-screen cover (`MessagesView.swift:5429-5443`,
/// `coverVerticalFullScreen` @ 87fe0d1c), at any width.
///
/// A sheet elsewhere: on an iPad, and, with the option on, on an iPhone in regular width (a foldable's inner screen, the list
/// beside the reader; the Plus tab's readers on a Pro Max in landscape; the other tabs read at compact width there since #431),
/// where the list column stays live beside a docked bar and choosing another topic there would tear the reader down with the
/// composer in it, mid-send included; a sheet is modal. The lists' composers (a new topic, a new MP) keep their sheet too, as
/// legacy's new topic (`MainWindow.swift:905-921` @ 87fe0d1c): their page has no guard against its taps.
enum ComposerPlacement: Equatable {
    /// A bar at the bottom of the reader, on the keyboard.
    case docked
    /// A sheet over the reader.
    case sheet
    /// Legacy's full-screen cover over the reader (#855).
    case cover

    /// The reader's composers: docked on an iPhone whose reader is alone in compact width with the modern composer on
    /// (`modernComposer`, the switch's value); with it off, legacy's cover on an iPhone; a sheet otherwise.
    static func reader(isPhone: Bool, horizontalSizeClass: UserInterfaceSizeClass?, modernComposer: Bool) -> ComposerPlacement {
        // EXPERIMENTAL(modernComposer, #904): replaces legacy's full-screen cover (an iPhone) by the docked bar.
        if ModernComposer.isActive(isPhone: isPhone, isOn: modernComposer) {
            return horizontalSizeClass == .compact ? .docked : .sheet
        }
        return isPhone ? .cover : .sheet
    }

    /// The reader's placement on this device at this width, with the switch of `experimental` (its default without one).
    @MainActor static func reader(
        horizontalSizeClass: UserInterfaceSizeClass?, experimental: ExperimentalSettings?
    ) -> ComposerPlacement {
        reader(
            isPhone: UIDevice.current.userInterfaceIdiom == .phone, horizontalSizeClass: horizontalSizeClass,
            modernComposer: ExperimentalSettings.isOn(.modernComposer, in: experimental)
        )
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

/// The reader's docked composer bar (#853): opaque from its text card down to the screen's bottom edge (under the home
/// indicator, and under the keyboard as it moves), touches on it never reach the page under it, it reports its height to its
/// presenter, and at full height ("Plein écran", or an iPhone in landscape) the reader's navigation bar is hidden, so the
/// composer has the screen as the full-height sheet had. Nothing for a sheet, which has its own.
///
/// At partial height the floating buttons' row has no fill (#972, operator 2026-11-16: no strip over the page): the page shows
/// around the buttons, whose capsules carry their own (`FloatingButtonPalette`); a banner or the recipient and subject fields
/// under the row stay on the fill. A tap between the buttons still stops at the bar, as the page's taps do while writing. At
/// full height the bar covers the page and is filled from its top.
struct DockedComposerBar: ViewModifier {
    let isDocked: Bool
    let height: ComposerHeight
    /// The floating buttons' row as laid out (`ComposerButtonsHeightKey`), 0 before it is measured.
    @State private var buttonsHeight: CGFloat = 0

    /// Where the bar's fill starts, from its top: under the buttons' row at partial height, the top at full height.
    nonisolated static func fillStart(height: ComposerHeight, buttonsHeight: CGFloat) -> CGFloat {
        height == .partial ? max(0, buttonsHeight) : 0
    }

    func body(content: Content) -> some View {
        if isDocked {
            content
                // The action is `@Sendable` (iOS 18.2 SDK on): it writes through the state's binding.
                .onPreferenceChange(ComposerButtonsHeightKey.self) { [buttons = $buttonsHeight] in buttons.wrappedValue = $0 }
                .background(alignment: .top) {
                    Rectangle().fill(.background)
                        .composerProbe(.fill)
                        .padding(.top, Self.fillStart(height: height, buttonsHeight: buttonsHeight))
                        .ignoresSafeArea()
                }
                .contentShape(.rect)
                .preference(key: DockedComposerHeightKey.self, value: height)
                .toolbar(height == .full ? .hidden : .automatic, for: .navigationBar)
        } else {
            content
        }
    }
}

/// The modern composer's floating buttons' row height, reported to the docked bar (#972) so its fill starts under the row.
struct ComposerButtonsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
