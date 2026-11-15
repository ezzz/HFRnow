import SwiftUI

/// The VoiceOver announcements of the reader and the composer (LOT-163). The wording lives here, pure, so it is tested without
/// a screen; `announce` only speaks while VoiceOver runs (the system ignores the notification otherwise).
enum ReaderAccessibility {
    /// What to say when the page on screen changes from `old` to `new` of `maxPage`: the web view's content changes under the
    /// focus, so nothing else tells a VoiceOver user the page moved. Nil on the first load (no `old`), when the number did not
    /// change (a refresh), and on a single-page topic.
    static func pageAnnouncement(from old: Int?, to new: Int?, maxPage: Int) -> String? {
        guard let old, let new, old != new, maxPage > 1 else { return nil }
        return "Page \(new) sur \(maxPage)"
    }

    /// Name of picture `position` (0-based) of `count` in the image viewer.
    static func imageLabel(position: Int, count: Int) -> String {
        count > 1 ? "Image \(position + 1) sur \(count)" : "Image"
    }

    /// Speaks `text` through VoiceOver; nothing for an empty text.
    @MainActor
    static func announce(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// Speaks what the reader shows without moving VoiceOver's focus (LOT-163): the feedback toast, whoever set it (each call to
/// `showMenuFeedback` grows the serial, so the same text twice is said twice), and a page change.
struct ReaderAnnouncements: ViewModifier {
    let model: TopicReaderModel

    func body(content: Content) -> some View {
        content
            .onChange(of: model.menuFeedbackSerial) { ReaderAccessibility.announce(model.menuFeedback) }
            .onChange(of: model.page?.currentPage) { old, new in
                // A reply, edit or delete confirmation is being spoken: the page it lands on must not cut it off.
                guard model.replyConfirmation == nil else { return }
                ReaderAccessibility.announce(ReaderAccessibility.pageAnnouncement(from: old, to: new, maxPage: model.page?.maxPage ?? 1))
            }
    }
}
