import WebKit

/// The selection menu of the reader (LOT-086): the native entries live in `QuoteMenuWebView`, the reading of the selection in
/// `reader.js`, and the answer comes back as a typed `ReaderBridgeMessage.quote`.
extension ReaderWebController {
    /// The selection menu offers "Citer extrait" and "Citer gras" only while the reader can quote (an account is current and
    /// the page has an answer form).
    var offersSelectionQuote: Bool {
        get { webView.offersQuote }
        set { webView.offersQuote = newValue }
    }

    /// Asks the page which message holds the selection and what it says; `reader.js` answers with a `quote` message, or
    /// with nothing when the selection is empty or not inside one message. Without a document the call fails and is ignored.
    func requestSelectionQuote(bold: Bool) {
        let script = "return window.hfrReader.quoteSelection(bold);"
        Task { _ = try? await webView.callAsyncJavaScript(script, arguments: ["bold": bold], in: nil, contentWorld: Self.world) }
    }
}
