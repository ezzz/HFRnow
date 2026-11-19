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

/// Keeps `layout.availableHeight` (the tallest card the screen allows, `ComposerCardLayout.room`) current: when the keyboard
/// changes and when one line's height does. The modern chrome's docked card only (`isDocked`): nothing for legacy's composer.
struct ComposerRoomUpdates: ViewModifier {
    @Binding var layout: ComposerCardLayout
    let isDocked: Bool
    @State private var keyboard = ComposerKeyboardRoom()

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboard.keyboardChanged(height: ComposerScreen.keyboardHeight(note))
                update()
            }
            .onChange(of: layout.line, initial: true) { update() }
    }

    private func update() {
        guard isDocked, layout.line > 0, let window = ComposerScreen.window else { return }
        let room = keyboard.room(window: window.height, topInset: window.topInset, line: layout.line)
        if layout.availableHeight != room { layout.availableHeight = room }
    }
}

/// The card's room, which follows the keyboard only while it is up (#1136, review): until the keyboard has shown once there is no
/// room (`nil`: today's six lines, so a long draft never sizes the card over the whole screen and shrinks it when the focus raises
/// the keyboard), and when the keyboard hides the last room stays, so the card does not rise over the page the user scrolled to read.
struct ComposerKeyboardRoom: Equatable {
    /// The last height of the keyboard while it was up; nil until it has been.
    private(set) var lastHeight: CGFloat?

    /// A keyboard frame change: a hidden keyboard (0) changes nothing.
    mutating func keyboardChanged(height: CGFloat) {
        if height > 0 { lastHeight = height }
    }

    /// The room for the card (`ComposerCardLayout.room`) with the last keyboard, nil before there was one.
    func room(window: CGFloat, topInset: CGFloat, line: CGFloat) -> CGFloat? {
        lastHeight.map { ComposerCardLayout.room(window: window, topInset: topInset, keyboard: $0, line: line) }
    }
}
