import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (MessagesView: reply action, composer sheet) and HFRswift/Swift/AnswerView.swift
// (AnswerView, "Répondre" title) @ 2440d79. Differences: HFR's own confirmation shown above the page; on an iPhone with « Composer
// moderne » on, the composer is a bar docked at the bottom of the page instead of legacy's full-screen cover, which the option off
// keeps (#853, #855, `ComposerPlacement`, GAP-653).
/// The reader's reply entry (LOT-084): the composer (`ReaderComposerPresenter`), and HFR's confirmation above the page once a reply
/// is confirmed.
/// The "Répondre" button is in the reader's bottom bar (`ReaderPageControls`, LOT-186), as legacy's was.
struct ReaderReplyFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's composer; nil when logged out.
    let composer: ComposerServices?
    @State private var reply: ReplyComposerModel?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if model.error == nil, let confirmation = model.replyConfirmation {
                    ConfirmationBanner(text: confirmation, surface: .glass, close: model.clearReplyConfirmation)
                }
            }
            .task(id: model.replyConfirmation) {
                guard model.replyConfirmation != nil else { return }
                ReaderAccessibility.announce(model.replyConfirmation)
                // The model clears it after `ConfirmationAutoDismiss.delay`, whatever happens to this view meanwhile (#864).
            }
            // The reply button and every quote ask the reader; it hands over once, to the sheet that is not open yet.
            .onChange(of: model.pendingReply) { _, request in
                guard request != nil, let taken = model.takePendingReply() else { return }
                guard reply == nil else { return } // a composer is open: the request was a double tap
                guard let composer, let target = model.replyTarget else {
                    // The answer form went away while the quote was fetched: say so instead of dropping the quote silently.
                    model.showMenuFeedback("Réponse indisponible : la page a changé, réessaie.")
                    return
                }
                reply = ReplyComposerModel(target: target, services: composer, quote: taken.quote)
            }
            // EXPERIMENTAL(modernComposer, #904): replaces the composer sheet by `ReaderComposerPresenter`, which docks it on the
            // keyboard with the option on (#853) and, with it off, shows legacy's full-screen cover on an iPhone (#855), a sheet
            // on an iPad.
            .modifier(ReaderComposerPresenter(composer: $reply) { _, reason in
                Task { await model.composerDidClose(reason) }
            })
            // The page under the composer scrolls but ignores its taps while it is open (#653).
            .onChange(of: reply != nil) { _, isOpen in model.composer(.reply, isOpen: isOpen) }
    }
}
