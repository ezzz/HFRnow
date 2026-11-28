import SwiftUI
import UIKit

/// The packing elves of one scene, in the band between the bars (THEMES.md §4 rules 3–9, §5): once `NoelPackingModel` has a
/// packing waiting, it asks every half second until the screen is clear, plays the elves with « Allez on remballe » for at most
/// 5 s while the decorations fade, and ends them on a tap or as soon as the keyboard, a sheet, an alert or the lock comes up.
struct NoelPackingLayer: View {
    let seasonal: SeasonalThemeModel
    let isCovered: @MainActor () -> Bool
    @State private var scene = UUID()
    @State private var keyboardVisible = false
    @State private var window = WindowReference()
    @Environment(\.scenePhase) private var scenePhase

    private var packing: NoelPackingModel { seasonal.packing }

    var body: some View {
        GeometryReader { proxy in
            if packing.isPlaying(in: scene) {
                let windowHeight = window.window?.bounds.height ?? proxy.size.height
                // Noël's elves, or Samain's witch sweeping the decorations away (LOT-191).
                if packing.current?.theme.family == .samain {
                    WitchSweep(area: proxy.size, windowHeight: windowHeight) { packing.finish() }
                } else {
                    NoelElves(area: proxy.size, windowHeight: windowHeight) { packing.finish() }
                }
            }
        }
        .background(WindowReader(reference: window))
        .task(id: packing.current != nil) {
            await watch()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                keyboardVisible = true
                packing.screenChanged(for: scene, screen: screen)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification) {
                keyboardVisible = false
            }
        }
        // Each scene reports its own phase: only an active scene plays the elves, and another window leaving never ends them.
        .onChange(of: scenePhase, initial: true) { _, phase in packing.sceneChanged(scene, active: phase == .active) }
        .onDisappear { packing.release(scene: scene) }
    }

    private var screen: SeasonalThemeModel.ScreenState {
        SeasonalThemeModel.ScreenState(isCovered: isCovered(), isPresenting: window.isPresenting, isKeyboardVisible: keyboardVisible)
    }

    /// Asks until the packing starts here (or another scene, or nothing, takes it), plays it to its end, and asks again if it
    /// was cut in its first second and waits to replay.
    private func watch() async {
        while !Task.isCancelled, packing.current != nil {
            guard packing.start(for: scene, screen: screen, animationsAllowed: seasonal.animationsAllowed) != nil else {
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }
            // The overlay is hidden from VoiceOver (rule 6): its words are announced instead, once per packing, not per replay.
            if packing.shouldAnnounce() { AccessibilityNotification.Announcement("Allez on remballe").post() }
            let end = Date().addingTimeInterval(NoelPackingModel.duration)
            while !Task.isCancelled, packing.isPlaying(in: scene), Date() < end {
                try? await Task.sleep(for: .milliseconds(250))
                packing.screenChanged(for: scene, screen: screen)
            }
            // Played to the end on a clear screen: done. Cut, it waits to replay or is held; the loop asks again, and a held
            // theme goes once this screen is clear.
            if packing.isPlaying(in: scene) { packing.finish() }
        }
    }
}

/// The elves rising from the band's bottom edge, packing and going back down, with « Allez on remballe » above them; redrawn
/// every frame only while they play (one view per packing). A tap anywhere in the band ends them (THEMES.md §4 rule 3).
private struct NoelElves: View {
    let area: CGSize
    let windowHeight: CGFloat
    let close: () -> Void
    @State private var begin = Date()

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let progress = timeline.date.timeIntervalSince(begin) / NoelPackingModel.duration
                let frames = NoelPackingLayout.frames(in: area, windowHeight: windowHeight, progress: progress)
                ZStack {
                    ForEach(frames.enumerated(), id: \.offset) { elf in
                        Image("NoelElf")
                            .resizable()
                            .frame(width: elf.element.width, height: elf.element.height)
                            .position(x: elf.element.midX, y: elf.element.midY)
                    }
                    Text("Allez on remballe")
                        .font(.headline)
                        .padding()
                        .background(.regularMaterial, in: .capsule)
                        .opacity(NoelPackingLayout.rise(at: progress))
                }
                .frame(width: area.width, height: area.height)
            }
            Button(action: close) {
                Color.clear.contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: area.width, height: area.height)
        .clipped()
        .accessibilityHidden(true)
    }
}
