import CoreGraphics
import SwiftUI

/// How tall the composer sheet is (#653, operator 2026-11-08): on an iPhone a reply or an edit opens at partial height,
/// the page being answered visible above it, and a control switches to the full height and back. A new topic or a new
/// private message keeps the full height: nothing is being answered and its fields need the room. The device decides, not the
/// size class: inside an iPad's form sheet the width is compact too (measured on the iPad Pro 13" simulator, iOS 27.1).
///
/// Legacy shows the composer full screen (`MessagesView.swift:5429-5443`, `coverVerticalFullScreen` @ 87fe0d1c): the partial
/// height is a (b) evolution asked by the operator (GAP-653).
enum ComposerHeight: Equatable {
    /// The page keeps the top third of the screen.
    case partial
    /// The sheet's full height.
    case full

    /// The height the sheet opens at.
    static func initial(for target: ComposerTarget, isPhone: Bool) -> ComposerHeight {
        offersToggle(for: target, isPhone: isPhone) ? .partial : .full
    }

    /// The composer shows the partial / full toggle: a reply or an edit on an iPhone.
    static func offersToggle(for target: ComposerTarget, isPhone: Bool) -> Bool {
        guard isPhone else { return false }
        switch target {
        case .reply, .edit: return true
        case .newTopic, .newPrivateMessage: return false
        }
    }

    /// The other height.
    var toggled: ComposerHeight { self == .partial ? .full : .partial }

    /// The smallest partial sheet: the title bar, two lines of text and the control row.
    static let minimumPartialHeight: CGFloat = 220

    /// The partial sheet's height in the room a sheet may take (`available`, below the status bar): a third of it. The system lifts
    /// a sheet above the keyboard, so with the keyboard up the page keeps the top third, the composer the middle one (measured on
    /// the iPhone 18 Pro Max simulator, iOS 27.1).
    static func partialHeight(available: CGFloat) -> CGFloat {
        min(available, max(minimumPartialHeight, (available / 3).rounded()))
    }

    /// The sheet's only detent at this height. Never both: a sheet that also offers `.large` is expanded to it as soon as the
    /// keyboard comes up (iOS 27.1 simulator), which would hide the page again; the toggle swaps them instead.
    var detent: PresentationDetent { self == .partial ? .custom(PartialComposerDetent.self) : .large }
}

/// The partial composer detent: `ComposerHeight.partialHeight` of the sheet's room.
struct PartialComposerDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        ComposerHeight.partialHeight(available: context.maxDetentValue)
    }
}

/// An opaque sheet background where the composer can be partial (#653); elsewhere the system's own, unchanged.
struct OpaqueComposerSheet: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled { content.presentationBackground(.background) } else { content }
    }
}
