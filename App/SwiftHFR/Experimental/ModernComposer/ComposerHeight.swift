import CoreGraphics
import SwiftUI

/// How tall the composer is (#653): on an iPhone a reply and an edit open at partial height (a new topic and a new private
/// message open full screen with no toggle, `ReplyComposerModel.opensFullScreen`, #1137: new content has no page to keep in
/// view), a card docked on the keyboard (`ComposerCardLayout`) with the page it was opened from visible above it (in the
/// reader a bar docked at the bottom of the page, elsewhere a sheet: `ComposerPlacement`, #853), and
/// a control switches to the full height and back (operator, 2026-11-08 for a reply, 2026-11-10 for the others, 2026-11-10
/// reference for the card). The device decides, not the width's size class: inside an
/// iPad's form sheet the width is compact too (measured on the iPad Pro 13" simulator, iOS 27.1). In compact height (an iPhone
/// in landscape) the system shows every sheet at full height whatever its detents, so there is no toggle there (the reader's
/// docked bar fills the reader there too).
/// Every opening of a reply or an edit starts at partial height: the height chosen with the toggle is not remembered
/// (operator, 2026-11-10).
///
/// Legacy shows the composer full screen (`MessagesView.swift:5429-5443`, `coverVerticalFullScreen` @ 87fe0d1c): the partial
/// height is a (b) evolution asked by the operator (GAP-653).
enum ComposerHeight: Equatable {
    /// The docked card, as tall as its text up to a cap: the page stays visible above it.
    case partial
    /// The sheet's full height.
    case full

    /// The composer offers the partial height and its toggle: an iPhone in regular height, unless it opens full screen with no
    /// way to shrink it (`opensFull`: a new private message or topic, #1137).
    static func offersToggle(isPhone: Bool, verticalSizeClass: UserInterfaceSizeClass?, opensFull: Bool = false) -> Bool {
        isPhone && verticalSizeClass != .compact && !opensFull
    }

    /// The height the sheet shows: the one `chosen` with the toggle; before any choice, partial, or full at an accessibility
    /// text size (`largeText`), where the control row takes two tall rows and a third of the screen leaves no line for the text
    /// (measured at AX XL on the iPhone 18 Pro Max simulator, #749; operator decision, confirmed 2026-11-11). Full without the
    /// toggle (an iPad, or compact height, where the system shows the sheet full anyway), whatever was chosen in regular height.
    static func shown(
        chosen: ComposerHeight?, isPhone: Bool, verticalSizeClass: UserInterfaceSizeClass?, largeText: Bool = false,
        opensFull: Bool = false
    ) -> ComposerHeight {
        guard offersToggle(isPhone: isPhone, verticalSizeClass: verticalSizeClass, opensFull: opensFull) else { return .full }
        return chosen ?? (largeText ? .full : .partial)
    }

    /// The other height.
    var toggled: ComposerHeight { self == .partial ? .full : .partial }

    /// The docked card's only detent at this height: its measured height (`ComposerCardLayout.cardHeight`) at partial
    /// height, `.large` at full. Never both heights: a sheet that also offers `.large` is expanded to it as soon as the keyboard
    /// comes up (iOS 27.1 simulator), which would hide the page again; the toggle swaps them instead.
    func detent(cardHeight: CGFloat) -> PresentationDetent {
        self == .partial ? .height(cardHeight) : .large
    }
}

/// The docked card's height (#653, operator reference of 2026-11-10: "the card grows with the text, up to a maximum height;
/// past that, the editor scrolls inside it", as the Claude app's input box). Every part but the editor is measured as laid out
/// (header, banners, fields, image chips, control row); the editor is as tall as its text, between `minimumLines` and
/// `maximumLines` lines of the body font, plus the text view's own top and bottom insets. The system lifts the sheet over the
/// keyboard, so the keyboard is no part of it (measured on the iPhone 18 Pro Max simulator, iOS 27.2: a detent that added the
/// keyboard's inset showed the card at the full height). On an iPhone the controls sit inside the text card, under the editor
/// (#854, `textCardHeight`): the editor stops at its cap, so the text never covers them.
struct ComposerCardLayout: Equatable {
    /// Lines the editor shows with no text, so the caret and the first line of a reply have room.
    static let minimumLines: CGFloat = 2
    /// Lines the editor always shows before it scrolls: about the third of the screen the original request (#653) gave the text and
    /// the control row on a 6.9" iPhone. It is the cap until the room is measured, and the floor of the cap after (#1136).
    static let maximumLines: CGFloat = 6
    /// `UITextView`'s `textContainerInset` (8 pt top and bottom), which `TextEditor` keeps around the text.
    static let editorInsets: CGFloat = 16
    /// Before the first measure: a card of two lines and the parts' usual heights, so the sheet never opens as a sliver.
    static let fallbackHeight: CGFloat = 220

