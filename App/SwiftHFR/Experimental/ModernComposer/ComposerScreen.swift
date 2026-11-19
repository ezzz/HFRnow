import SwiftUI
import UIKit

// EXPERIMENTAL(modernComposer, #904): what the docked card's growth limit reads of the screen (#1136).
/// The window and the keyboard as the docked card's room sees them (`ComposerCardLayout.room`).
enum ComposerScreen {
    /// The key window's height and top safe-area inset; nil without a window (a preview).
    @MainActor
    static var window: (height: CGFloat, topInset: CGFloat)? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        return (window.bounds.height, window.safeAreaInsets.top)
    }

    /// How much of the key window the keyboard of `note` covers (0 when it hides).
    @MainActor
    static func keyboardHeight(_ note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
                  .first(where: \.isKeyWindow)
        else { return 0 }
        return max(0, window.bounds.maxY - window.convert(frame, from: nil).minY)
    }
}
