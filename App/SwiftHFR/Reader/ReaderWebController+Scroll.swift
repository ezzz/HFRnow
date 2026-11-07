import UIKit

/// Scrolling the reader's page. The web view runs under the bars and banners (LOT-186, M4 Liquid Glass): what covers it is
/// handed to WebKit and to the scroll view, so the first message opens below the bar, the last one scrolls above the bottom
/// bar, a landing and the topmost message (LOT-111) count from the bar's edge, and the bars' scroll edge effect replaces the
/// opaque fills.
extension ReaderWebController {
    /// `landing` keeps the message at the top while late images load (a document's own anchor); a request inside the shown
    /// document scrolls once.
    func scroll(to anchor: Int, landing: Bool = false) {
        let script = "return window.hfrReader.\(landing ? "landOnPost" : "scrollToPost")(n);"
        Task { _ = try? await webView.callAsyncJavaScript(script, arguments: ["n": anchor], in: nil, contentWorld: Self.world) }
    }

    /// Applies `obscuredInsets`, keeping the content at the bars' edge in place: a banner shown above the page does not hide
    /// the message the reader was on.
    func applyObscuredInsets(from old: UIEdgeInsets) {
        let scrollView = webView.scrollView
        let offsetY = ReaderScrollGeometry.offsetY(keeping: scrollView.contentOffset.y, from: old.top, to: obscuredInsets.top)
        webView.obscuredContentInsets = obscuredInsets
        scrollView.contentInset = obscuredInsets
        scrollView.verticalScrollIndicatorInsets = obscuredInsets
        scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: offsetY)
    }

    /// The content position at the lower edge of the top bars (`ReaderScrollGeometry.readingTop`).
    var readingTop: CGFloat {
        ReaderScrollGeometry.readingTop(offsetY: webView.scrollView.contentOffset.y, obscuredTop: obscuredInsets.top)
    }

    /// Scrolls so that `readingTop` is at the lower edge of the top bars, whatever they cover now (a refresh's restore).
    func scroll(toReadingTop readingTop: CGFloat) {
        let scrollView = webView.scrollView
        let offsetY = ReaderScrollGeometry.offsetY(readingTop: readingTop, obscuredTop: obscuredInsets.top)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offsetY), animated: false)
    }
}
