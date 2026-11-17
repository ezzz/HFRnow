import UIKit

/// Scrolling the reader's page. The web view runs under the bars and banners (LOT-186, M4 Liquid Glass): what covers it is
/// handed to WebKit and to the scroll view, so the first message opens below the bar, the last one scrolls above the bottom
/// bar, a landing and the topmost message (LOT-111) count from the bar's edge, and the bars' scroll edge effect replaces the
/// opaque fills.
extension ReaderWebController {
    /// `landing` keeps the message at the top while late images load (a document's own anchor); a request inside the shown
    /// document only jumps there. The page scrolls two frames later, past WebKit's reset to the top (`reader.js`, #642); a
    /// landing also waits for the page to show what the scroll view shows now (`from`, #995).
    func scroll(to anchor: Int, landing: Bool = false) {
        if landing {
            run("return window.hfrReader.landOnPost(n, from);", arguments: ["n": anchor, "from": agreementTop])
        } else {
            run("return window.hfrReader.scrollToPost(n);", arguments: ["n": anchor])
        }
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

    /// The content position at the lower edge of the top bars (`ReaderScrollGeometry.readingTop`), in CSS pixels: the scroll
    /// view counts a pinch-zoomed page in points `zoomScale` times larger (its bars' inset is not scaled), while
    /// `window.scrollTo`, which restores it after a refresh, takes CSS pixels at any scale (#587).
    var readingTop: CGFloat {
        let top = ReaderScrollGeometry.readingTop(offsetY: webView.scrollView.contentOffset.y, obscuredTop: obscuredInsets.top)
        return ReaderScrollGeometry.layoutY(readingTop: top, zoomScale: webView.scrollView.zoomScale)
    }

    /// What the page must show before an app scroll runs (`afterAgreement` in `reader.js`, #995): the reading top now, or
    /// `NSNull` while the member moves the scroll view (`WebKitResetWatch.userScrolls`, the one predicate and test seam), whose
    /// reading top is then a moving value the page would never match (the page then scrolls after its two frames, as before
    /// #995).
    var agreementTop: Any {
        resetWatch.userScrolls(webView.scrollView) ? NSNull() : Double(readingTop)
    }

    /// Scrolls so that `readingTop` is at the lower edge of the top bars, whatever they cover now (a refresh's restore). The
    /// page scrolls itself: WebKit counts `scrollY` from the bars' edge once `obscuredContentInsets` is set (`scrollY` is the
    /// reading top, `ReaderInsetsWebTests`), and a native `setContentOffset` at DOMContentLoaded is undone by the new
    /// document's first layout. The page scrolls two frames later, past WebKit's reset to the top (issue #642), and once it shows
    /// what the scroll view shows now (`from`): a reset that reached the scroll view first is on its way to the page (#995).
    func scroll(toReadingTop readingTop: CGFloat) {
        run(
            "return window.hfrReader.restoreScroll(y, from);",
            arguments: ["y": Double(max(0, readingTop)), "from": agreementTop]
        )
    }
}
