import CoreGraphics

/// The reader's scroll math with the page under the bars (LOT-186). The web view's content runs under the navigation bar,
/// its banners and the bottom bar; `obscuredTop` is what covers the top of the scroll view. What the reader sees first is the
/// content at the bar's lower edge (the "reading top"), not the content at the scroll view's own top: an offset is kept as
/// that reading top, so a page never reopens shifted by a bar or a banner that appeared meanwhile.
enum ReaderScrollGeometry {
    /// The content position at the lower edge of the top bars, for a scroll view at `offsetY` under `obscuredTop` points.
    static func readingTop(offsetY: CGFloat, obscuredTop: CGFloat) -> CGFloat {
        offsetY + obscuredTop
    }

    /// The offset that shows `readingTop` at the lower edge of `obscuredTop` points of bars, never above the content's top
    /// (an offset below `-obscuredTop` would leave a gap between the bar and the first message).
    static func offsetY(readingTop: CGFloat, obscuredTop: CGFloat) -> CGFloat {
        max(readingTop - obscuredTop, -obscuredTop)
    }

    /// The offset that keeps the same content at the bars' edge when the bars covering the top change from `old` to `new`
    /// points (a banner shown or hidden, the bar's height changing with the size class).
    static func offsetY(keeping offsetY: CGFloat, from old: CGFloat, to new: CGFloat) -> CGFloat {
        Self.offsetY(readingTop: readingTop(offsetY: offsetY, obscuredTop: old), obscuredTop: new)
    }

    /// The page position, in the page's own layout points (what `window.scrollTo` takes), of a `readingTop` measured in the
    /// scroll view's points: the scroll view counts them `zoomScale` times larger after a pinch zoom (issue #587).
    static func layoutY(readingTop: CGFloat, zoomScale: CGFloat) -> CGFloat {
        guard zoomScale.isFinite, zoomScale > 0 else { return readingTop }
        return readingTop / zoomScale
    }
}
