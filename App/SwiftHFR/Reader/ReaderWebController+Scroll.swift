import UIKit

/// Scrolling the reader's page. The web view runs under the bars and banners (LOT-186, M4 Liquid Glass): what covers it is
/// handed to WebKit and to the scroll view, so the first message opens below the bar, the last one scrolls above the bottom
/// bar, a landing and the topmost message (LOT-111) count from the bar's edge, and the bars' scroll edge effect replaces the
/// opaque fills.
extension ReaderWebController {
    /// `landing` keeps the message at the top while late images load (a document's own anchor); a request inside the shown
    /// document only jumps there. The page scrolls two frames later, past WebKit's reset to the top (`reader.js`, #642).
    func scroll(to anchor: Int, landing: Bool = false) {
        run("return window.hfrReader.\(landing ? "landOnPost" : "scrollToPost")(n);", arguments: ["n": anchor])
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

    /// Scrolls so that `readingTop` is at the lower edge of the top bars, whatever they cover now (a refresh's restore). The
    /// page scrolls itself: WebKit counts `scrollY` from the bars' edge once `obscuredContentInsets` is set (`scrollY` is the
    /// reading top, `ReaderInsetsWebTests`), and a native `setContentOffset` at DOMContentLoaded is undone by the new
    /// document's first layout. The page scrolls two frames later, past WebKit's reset to the top (issue #642).
    func scroll(toReadingTop readingTop: CGFloat) {
        run("return window.hfrReader.restoreScroll(y);", arguments: ["y": Double(max(0, readingTop))])
    }

    /// Runs `action` (a new document's landing or restore) once WebKit has reset the scroll view to the new document's top.
    /// WebKit does it when it applies the document's first layer-tree commit, often after the page reported ready, and the page
    /// then follows the scroll view: a scroll sent before that reset was undone on a loaded CI runner (`scrollY` 1000, then 0,
    /// #772), which the two frames `reader.js` waits (#642) did not always cover. While the scroll view still shows another
    /// offset than the top, the previous document's, the reset is to come and the action waits for it. A drag first is the
    /// reader's own choice and cancels it.
    func scrollAfterWebKitReset(_ action: @escaping @MainActor @Sendable (ReaderWebController) -> Void) {
        resetObservation = nil
        guard !isAtTop(webView.scrollView) else {
            action(self)
            return
        }
        resetObservation = webView.scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                guard let self, scrollView.isTracking || self.isAtTop(scrollView) else { return }
                // Invalidated, not released: the observation runs this very callback. The next document replaces it.
                self.resetObservation?.invalidate()
                guard !scrollView.isTracking else { return }
                // After this turn, so WebKit's own update of the page for the reset leaves first.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    action(self)
                }
            }
        }
    }

    /// The scroll view shows the top of the document, below the bars: where WebKit puts a new document.
    private func isAtTop(_ scrollView: UIScrollView) -> Bool {
        abs(ReaderScrollGeometry.readingTop(offsetY: scrollView.contentOffset.y, obscuredTop: obscuredInsets.top)) <= 1
    }
}
