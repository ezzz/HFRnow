import Foundation
import HFRClient
import HFRModels

/// A request to open the reply composer, with what to put in it.
struct ReplyRequest: Equatable, Identifiable, Sendable {
    /// Unique per request, so two quotes of the same text are two requests.
    let id = UUID()
    /// Quote blocks to merge into the topic's draft; nil opens the draft as it is.
    var quote: ReplyQuote?
}

// Port of HFRswift/Swift/MessagesView.swift (`openQuoteComposer`, `openTextQuoteComposer`, `openReplyComposer`, `toggleQuoteSelection`)
// @ 21173e7 (`master`; the "+" modes and the selection menu are newer than 2440d79) and HFRswift/Swift/ReplyService.swift:767-841
// @ 2440d79. Differences: docs/lots/LOT-086-quote-composer.md.
/// Quoting from the reader (LOT-086): "Citer", the multi-quote toggle, a quote of the text selection, and what the reply
/// button carries. The reader only asks its screen to open the composer (`pendingReply`); the draft, the merge and the
/// release of the selection after a confirmed send are the composer's.
extension TopicReaderModel {
    /// The reply button: opens the composer on the topic's draft, with the multi-quote selection merged into it when the topic
    /// has one (`quick` and `forum` alike, see the spec). Without a selection, or when the quotes cannot be fetched, the
    /// composer still opens, so a failed quote never blocks a reply; the message says what was not added.
    func requestReply() async {
        guard replyTarget != nil, !isLoadingQuote, pendingReply == nil else { return }
        // Busy before the first await: a second tap meanwhile must not start a second fetch.
        isLoadingQuote = true
        defer { isLoadingQuote = false }
        guard let quoting, let page, let answerURL = page.answerURL, let token = selectionToken(on: page),
              !(await quoting.selectedNumbers(for: token)).isEmpty else {
            pendingReply = ReplyRequest()
            return
        }
        do throws(QuoteError) {
            pendingReply = ReplyRequest(quote: try await quoting.selectionQuote(token, answerFormURL: answerURL))
        } catch {
            showMenuFeedback(ComposerMessages.quote(error))
            // Still opens, carrying the selection: a draft that quotes it releases it once posted.
            pendingReply = ReplyRequest(quote: ReplyQuote(text: "", release: await currentRelease()))
        }
    }

    /// "Citer": the message's own quote, merged into the draft. A failure opens nothing and says why.
    func quoteMessage(post: Int) async {
        guard let quoting, replyTarget != nil, !isLoadingQuote, pendingReply == nil, let actions = actions(of: post) else { return }
        isLoadingQuote = true
        defer { isLoadingQuote = false }
        do throws(QuoteError) {
            pendingReply = ReplyRequest(quote: ReplyQuote(text: try await quoting.quote(actions), release: await currentRelease()))
        } catch {
            showMenuFeedback(ComposerMessages.quote(error))
        }
    }

    /// "Citer extrait" / "Citer gras": the selection `text` of message `post`, narrowed or bolded by LOT-049's formatter. A
    /// selection from another document (a page loaded since) is dropped, like every message of the page.
    func quoteSelection(post: Int, text: String, bold: Bool, token: Int) async {
        guard token == document?.token, let quoting, replyTarget != nil, !isLoadingQuote, pendingReply == nil,
              let actions = actions(of: post) else { return }
        isLoadingQuote = true
        defer { isLoadingQuote = false }
        do throws(QuoteError) {
            let prefill = try await quoting.quote(actions)
            let narrowed = QuoteSelectionFormatter.format(prefill, selection: text, bold: bold)
            pendingReply = ReplyRequest(quote: ReplyQuote(text: narrowed, release: await currentRelease()))
        } catch {
            showMenuFeedback(ComposerMessages.quote(error))
        }
    }