    /// The floating buttons, the banners and the fields above the text card.
    var top: CGFloat = 0
    /// The image chips row inside the card, 0 without an image.
    var chips: CGFloat = 0
    /// The control row and, when shown, the "Aa" bar above it: inside the text card, at its bottom edge (#854).
    var controls: CGFloat = 0
    /// The text as laid out at the editor's width (a hidden copy of it).
    var text: CGFloat = 0
    /// One line of the body font at the current text size.
    var line: CGFloat = 0
    /// The tallest card the screen allows (`room`): the editor grows up to it, then scrolls. nil until it is measured: today's
    /// six lines (#1136).
    var availableHeight: CGFloat?
    /// The reader's inline navigation bar's height: 54 pt measured on the iPhone 18 Pro simulator, iOS 27.2 (#1286; the HIG's 44 pt
    /// left the room 10 pt too tall): the card stays below it.
    static let navigationBarHeight: CGFloat = 54
    /// Lines of the body font kept visible of the page above the card, so the header of its last message shows (#1136).
    static let pageStripLines: CGFloat = 3

    /// The room for the card on a screen: the window less the top safe area, the navigation bar, the keyboard and a strip of the
    /// page above (`pageStripLines`). The system lifts the sheet over the keyboard, so the keyboard counts here, not in the
    /// card's own height. Never negative.
    static func room(window: CGFloat, topInset: CGFloat, keyboard: CGFloat, line: CGFloat) -> CGFloat {
        max(0, window - topInset - navigationBarHeight - keyboard - pageStripLines * line)
    }
    /// The space above and below the card with legacy's chrome (an iPad, or the option off). The modern composer's is
    /// `ComposerChrome.cardInsets` (#895).
    static let gap: CGFloat = 8

    /// The editor's height: its text's, from two lines up to `textCap`, insets included.
    var editorHeight: CGFloat {
        let lines = max(line, 1)
        return min(max(text, Self.minimumLines * lines), textCap) + Self.editorInsets
    }

    /// The most text the editor shows before it scrolls: what is left of `availableHeight` once the buttons, the banners, the
    /// chips, the controls, the gaps and the text view's insets are taken (#1136), never under six lines (the cap before the
    /// room was measured); six lines until it is.
    var textCap: CGFloat {
        let lines = max(line, 1)
        guard let availableHeight else { return Self.maximumLines * lines }
        let insets = ComposerChrome.docked.cardInsets
        let room = availableHeight - top - chips - controls - insets.top - insets.bottom - Self.editorInsets
        return max(Self.maximumLines * lines, room)
    }

    /// This layout with the image chips row `height` tall (0 without an image). The editor card and the sheet's detent both read
    /// it, so the row is taken off the editor's cap in both (#1286: the card once ignored it).
    func withChips(height: CGFloat) -> ComposerCardLayout {
        var copy = self
        copy.chips = height
        return copy
    }

    /// The rounded text card (#854): the image chips, the editor, then the controls on its bottom edge.
    var textCardHeight: CGFloat { chips + editorHeight + controls }

    /// The docked sheet's height: what is above the text card (the floating buttons with their insets, #895), the card and
    /// the modern chrome's gaps around it (`ComposerChrome.cardInsets`); the fallback until the parts have been measured. Only
    /// the modern composer opens at partial height, so its insets are the ones that count.
    var cardHeight: CGFloat {
        guard top > 0, controls > 0, line > 0 else { return Self.fallbackHeight }
        let insets = ComposerChrome.docked.cardInsets
        return (top + textCardHeight + insets.top + insets.bottom).rounded(.up)
    }
}

/// The settings a composer sheet gives its presentation (a list's composer, an iPad's, the reader's with the option off): its
/// one detent, no swipe-down while closing needs a choice or a send runs, and for the modern composer only (#904) an opaque
/// background (a sheet below full height is glass, and the dimmed page showed through the editor in dark mode, iOS 27.1
/// simulator). None for the reader's docked bar (#853): set from inside the reader, they would reach the reader's own
/// presentation.
struct ComposerSheetSettings: ViewModifier {
    let isSheet: Bool
    /// The modern composer (`ModernComposer.isActive`): the background stays opaque across the toggle.
    let isModern: Bool
    /// The sheet's only detent (`ComposerHeight.detent(cardHeight:)`).
    let detent: PresentationDetent
    /// Swiping down would close without the choice: blocked while there is text or a send runs.
    let dismissDisabled: Bool

    func body(content: Content) -> some View {
        if isSheet {
            content
                .presentationDetents([detent])
                .modifier(OpaqueWhenModern(isModern: isModern))
                .interactiveDismissDisabled(dismissDisabled)
        } else {
            content
        }
    }

    // EXPERIMENTAL(modernComposer, #904): replaces the system's sheet background by an opaque one.
    private struct OpaqueWhenModern: ViewModifier {
        let isModern: Bool

        func body(content: Content) -> some View {
            if isModern { content.presentationBackground(.background) } else { content }
        }
    }
}
