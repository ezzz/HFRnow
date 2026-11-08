import UIKit

/// Scrolling the reader's page. The web view runs under the bars and banners (LOT-186, M4 Liquid Glass): what covers it is
/// handed to WebKit and to the scroll view, so the first message opens below the bar, the last one scrolls above the bottom
/// bar, a landing and the topmost message (LOT-111) count from the bar's edge, and the bars' scroll edge effect replaces the
/// opaque fills.
extension ReaderWebController {
    /// WebKit resets the scroll view of a new document to its top when it applies the document's first layer-tree commit, so
    /// a scroll the page made in the same commit is lost: the landing or the restore of a document just ready opened at the
    /// top now and then (issue #642). Two animation frames put the scroll in a later commit.
    private static let afterFirstFrames = "await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));"

    /// `landing` keeps the message at the top while late images load (a document's own anchor, scrolled once the document's
    /// first frames are drawn); a request inside the shown document scrolls once, at once.
    func scroll(to anchor: Int, landing: Bool = false) {
        let script = landing
            ? "\(Self.afterFirstFrames) return window.hfrReader.landOnPost(n);"
            : "return window.hfrReader.scrollToPost(n);"
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

    /// Scrolls so that `readingTop` is at the lower edge of the top bars, whatever they cover now (a refresh's restore). The
    /// page scrolls itself: WebKit counts `scrollY` from the bars' edge once `obscuredContentInsets` is set (`scrollY` is the
    /// reading top, `ReaderInsetsWebTests`), and a native `setContentOffset` at DOMContentLoaded is undone by the new
    /// document's first layout. The page waits for its first frames too (`afterFirstFrames`).
    func scroll(toReadingTop readingTop: CGFloat) {
        let script = "\(Self.afterFirstFrames) window.scrollTo(0, y); return true;"
        let top = Double(max(0, readingTop))
        Task { _ = try? await webView.callAsyncJavaScript(script, arguments: ["y": top], in: nil, contentWorld: Self.world) }
    }
}
