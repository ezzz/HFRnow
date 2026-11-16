import UIKit

/// Holds a new document's landing or restore until WebKit has reset the scroll view to the document's top (#772).
///
/// WebKit resets the scroll view of a new document when it applies the first layer-tree commit after the navigation's commit,
/// often after the page reported ready, and the page then follows the scroll view: a scroll sent before that reset was undone
/// on a loaded CI runner (`scrollY` 1000, then 0), which the two frames `reader.js` waits (#642) did not always cover. The watch
/// starts at the commit (`start`) and sees the reset as the scroll view arriving at its top.
///
/// A scroll view still away from its top at ready shows the previous document: the reset is certain to move it, and the action
/// waits for it. One already at its top may have been reset without moving: the action runs at once, and once more if the reset
/// comes later, until the page reports a reading position. A drag or a fling, a new document, or the reset itself ends the watch.
@MainActor
final class WebKitResetWatch {
    /// Whether the reader is moving the scroll view; tests replace it (a plain scroll view cannot be dragged).
    var userScrolls: @MainActor (UIScrollView) -> Bool = { $0.isTracking || $0.isDragging || $0.isDecelerating }
    /// The document whose reset is watched; nil when none is.
    private(set) var token: Int?
    /// The document whose navigation committed last (`start`), until another one is shown (`stop`); watched or not.
    private(set) var committedToken: Int?
    /// The document whose reset came.
    private var resetToken: Int?
    private var action: (@MainActor @Sendable () -> Void)?
    /// The action already ran at ready (scroll view at its top): the reset only gives it a second chance.
    private var isSecondChance = false
    private var observation: NSKeyValueObservation?

    /// The navigation of document `token` committed: WebKit resets `scrollView` at its next layer-tree commit. Nothing is
    /// watched while the reader is scrolling.
    func start(token: Int, on scrollView: UIScrollView) {
        stop()
        committedToken = token
        guard !userScrolls(scrollView) else { return }
        self.token = token
        observation = scrollView.observe(\.contentOffset) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.moved(scrollView)
            }
        }
    }

    /// Runs `action` for document `token` (its landing or restore, at ready) once WebKit's reset has come; at once when the
    /// reset came already or nothing is watched.
    func perform(token: Int, on scrollView: UIScrollView, _ action: @escaping @MainActor @Sendable () -> Void) {
        guard self.token == token, resetToken != token else { return action() }
        if Self.isAtTop(scrollView) {
            action()
            isSecondChance = true
        }
        self.action = action
    }

    /// The page reported a reading position: what it shows is the reader's from now on, so a second chance expires.
    func pageReportedPosition() {
        if isSecondChance { end() }
    }

    /// Another document is shown: nothing held for the previous one runs, not even an action already queued at its reset.
    func stop() {
        end()
        resetToken = nil
        committedToken = nil
    }

    /// Ends the watch. The observation is invalidated, not released: this can run inside its own callback.
    private func end() {
        observation?.invalidate()
        token = nil
        action = nil
        isSecondChance = false
    }

    private func moved(_ scrollView: UIScrollView) {
        guard let token else { return }
        if userScrolls(scrollView) { return end() }
        guard Self.isAtTop(scrollView) else { return }
        let action = self.action
        end()
        resetToken = token
        guard let action else { return }
        // After this turn, so WebKit's own update of the page for the reset leaves first.
        Task { @MainActor [weak self] in
            guard self?.resetToken == token else { return }
            action()
        }
    }

    /// The scroll view shows the top of its content, below what covers it: where WebKit puts a new document (the reader sets
    /// `contentInset` to the bars it runs under, `ReaderWebController.applyObscuredInsets`).
    static func isAtTop(_ scrollView: UIScrollView) -> Bool {
        abs(scrollView.contentOffset.y + scrollView.contentInset.top) <= 1
    }
}
