import CoreGraphics
import SwiftUI

/// How tall the composer sheet is (#653): on an iPhone every composer (reply, edit, new topic, new private message) opens at
/// partial height, a card docked on the keyboard (`ComposerCardLayout`) with the page it was opened from visible above it, and
/// a control switches to the full height and back (operator, 2026-11-08 for a reply, 2026-11-10 for the others, 2026-11-10
/// reference for the card). The device decides, not the width's size class: inside an
/// iPad's form sheet the width is compact too (measured on the iPad Pro 13" simulator, iOS 27.1). In compact height (an iPhone
/// in landscape) the system shows every sheet at full height whatever its detents, so there is no toggle there.
/// Every opening starts at partial height: the height chosen with the toggle is not remembered (operator, 2026-11-10).
///
/// Legacy shows the composer full screen (`MessagesView.swift:5429-5443`, `coverVerticalFullScreen` @ 87fe0d1c): the partial
/// height is a (b) evolution asked by the operator (GAP-653).
enum ComposerHeight: Equatable {
    /// The docked card, as tall as its text up to a cap: the page stays visible above it.
    case partial
    /// The sheet's full height.
    case full

    /// The composer offers the partial height and its toggle: an iPhone in regular height.
    static func offersToggle(isPhone: Bool, verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPhone && verticalSizeClass != .compact
    }

    /// The height the sheet shows: the one `chosen` with the toggle; before any choice, partial, or full at an accessibility
    /// text size (`largeText`), where the control row takes two tall rows and a third of the screen leaves no line for the text
    /// (measured at AX XL on the iPhone 18 Pro Max simulator, #749; operator decision, confirmed 2026-11-11). Full without the
    /// toggle (an iPad, or compact height, where the system shows the sheet full anyway), whatever was chosen in regular height.
    static func shown(
        chosen: ComposerHeight?, isPhone: Bool, verticalSizeClass: UserInterfaceSizeClass?, largeText: Bool = false
    ) -> ComposerHeight {
        guard offersToggle(isPhone: isPhone, verticalSizeClass: verticalSizeClass) else { return .full }
        return chosen ?? (largeText ? .full : .partial)
    }

    /// #853 device-test variant: the detents the sheet offers. At partial height a second, larger one (`.large`) so that the
    /// sheet lifted by the keyboard still sits at or below the undimmed bound; the selection stays pinned to `detent`.
    func detents(cardHeight: CGFloat) -> [PresentationDetent] {
        self == .partial ? [detent(cardHeight: cardHeight), .large] : [.large]
    }

    /// #853 device-test variant: the largest detent through which the page above stays interactive (`.large` at partial height).
    var undimmedBound: PresentationDetent { .large }

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
/// keyboard's inset showed the card at the full height).
struct ComposerCardLayout: Equatable {
    /// Lines the editor shows with no text, so the caret and the first line of a reply have room.
    static let minimumLines: CGFloat = 2
    /// Lines past which the editor scrolls inside the card: about the third of the screen the original request (#653) gave the
    /// text and the control row on a 6.9" iPhone, so the page above keeps its top third with the keyboard up.
    static let maximumLines: CGFloat = 6
    /// `UITextView`'s `textContainerInset` (8 pt top and bottom), which `TextEditor` keeps around the text.
    static let editorInsets: CGFloat = 16
    /// Before the first measure: a card of two lines and the parts' usual heights, so the sheet never opens as a sliver.
    static let fallbackHeight: CGFloat = 220

    /// The header, the banners and the fields above the editor.
    var top: CGFloat = 0
    /// The image chips row inside the card, 0 without an image.
    var chips: CGFloat = 0
    /// The control row and, when shown, the "Aa" bar above it.
    var controls: CGFloat = 0
    /// The text as laid out at the editor's width (a hidden copy of it).
    var text: CGFloat = 0
    /// One line of the body font at the current text size.
    var line: CGFloat = 0
    /// The space above and below the card.
    static let gap: CGFloat = 8

    /// The editor's height: its text's, between two and six lines, insets included.
    var editorHeight: CGFloat {
        let lines = max(line, 1)
        return min(max(text, Self.minimumLines * lines), Self.maximumLines * lines) + Self.editorInsets
    }

    /// The card's height; the fallback until the parts have been measured.
    var cardHeight: CGFloat {
        guard top > 0, controls > 0, line > 0 else { return Self.fallbackHeight }
        return (top + chips + editorHeight + 2 * Self.gap + controls).rounded(.up)
    }
}

/// The composer sheet on an iPhone (#653): an opaque background (a sheet below full height is glass, and the dimmed page showed
/// through the editor in dark mode, iOS 27.1 simulator) and, when the presenter ignores its page's taps while the composer is
/// open, the page above the docked card left undimmed and scrollable (operator, 2026-11-10). Elsewhere the system's own.
struct PartialComposerSheet: ViewModifier {
    /// The composer can be partial on this device (an iPhone): the background stays opaque across the toggle.
    let isEnabled: Bool
    let height: ComposerHeight
    /// The sheet's current detent (`ComposerHeight.detent(cardHeight:)`).
    let detent: PresentationDetent
    /// The presenter ignores its page's taps while the composer is open (`TopicReaderModel.suspendsPageInteractions`).
    let pageScrolls: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .presentationBackground(.background)
                // #853 device-test variant: bound by the larger detent, not the card's own.
                .presentationBackgroundInteraction(
                    pageScrolls && height == .partial ? .enabled(upThrough: height.undimmedBound) : .automatic
                )
        } else {
            content
        }
    }
}