    /// The message menu a tap asks for: the selection is read from the session first, so the "Citer ☐/☑" entry shows the
    /// state as it is now (a reply sent since has released its messages).
    func openMenu(post: Int, source: MessageMenuSource, token: Int) async {
        if let quoting, let selection = selectionToken(on: page) { quoteSelected = Set(await quoting.selectedNumbers(for: selection)) }
        requestMenu(post: post, source: source, token: token)
    }

    /// "Citer ☐/☑": adds the message to the topic's selection or removes it, and returns what to tell the user (nil when
    /// there is nothing to toggle). The selection is the session's cookie (LOT-042): nothing is requested.
    func toggleQuoteSelection(_ context: MessageMenuContext) async -> String? {
        guard let quoting, let token = context.actions.quoteSelection else { return nil }
        let selected = await quoting.toggle(token)
        let numbers = await quoting.selectedNumbers(for: token)
        quoteSelected = Set(numbers)
        return selected ? "Ajouté aux citations (\(numbers.count))" : "Retiré des citations (\(numbers.count))"
    }

    /// The selection as it is now, to release once a reply that quotes some of it is posted: whichever way the composer was
    /// opened, the draft it restores may quote messages that are still selected. Nil when nothing is selected.
    private func currentRelease() async -> QuoteRelease? {
        guard let quoting, let token = selectionToken(on: page) else { return nil }
        let numbers = await quoting.selectedNumbers(for: token)
        return numbers.isEmpty ? nil : QuoteRelease(token: token, numbers: numbers)
    }

    /// The reply the screen has to open, handed over once.
    func takePendingReply() -> ReplyRequest? {
        defer { pendingReply = nil }
        return pendingReply
    }

    /// The quote links of the page on screen's message `post`; nil for a continuation copy or a message the page lacks.
    private func actions(of post: Int) -> MessageActions? {
        page?.messages.first { !$0.isContinuation && $0.numreponse == post }?.actions
    }

    /// Any message's selection token names the topic's cookie, so the first one the page gives will do.
    private func selectionToken(on page: ReaderPage?) -> QuoteSelectionToken? {
        page?.messages.lazy.compactMap(\.actions.quoteSelection).first
    }

    /// The quote entries of the message menu, for the registry: "Citer" and "Citer ☐/☑" (LOT-086).
    func quoteHandlers(confirm: @escaping @MainActor (String) -> Void) -> [any MessageActionHandler] {
        [
            QuoteActionHandler(canQuote: { [weak self] in self?.canQuote ?? false }, quote: { [weak self] post in
                await self?.quoteMessage(post: post)
            }),
            QuoteSelectionHandler(canSelect: { [weak self] in self?.canQuote ?? false }, toggle: { [weak self] context in
                if let text = await self?.toggleQuoteSelection(context) { confirm(text) }
            })
        ]
    }

    /// Quoting needs an account (the engine's session) and an answer form to put the quote in.
    var canQuote: Bool { quoting != nil && replyTarget != nil }
}

/// "Citer": the message's quote into the reply.
@MainActor
struct QuoteActionHandler: MessageActionHandler {
    /// Whether the reader can quote now.
    let canQuote: @MainActor () -> Bool
    /// Quotes message `post`.
    let quote: @MainActor (Int) async -> Void

    var kind: MessageMenuAction.Kind { .quote }

    func isAvailable(for context: MessageMenuContext) -> Bool { canQuote() }

    func perform(with context: MessageMenuContext) async { await quote(context.numreponse) }
}

/// "Citer ☐/☑": the multi-quote toggle.
@MainActor
struct QuoteSelectionHandler: MessageActionHandler {
    /// Whether the reader can quote now.
    let canSelect: @MainActor () -> Bool
    /// Toggles the message of the context.
    let toggle: @MainActor (MessageMenuContext) async -> Void

    var kind: MessageMenuAction.Kind { .quoteSelection }

    func isAvailable(for context: MessageMenuContext) -> Bool { canSelect() }

    func perform(with context: MessageMenuContext) async { await toggle(context) }
}
