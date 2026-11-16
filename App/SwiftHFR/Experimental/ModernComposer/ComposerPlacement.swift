import SwiftUI
import UIKit

/// Where the reader shows its composers (#853, operator 2026-11-13; reference: the Messages and Claude apps' input bars). On an
/// iPhone whose reader fills the width, a reply, the edit of one's message and the author menu's MP are a bar docked at the
/// bottom of the reader, on the keyboard: the page above it is the reader's own scroll view, so it scrolls with the keyboard
/// up, and dragging it down pulls the keyboard down with the finger while the bar stays. A sheet below full height could not do
/// that: iOS moves a sheet to its largest detent when the keyboard rises, and with one detent left the page under it inert
/// (device, 2026-11-13). The bar's "Plein écran" fills the reader instead (`ComposerHeight.full`).
///
/// Part of the modern composer (#904, Réglages › Expérimental › « Composer moderne », #903): with the option off the reader's
/// composers stay the sheet they were (#855 builds the legacy full-screen cover there).
///
/// A sheet elsewhere: on an iPad, and on an iPhone in regular width (a foldable's inner screen, the list beside the reader; a
/// Pro Max in landscape reads at compact width since #431, as legacy's stack), where
/// the list column stays live beside a docked bar and choosing another topic there would tear the reader down with the
/// composer in it, mid-send included; a sheet is modal. The lists' composers (a new topic, a new MP) keep their sheet too:
/// their page has no guard against its taps.
enum ComposerPlacement: Equatable {
    /// A bar at the bottom of the reader, on the keyboard.
    case docked
    /// A sheet over the reader.
    case sheet

    /// The reader's composers: docked on an iPhone whose reader is alone in compact width with the modern composer on
    /// (`modernComposer`, the switch's value), a sheet otherwise.
    static func reader(isPhone: Bool, horizontalSizeClass: UserInterfaceSizeClass?, modernComposer: Bool) -> ComposerPlacement {
        ModernComposer.isActive(isPhone: isPhone, isOn: modernComposer) && horizontalSizeClass == .compact ? .docked : .sheet
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
