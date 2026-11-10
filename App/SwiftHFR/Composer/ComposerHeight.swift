import CoreGraphics
import SwiftUI
import UIKit

/// How tall the composer sheet is (#653): on an iPhone every composer (reply, edit, new topic, new private message) opens at
/// partial height, the page it was opened from visible above it, and a control switches to the full height and back
/// (operator, 2026-11-08 for a reply, 2026-11-10 for the others). The device decides, not the width's size class: inside an
/// iPad's form sheet the width is compact too (measured on the iPad Pro 13" simulator, iOS 27.1). In compact height (an iPhone
/// in landscape) the system shows every sheet at full height whatever its detents, so there is no toggle there.
/// Every opening starts at partial height: the height chosen with the toggle is not remembered (operator, 2026-11-10).
///
/// Legacy shows the composer full screen (`MessagesView.swift:5429-5443`, `coverVerticalFullScreen` @ 87fe0d1c): the partial
/// height is a (b) evolution asked by the operator (GAP-653).
enum ComposerHeight: Equatable {
    /// The page keeps the top third of the screen.
    case partial
    /// The sheet's full height.
    case full

    /// The composer offers the partial height and its toggle: an iPhone in regular height.
    static func offersToggle(isPhone: Bool, verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        isPhone && verticalSizeClass != .compact
    }

    /// The height the sheet shows: the one `chosen` with the toggle; before any choice, partial, or full at an accessibility
    /// text size (`largeText`), where the control row takes two tall rows and a third of the screen leaves no line for the text
    /// (measured at AX XL on the iPhone 18 Pro Max simulator, #749). Full without the toggle (an iPad, or compact height, where
    /// the system shows the sheet full anyway), whatever was chosen in regular height.
    static func shown(
        chosen: ComposerHeight?, isPhone: Bool, verticalSizeClass: UserInterfaceSizeClass?, largeText: Bool = false
    ) -> ComposerHeight {
        guard offersToggle(isPhone: isPhone, verticalSizeClass: verticalSizeClass) else { return .full }
        return chosen ?? (largeText ? .full : .partial)
    }

    /// The other height.
    var toggled: ComposerHeight { self == .partial ? .full : .partial }

    /// The smallest partial sheet: the title bar, two lines of text and the control row.
    static let minimumPartialHeight: CGFloat = 220

    /// One line of the recipient, sub-category or subject fields, before Dynamic Type (`ReplyComposerView.messageFields`).
    static let fieldRowHeight: CGFloat = 44

    /// The partial sheet's height in the room a sheet may take (`available`, below the status bar): a third of it, but never
    /// less than the minimum plus `fieldRows` lines of `rowHeight` (a new topic's or a new message's fields stay usable above
    /// two lines of text), and never more than the room. The system lifts a sheet above the keyboard, so with the keyboard up
    /// the page keeps the top third, the composer the middle one (measured on the iPhone 18 Pro Max simulator, iOS 27.1).
    static func partialHeight(available: CGFloat, fieldRows: Int = 0, rowHeight: CGFloat = fieldRowHeight) -> CGFloat {
        let minimum = minimumPartialHeight + CGFloat(fieldRows) * rowHeight
        return min(available, max(minimum, (available / 3).rounded()))
    }

    /// The field lines above the text: recipient (a new private message) or sub-category (a new topic), then the subject.
    static func fieldRows(hasSubject: Bool, hasSecondField: Bool) -> Int {
        guard hasSubject else { return 0 }
        return hasSecondField ? 2 : 1
    }

    /// The sheet's only detent at this height, for a composer with `fieldRows` field lines. Never both heights: a sheet that
    /// also offers `.large` is expanded to it as soon as the keyboard comes up (iOS 27.1 simulator), which would hide the page
    /// again; the toggle swaps them instead.
    func detent(fieldRows: Int) -> PresentationDetent {
        guard self == .partial else { return .large }
        switch fieldRows {
        case 0: return .custom(PartialComposerDetent.self)
        case 1: return .custom(PartialComposerDetentOneField.self)
        default: return .custom(PartialComposerDetentTwoFields.self)
        }
    }
}

/// A partial composer detent: `ComposerHeight.partialHeight` of the sheet's room for `fieldRows` field lines, which follow
/// Dynamic Type as the fields do.
protocol PartialComposerDetentRows: CustomPresentationDetent {
    static var fieldRows: Int { get }
}

extension PartialComposerDetentRows {
    static func height(in context: Context) -> CGFloat? {
        let category = UIContentSizeCategory(context.dynamicTypeSize)
        let row = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: ComposerHeight.fieldRowHeight, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
        )
        return ComposerHeight.partialHeight(available: context.maxDetentValue, fieldRows: fieldRows, rowHeight: row)
    }
}

/// A reply, or an edit without a subject.
struct PartialComposerDetent: PartialComposerDetentRows {
    static let fieldRows = 0
}

/// The edit of a topic's first message: its subject.
struct PartialComposerDetentOneField: PartialComposerDetentRows {
    static let fieldRows = 1
}

/// A new topic (sub-category and subject) or a new private message (recipient and subject).
struct PartialComposerDetentTwoFields: PartialComposerDetentRows {
    static let fieldRows = 2
}

/// The composer sheet at partial height (#653): an opaque background (a sheet below full height is glass, and the dimmed page
/// showed through the editor in dark mode, iOS 27.1 simulator) and, when the presenter ignores its page's taps while the
/// composer is open, the page above it left undimmed and scrollable (operator, 2026-11-10). Elsewhere the system's own, unchanged.
struct PartialComposerSheet: ViewModifier {
    /// The composer can be partial on this device (an iPhone): the background stays opaque across the toggle.
    let isEnabled: Bool
    let height: ComposerHeight
    let fieldRows: Int
    /// The presenter ignores its page's taps while the composer is open (`TopicReaderModel.suspendsPageInteractions`).
    let pageScrolls: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .presentationBackground(.background)
                .presentationBackgroundInteraction(
                    pageScrolls && height == .partial ? .enabled(upThrough: height.detent(fieldRows: fieldRows)) : .automatic
                )
        } else {
            content
        }
    }
}
