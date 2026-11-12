import SwiftUI
import UIKit

/// The arrival sleigh and the objects crossing Noël soft, in the band between the bars of one scene (THEMES.md §4 rules 4–9).
/// It asks `NoelCrossingModel` now and then (every 15 s, every half second while the sleigh waits: never per frame), draws the
/// crossing only while it runs, and stops it as soon as the keyboard, a sheet, an alert or the lock comes up.
struct NoelCrossingLayer: View {
    let seasonal: SeasonalThemeModel
    let isCovered: @MainActor () -> Bool
    @State private var scene = UUID()
    @State private var keyboardVisible = false
    @State private var window = WindowReference()

    private var crossings: NoelCrossingModel { seasonal.crossings }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let crossing = crossings.current, crossing.scene == scene {
                    CrossingSprite(crossing: crossing)
                        .id(crossing.id)
                    if crossing.isArrival {
                        // An overlay closes on a tap (THEMES.md §4 rule 3); the small objects never take a touch.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { crossings.finish(crossing.id) }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            // Started again when the band is laid out or resized (rotation, split view), so a path fits the area it crosses.
            .task(id: WatchKey(isWatching: isWatching, area: proxy.size)) {
                guard isWatching, proxy.size.width > 0, proxy.size.height > 0 else { return }
                await watch(area: proxy.size)
            }
        }
        .accessibilityHidden(true)
        .background(WindowReader(reference: window))
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                keyboardVisible = true
                crossings.screenChanged(for: scene, screen: screen)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification) {
                keyboardVisible = false
            }
        }
        .onDisappear { crossings.release(scene: scene) }
    }

    /// What restarts the watch.
    private struct WatchKey: Equatable {
        var isWatching: Bool
        var area: CGSize
    }

    /// Something may cross: Noël soft is on, or the sleigh is due.
    private var isWatching: Bool { crossings.shouldWatch(scene: scene, theme: seasonal.activeTheme) }

    private var screen: SeasonalThemeModel.ScreenState {
        SeasonalThemeModel.ScreenState(isCovered: isCovered(), isPresenting: window.isPresenting, isKeyboardVisible: keyboardVisible)
    }

    /// Asks for a crossing until one comes, plays it to its end (or until the screen is no longer clear), and asks again.
    private func watch(area: CGSize) async {
        while !Task.isCancelled {
            let windowHeight = window.window?.bounds.height ?? area.height
            if let crossing = crossings.crossing(
                for: scene, on: .init(area: area, windowHeight: windowHeight), screen: screen,
                animationsAllowed: seasonal.animationsAllowed, crossingsOn: seasonal.activeTheme == .noelSoft
            ) {
                // Real time on screen: the model's clock schedules, it does not animate.
                let end = Date().addingTimeInterval(crossing.path.duration)
                while !Task.isCancelled, crossings.current?.id == crossing.id, Date() < end {
                    try? await Task.sleep(for: .milliseconds(250))
                    crossings.screenChanged(for: scene, screen: screen)
                }
                crossings.finish(crossing.id)
            } else {
                try? await Task.sleep(for: crossings.arrivalPending ? .milliseconds(500) : .seconds(15))
            }
        }
    }
}

/// One object on its line, redrawn every frame only while it crosses, from the moment it appears (one view per crossing).
private struct CrossingSprite: View {
    let crossing: NoelCrossingModel.Crossing
    @State private var begin = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(begin)
            Image(crossing.item.assetName)
                .resizable()
                .frame(width: crossing.size.width, height: crossing.size.height)
                // One image holds the sleigh and its reindeer: the mirror turns them as a whole (THEMES.md §6 rule 3).
                .scaleEffect(x: crossing.path.mirrored ? -1 : 1, y: 1)
                .rotationEffect(.radians(crossing.path.rotation))
                .position(crossing.path.point(at: elapsed / crossing.path.duration))
        }
        .allowsHitTesting(false)
    }
}
