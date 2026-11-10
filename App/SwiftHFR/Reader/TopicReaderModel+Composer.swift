import Foundation
import SwiftUI

/// A composer the reader presents over its page (#653): the reply, the edit of a message, the MP of the author menu.
enum ReaderComposer: Hashable, Sendable {
    case reply
    case edit
    case privateMessage
}

/// The page under an open composer (#653, operator 2026-11-10): on an iPhone the composer opens at partial height and the page
/// above it still scrolls, so the message being answered can be read again; but its taps and actions are ignored while the
/// composer is open. A link, a message menu, a video, a quote, the reply button, a page change or a refresh would navigate,
/// open a menu, start a second composer or reload the page underneath the text being written. Scrolling and the reading
/// position go on; nothing is cancelled or stopped.
extension TopicReaderModel {
    /// A composer is open over this reader: the page's taps and actions do nothing until it closes.
    var suspendsPageInteractions: Bool { !openComposers.isEmpty }

    /// "Citer extrait" and "Citer gras" in the selection menu: the page can quote and no composer is open over it.
    var offersSelectionQuote: Bool { canQuote && !suspendsPageInteractions }
}

/// Applies the suspension to the reader's screen: the web view drops the page's taps, the selection menu loses its quotes, and
/// the back button is hidden (going back would drop the sheet with its text). Also reports the edit sheet, whose presenter
/// (`ReaderEditFlow`) does not hold the reader.
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
            }
            .navigationBarBackButtonHidden(model.suspendsPageInteractions)
    }
}
