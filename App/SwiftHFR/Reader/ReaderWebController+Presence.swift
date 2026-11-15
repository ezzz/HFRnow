import UIKit

/// When the reader is on screen (issue #750): SwiftUI's `onAppear` and `onDisappear`, checked against the web view's window.
extension ReaderWebController {
    /// The screen is back: `show` loads again (call it before `show`).
    func resume() {
        stopped = false
        stoppedDocument = nil
    }

    /// SwiftUI's `onAppear`: the screen is back (`resume()`).
    func viewAppeared() {
        disappeared = false
        resume()
    }

    /// SwiftUI's `onDisappear`. SwiftUI also sends it to a reader pushed again in a collapsed split view, in the same
    /// millisecond as its `onAppear` and before its web view is in a window, and then never sends `onAppear` again although
    /// the reader stays on screen (issue #750: every topic opened after the first one, #643 on conversations). So the
    /// window decides: the reader leaves (`events.left`) only when its web view is in none, and one stopped while it was
    /// on its way in comes back when its web view enters a window (`windowDidChange`).
    func viewDisappeared() {
        disappeared = true
        guard webView.window == nil else {
            ReaderLog.debug("disappear ignored: in a window")
            return
        }
        events.left()
    }

    /// UIKit's ground truth for "on screen" (the web view's `didMoveToWindow`): a stopped reader whose web view enters a
    /// window is on screen again, and one SwiftUI said had gone leaves once its web view leaves the window (issue #750).
    func windowDidChange(inWindow: Bool) {
        ReaderLog.debug("window in=\(inWindow) token=\(document?.token ?? -1) stopped=\(stopped) disappeared=\(disappeared)")
        if inWindow {
            guard stopped else { return }
            let document = stoppedDocument
            resume()
            show(document)
            events.returned()
        } else if disappeared, !stopped {
            events.left()
        }
    }
}
