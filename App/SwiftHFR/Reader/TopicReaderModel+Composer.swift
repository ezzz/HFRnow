import Foundation
import SwiftUI

/// A composer the reader presents over its page (#653): the reply, the edit of a message, the MP of the author menu.
enum ReaderComposer: Hashable, Sendable {
    case reply
    case edit
    case privateMessage
}

/// The page under an open composer (#653, operator 2026-11-10): on an iPhone the composer is a bar docked at the bottom of the
/// page (#853) and the page above it still scrolls, with the keyboard up too, so the message being answered can be read again;
/// but its taps and actions are ignored while the composer is open. A link, a message menu, a video, a quote, the reply button, a page change or a refresh would navigate,
/// open a menu, start a second composer or reload the page underneath the text being written. Scrolling and the reading
/// position go on; nothing is cancelled or stopped.
extension TopicReaderModel {
    /// A composer is open over this reader: the page's taps and actions do nothing until it closes.
    var suspendsPageInteractions: Bool { !openComposers.isEmpty }

    /// "Citer extrait" and "Citer gras" in the selection menu: the page can quote and no composer is open over it.
    var offersSelectionQuote: Bool { canQuote && !suspendsPageInteractions }

    /// "Sondage" in the top bar: the page has a poll and no composer is open over it (a second sheet would not show).
    var offersPoll: Bool { page?.poll != nil && !suspendsPageInteractions }

    /// "Marquer comme non lu" in the "…" overflow: the page carries HFR's link and no composer is open over it.
    var offersMarkUnread: Bool { page?.markUnreadURL != nil && !suspendsPageInteractions }

    /// A composer is docked on the keyboard under the page (#853): the page's insets and pull-down follow the keyboard.
    var pageFollowsKeyboard: Bool {
        ComposerPlacement.pageFollowsKeyboard(placement: .readerOnThisDevice, composerIsOpen: suspendsPageInteractions)
    }
}

/// Applies the suspension to the reader's screen: the web view drops the page's taps, the selection menu loses its quotes, and
/// the back button is hidden (going back would drop the composer with its text). Under a docked composer (#853) the bottom bar
/// gives it its place (every control of it is off meanwhile) and dragging the page down pulls the keyboard down with the finger,
/// as in Messages: the bar stays, with its text. Also reports the edit composer, whose presenter (`ReaderEditFlow`) does not
/// hold the reader.
struct ReaderComposerGuard: ViewModifier {
    let model: TopicReaderModel
    let controller: ReaderWebController?
    /// "Editer" has its composer open.
    let isEditing: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: isEditing) { _, isOpen in model.composer(.edit, isOpen: isOpen) }
            .onChange(of: model.suspendsPageInteractions) { _, suspended in
                controller?.ignoresPageTaps = suspended
                controller?.offersSelectionQuote = model.offersSelectionQuote
                controller?.dismissesKeyboardInteractively = model.pageFollowsKeyboard
            }
            .navigationBarBackButtonHidden(model.suspendsPageInteractions)
            .toolbar(model.pageFollowsKeyboard ? .hidden : .automatic, for: .bottomBar)
    }
}
