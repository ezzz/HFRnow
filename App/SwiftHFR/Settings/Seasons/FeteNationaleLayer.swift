import SwiftUI
import UIKit

/// The 14 July overlay of one scene, in the band between the bars (THEMES.md §4 rules 3–9, §5): once `FeteNationaleModel` has an
/// overlay waiting, it asks every half second until the screen is clear, plays a bust of Marianne with fireworks and
/// « Fête nationale » for 4 s, and ends it on a tap or as soon as the keyboard, a sheet, an alert or the lock comes up.
struct FeteNationaleLayer: View {
    let seasonal: SeasonalThemeModel
    let isCovered: @MainActor () -> Bool
    @State private var scene = UUID()
    @State private var keyboardVisible = false
    @State private var window = WindowReference()
    @Environment(\.scenePhase) private var scenePhase

    private var fete: FeteNationaleModel { seasonal.fete }

    var body: some View {
        GeometryReader { proxy in
            if fete.isPlaying(in: scene) {
                FeteNationaleScene(area: proxy.size) { fete.finish() }
            }
        }
        .background(WindowReader(reference: window))
        .task(id: fete.current != nil) {
            await watch()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                keyboardVisible = true
                fete.screenChanged(for: scene, screen: screen)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification) {
                keyboardVisible = false
            }
        }
        // Each scene reports its own phase: only an active scene plays the overlay, and another window leaving never ends it.
        .onChange(of: scenePhase, initial: true) { _, phase in fete.sceneChanged(scene, active: phase == .active) }
        .onDisappear { fete.release(scene: scene) }
    }

    private var screen: SeasonalThemeModel.ScreenState {
        SeasonalThemeModel.ScreenState(isCovered: isCovered(), isPresenting: window.isPresenting, isKeyboardVisible: keyboardVisible)
    }

    /// Asks until the overlay starts here (or another scene, or nothing, takes it), plays it to its end, and asks again if it
    /// was cut in its first second and waits to replay.
    private func watch() async {
        while !Task.isCancelled, fete.current != nil {
            guard fete.start(for: scene, screen: screen, animationsAllowed: seasonal.animationsAllowed) != nil else {
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }
            // The overlay is hidden from VoiceOver (rule 6): its words are announced instead, once, not per replay.
            if fete.shouldAnnounce() { AccessibilityNotification.Announcement(FeteNationaleLayout.text).post() }
            let end = Date().addingTimeInterval(FeteNationaleModel.duration)
            while !Task.isCancelled, fete.isPlaying(in: scene), Date() < end {
                try? await Task.sleep(for: .milliseconds(250))
                fete.screenChanged(for: scene, screen: screen)
            }
            // Played to the end on a clear screen: done. Cut, it waits to replay or is over; the loop asks again.
            if fete.isPlaying(in: scene) { fete.finish() }
        }
    }
}

/// The bust and the fireworks over a soft dimming of the screen; redrawn every frame only while it plays (one view per run). A
/// tap anywhere in the band ends it (THEMES.md §4 rule 3). Decorative: hidden from VoiceOver. On a dark scheme the bursts get a
/// light rim: about half of their opaque pixels (the dark outlines of the art) measure under 3:1 on black (rule 7).
struct FeteNationaleScene: View {
    let area: CGSize
    let close: () -> Void
    /// The moment drawn, from the start of the run; the previews and the screenshots freeze it.
    var frozenAt: Double?
    @State private var begin = Date()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: frozenAt != nil)) { timeline in
                let progress = frozenAt ?? timeline.date.timeIntervalSince(begin) / FeteNationaleModel.duration
                let presence = FeteNationaleLayout.presence(at: progress)
                ZStack {
                    // Dimming helps the light screens; on a dark one it would only darken the strokes (rule 7).
                    Color.black.opacity((scheme == .dark ? 0 : 0.35) * presence)
                    ForEach(FeteNationaleLayout.bursts, id: \.start) { burst in
                        if let state = FeteNationaleLayout.state(of: burst, at: progress) {
                            let side = FeteNationaleLayout.burstSide(size: burst.size, in: area)
                            Image(burst.variant.rawValue)
                                .resizable()
                                .scaledToFit()
                                .frame(width: side, height: side)
                                .scaleEffect(state.scale)
                                .opacity(state.opacity)
                                .shadow(color: scheme == .dark ? .white.opacity(0.85) : .clear, radius: 1.5)
                                .position(x: area.width * burst.centre.x, y: area.height * burst.centre.y)
                        }
                    }
                    bust(presence: presence)
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

    private func bust(presence: Double) -> some View {
        VStack(spacing: 12) {
            Image("FeteMarianne")
                .resizable()
                .scaledToFit()
                .frame(height: FeteNationaleLayout.bustHeight(band: area.height))
            Text(FeteNationaleLayout.text)
                .font(.title2.bold())
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
        }
        .opacity(presence)
        .offset(y: (1 - presence) * 24)
        .position(x: area.width / 2, y: area.height / 2)
    }
}
