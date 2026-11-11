import UIKit

extension ReaderWebController {
    /// Callbacks to the reader screen.
    struct Events {
        /// The document `token` reached DOMContentLoaded and its images were routed.
        var ready: @MainActor (Int) -> Void = { _ in }
        /// The document `token` could not be shown: its navigation failed twice (issue #566).
        var failed: @MainActor (Int) -> Void = { _ in }
        /// The user tapped a link.
        var link: @MainActor (URL) -> Void = { _ in }
        /// The user tapped the placeholder of video `index` of message `post` in document `token`.
        var video: @MainActor (_ post: Int, _ index: Int, _ token: Int) -> Void = { _, _, _ in }
        /// Scrolling paused with message `post` topmost in document `token` (LOT-111, recorded as the reading position).
        var position: @MainActor (_ post: Int, _ token: Int) -> Void = { _, _ in }
        /// The user tapped the menu button or the author of message `post` in document `token`; `anchor` is the button's
        /// rectangle in the web view's own coordinates (nil when the page gave none).
        var menu: @MainActor (_ post: Int, _ source: MessageMenuSource, _ anchor: CGRect?, _ token: Int) -> Void = { _, _, _, _ in }
        /// The user chose "Citer extrait" or "Citer gras" over `text`, selected in message `post` of document `token` (LOT-086).
        var quote: @MainActor (_ post: Int, _ text: String, _ bold: Bool, _ token: Int) -> Void = { _, _, _, _ in }
        /// The user tapped a posted picture; `images` are those the viewer may show (policy C applied here), opened on `index`.
        var image: @MainActor (_ images: [GalleryImage], _ index: Int, _ token: Int) -> Void = { _, _, _ in }
        /// A short sentence for the reader's feedback line (the result of "Enregistrer dans Photos", #615).
        var notice: @MainActor (_ text: String) -> Void = { _ in }
        /// The reader left the screen: its web view left its window after SwiftUI's `onDisappear` (`+Presence`, issue #750).
        var left: @MainActor () -> Void = {}
        /// The stopped reader is on screen again: its web view entered a window with no `onAppear` to say so (issue #750).
        var returned: @MainActor () -> Void = {}
    }
}
