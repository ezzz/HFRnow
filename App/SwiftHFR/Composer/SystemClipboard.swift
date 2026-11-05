import UIKit

/// The general pasteboard. Reading `string` may show the system's paste prompt, as in the legacy app.
@MainActor
struct SystemClipboard: ClipboardReading {
    var changeCount: Int { UIPasteboard.general.changeCount }
    var url: URL? { UIPasteboard.general.url }
    var string: String? { UIPasteboard.general.string }
}
