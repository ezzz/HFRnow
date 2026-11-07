import Foundation
import WebKit

/// The scripts of the reader's world: `reader.js`, and the text size and theme colours set before a document renders and
/// live on the shown one (LOT-169, LOT-121).
extension ReaderWebController {
    private static let readerScript: String? = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// The scripts that set the text size and the theme colours of a document before it renders, then `reader.js`; all in
    /// the reader's world.
    func installUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        for source in [Self.textScaleScript(textScale), theme.readerScript] {
            controller.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world)
            )
        }
        if let script = Self.readerScript {
            controller.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world)
            )
        }
    }

    /// Sets `--text-scale` (read by `reader.css`) on the shown document's root element.
    func applyTextScale() {
        guard document != nil else { return }
        let script = Self.textScaleScript(textScale)
        Task { _ = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: Self.world) }
    }

    /// Sets the theme's CSS variables (read by `reader.css`) on the shown document's root element.
    func applyTheme() {
        guard document != nil else { return }
        let script = theme.readerScript
        Task { _ = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: Self.world) }
    }

    /// The script that sets `--text-scale` to `scale`'s factor; a number the app formats, never page text.
    static func textScaleScript(_ scale: TextScale) -> String {
        let factor = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(scale.factor))
        return "document.documentElement.style.setProperty('--text-scale', '\(factor)');"
    }
}
