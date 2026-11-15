import UIKit
import WebKit

// Port of HFRswift/Swift/MessagesView.swift (`MessageWebView`: `installTextQuoteMenuItems`, `buildMenu`, `requestTextQuote`,
// :545-660) @ 21173e7 (`master`; the "Citer extrait" / "Citer gras" menu is newer than 2440d79). Differences: the web view only
// reports the choice; the page's script reads the selection in the reader's own world and answers through the typed bridge.
/// The reader's web view with two more entries in the text selection menu (LOT-086, community "Quotinuum"): "Citer extrait"
/// quotes the selected passage alone, "Citer gras" quotes the whole message with the passage in bold.
final class QuoteMenuWebView: WKWebView {
    /// Called with `bold` when the user picks an entry.
    var onQuoteSelection: (@MainActor (_ bold: Bool) -> Void)?
    /// The entries show only while this is true (the reader can quote); the standard menu is untouched either way.
    var offersQuote = false
    /// Told whether the web view is now in a window (UIKit's `didMoveToWindow`): the reader's ground truth for "on screen",
    /// which SwiftUI's `onAppear`/`onDisappear` pair does not always give (issue #750).
    var onWindowChange: (@MainActor (_ inWindow: Bool) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        // A menu the system builds without the standard edit group (a context menu of another kind) gets nothing added.
        guard offersQuote, builder.menu(for: .standardEdit) != nil else { return }
        let menu = UIMenu(
            title: "", options: .displayInline,
            children: [
                UICommand(title: "Citer extrait", image: UIImage(systemName: "quote.bubble"), action: #selector(quoteExtract(_:))),
                UICommand(title: "Citer gras", image: UIImage(systemName: "bold"), action: #selector(quoteBold(_:)))
            ]
        )
        builder.insertSibling(menu, afterMenu: .standardEdit)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(quoteExtract(_:)) || action == #selector(quoteBold(_:)) { return offersQuote }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func quoteExtract(_ sender: Any?) { onQuoteSelection?(false) }

    @objc private func quoteBold(_ sender: Any?) { onQuoteSelection?(true) }
}
