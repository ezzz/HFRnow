import Foundation
import WebKit

/// The scripts of the reader's world: `reader.js`, and the text size and theme colours set before a document renders and
/// live on the shown one (LOT-169, LOT-121).
extension ReaderWebController {
    private static let readerScript: String? = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// The scripts that set the text size, the theme colours of a document before it renders, then `reader.js`; all in
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

    /// Runs `script` in the reader's world without waiting for its answer. Nothing holds the controller meanwhile: a page out
    /// of its window can stay without answering (WebKit suspends its process), and a pending call kept the reader alive (#772).
    func run(_ script: String, arguments: [String: Any] = [:]) {
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: Self.world, completionHandler: nil)
    }

    /// Sets `--text-scale` (read by `reader.css`) on the shown document's root element.
    func applyTextScale() {
        guard document != nil else { return }
        run(Self.textScaleScript(textScale))
    }

    /// Sets the theme's CSS variables (read by `reader.css`) on the shown document's root element.
    func applyTheme() {
        guard document != nil else { return }
        run(theme.readerScript)
    }

    /// What a new document takes from the controller once it is ready: the text size, the theme and the hint.
    func applyDisplayState() {
        applyTextScale()
        applyTheme()
    }

    /// The page's own background (the dark style's, LOT-122) shows past the page's ends while it bounces. WebKit resolves the colour
    /// when it is set, so it is set again when iOS or the theme setting flips light and dark.
    func applyUnderPageBackground() {
        webView.underPageBackgroundColor = theme.readerBackground.resolvedColor(with: webView.traitCollection)
    }

    func trackUnderPageBackground() {
        applyUnderPageBackground()
        webView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIView, _) in
            self?.applyUnderPageBackground()
        }
    }

    /// The script that sets `--text-scale` to `scale`'s factor; a number the app formats, never page text.
    static func textScaleScript(_ scale: TextScale) -> String {
        let factor = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(scale.factor))
        return "document.documentElement.style.setProperty('--text-scale', '\(factor)');"
    }
}
