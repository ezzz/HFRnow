import UIKit

// Port of HFRswift/Swift/MessagesView.swift (`presentPopupMenu` :2011-2058, `popupAnchor` :2062-2081, the edit menu delegate
// `editMenuInteraction(_:menuFor:suggestedActions:)` :2799-2827 and its `UIEditMenuInteraction` on the web view :1249-1251)
// @ 87fe0d1c. Differences: the anchor is the tapped "+" button's rectangle (its target rect), not a point; a menu shown while
// another is open replaces it. GAP-064.
// The SDK's `UIEditMenuInteractionDelegate` is not main-actor isolated: the conformance is (SE-0470), as UIKit calls it on
// the main thread only.
/// The message menu of the reader: the system's horizontal edit-menu callout, anchored at the tapped "+", which pages to the
/// further actions with "›" (operator decision of 2026-11-15 on #594, as legacy). It replaces a SwiftUI popover that opened
/// away from the button.
@MainActor
final class ReaderMessageEditMenu: NSObject, @MainActor UIEditMenuInteractionDelegate {
    /// Where the callout points: its source point, the button it points at, and the arrow's direction.
    struct Placement: Equatable {
        let point: CGPoint
        let target: CGRect
        let arrow: UIEditMenuArrowDirection
    }

    /// The menu on screen and what picking an entry or closing it does.
    private struct Shown {
        let serial: Int
        let menu: MessageMenu
        let target: CGRect
        let pick: @MainActor (MessageMenuAction) -> Void
        let closed: @MainActor () -> Void
    }

    private var interaction: UIEditMenuInteraction?
    private weak var view: UIView?
    private var shown: Shown?
    private var serial = 0

    /// The menu currently shown, nil once it closed (tests read it).
    var shownMenu: MessageMenu? { shown?.menu }

    /// Installs the interaction on the web view (legacy adds it to its `WKWebView`).
    func attach(to view: UIView) {
        let interaction = UIEditMenuInteraction(delegate: self)
        view.addInteraction(interaction)
        self.interaction = interaction
        self.view = view
    }

    /// Shows `menu` at its anchor, in the web view's coordinates; `topInset` is what the bars cover of the web view's top.
    /// `pick` runs a chosen entry, `closed` tells that the menu went away without being replaced.
    func present(
        _ menu: MessageMenu, topInset: CGFloat, pick: @escaping @MainActor (MessageMenuAction) -> Void,
        closed: @escaping @MainActor () -> Void
    ) {
        guard let interaction, let view else { return closed() }
        let placement = Self.placement(of: menu.anchor, topInset: topInset, in: view.bounds)
        serial += 1
        shown = Shown(serial: serial, menu: menu, target: placement.target, pick: pick, closed: closed)
        let configuration = UIEditMenuConfiguration(identifier: NSNumber(value: serial), sourcePoint: placement.point)
        configuration.preferredArrowDirection = placement.arrow
        interaction.presentEditMenu(with: configuration)
    }

    /// Closes the menu from the app's side (the model dropped it: another page, a refresh).
    func dismiss() {
        guard shown != nil else { return }
        shown = nil
        interaction?.dismissMenu()
    }

    /// Legacy `popupAnchor`: the callout points at the button, from above (arrow down) unless the button sits within 40 points
    /// of the bars' edge, where it opens below it (arrow up). A missing anchor, or one off the web view, falls back to legacy's
    /// right edge (15 points in) just below the bars.
    static func placement(of anchor: CGRect?, topInset: CGFloat, in bounds: CGRect) -> Placement {
        let fallback = CGRect(x: max(bounds.maxX - 16, bounds.minX), y: topInset + 44, width: 1, height: 1).intersection(bounds)
        let visible = anchor.map { $0.intersection(bounds) }.flatMap { $0.isNull || $0.isEmpty ? nil : $0 }
        let target = visible ?? (fallback.isNull ? CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1) : fallback)
        let opensBelow = target.minY <= topInset + 40
        return Placement(
            point: CGPoint(x: target.midX, y: opensBelow ? target.maxY : target.minY), target: target,
            arrow: opensBelow ? .up : .down
        )
    }

    /// The entries as edit-menu actions, in the menu's order (legacy: Citer, Citer ☐, Favoris, Link, then the rest behind "›").
    static func actions(for menu: MessageMenu, pick: @escaping @MainActor (MessageMenuAction) -> Void) -> [UIAction] {
        menu.entries.map { action in
            UIAction(
                title: action.title, image: UIImage(systemName: action.systemImageName),
                attributes: action.isDestructive ? .destructive : []
            ) { _ in pick(action) }
        }
    }

    private func current(_ configuration: UIEditMenuConfiguration) -> Shown? {
        guard let shown, (configuration.identifier as? NSNumber)?.intValue == shown.serial else { return nil }
        return shown
    }

    // MARK: - UIEditMenuInteractionDelegate

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        // The system's own suggestions (copy, look up…) are not offered: this callout is the message's menu only.
        guard let shown = current(configuration) else { return nil }
        return UIMenu(title: shown.menu.title, children: Self.actions(for: shown.menu, pick: shown.pick))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        current(configuration)?.target ?? .null
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        // A menu replaced by a newer one says nothing: the model already holds the newer one.
        guard let shown = current(configuration) else { return }
        self.shown = nil
        shown.closed()
    }
}

extension ReaderWebController {
    /// The message menu ("+") of `model` opens as the edit-menu callout at its button (#594); the author menu keeps its popover
    /// (`ReaderMessageMenuAnchor`). A menu the model dropped closes. The picked action runs on the menu it was shown for
    /// (LOT-087: the callout clears the model's menu before the action runs).
    func showMessageMenu(_ menu: MessageMenu?, of model: TopicReaderModel) {
        guard let menu, menu.source == .message else { return messageMenu.dismiss() }
        messageMenu.present(
            menu, topInset: obscuredInsets.top,
            pick: { [weak model] action in Task { [model] in await model?.perform(action, in: menu) } },
            closed: { [weak model] in if model?.presentedMenu == menu { model?.dismissMenu() } }
        )
    }
}
