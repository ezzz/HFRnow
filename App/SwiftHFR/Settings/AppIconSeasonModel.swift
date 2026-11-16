import HFRStorage
import Observation
import SwiftUI

/// The "Revenir à l'icône précédente ?" question (#730, decision Q4 of 2026-10-28): a dated icon stays after its window, because
/// a switch must be the user's, so the first launch after the window asks once whether to go back.
@MainActor
@Observable
final class AppIconSeasonModel {
    /// What the alert shows: the dated icon still active and the one a Yes goes back to.
    struct Question: Equatable, Sendable {
        let dated: AppIconOption
        let previous: AppIconOption
    }

    /// The pending question, nil when there is none.
    private(set) var question: Question?
    /// The French message of a refused « Oui », nil otherwise; the question comes back at the next launch.
    var errorMessage: String?

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let switcher: any AlternateIconSwitching
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    init(
        store: any SettingsStore,
        switcher: any AlternateIconSwitching = SystemAlternateIconSwitcher(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.switcher = switcher
        self.calendar = calendar
        self.now = now
    }

    /// At launch: sets `question` when a dated icon is active after its window and this window was not answered yet.
    func checkAtLaunch() {
        question = nil
        guard switcher.supportsAlternateIcons else { return }
        let option = AppIconOption.current(store: store, switcher: switcher)
        guard let window = option.window, !window.contains(now(), calendar: calendar),
              store.value(for: SettingKey.appIconRevertAsked) != token(option, window) else { return }
        let previous = store.value(for: SettingKey.appIconPrevious).flatMap(AppIconOption.init(rawValue:))
        question = Question(dated: option, previous: previous.flatMap { $0.window == nil ? $0 : nil } ?? .superblue)
    }

    /// "Garder": the icon stays and this window is not asked about again.
    func keep() {
        guard let question else { return }
        markAsked(question.dated)
        self.question = nil
    }

    /// "Oui": applies the previous icon through the system (the user's own answer); a refusal leaves the icon and asks again next
    /// launch.
    func revert() async {
        guard let asked = question else { return }
        question = nil
        do {
            try await switcher.setAlternateIconName(asked.previous.alternateIconName)
        } catch {
            errorMessage = "Impossible de changer l’icône : \(error.localizedDescription)"
            return
        }
        store.set(asked.previous.rawValue, for: SettingKey.appIconName)
        store.set(nil, for: SettingKey.appIconPrevious)
        markAsked(asked.dated)
    }

    private func markAsked(_ option: AppIconOption) {
        guard let window = option.window else { return }
        store.set(token(option, window), for: SettingKey.appIconRevertAsked)
    }

    /// `<icon>:<year the window last ended>`: one answer per season, whatever the launch date after it.
    private func token(_ option: AppIconOption, _ window: IconWindow) -> String {
        "\(option.rawValue):\(window.lastEndYear(before: now(), calendar: calendar))"
    }
}

extension View {
    /// Shows the dated-icon question of `model` as an alert and runs the check once the view appears (at launch).
    func appIconSeasonAlert(_ model: AppIconSeasonModel) -> some View {
        modifier(AppIconSeasonAlert(model: model))
    }
}

private struct AppIconSeasonAlert: ViewModifier {
    let model: AppIconSeasonModel

    func body(content: Content) -> some View {
        content
            .task { model.checkAtLaunch() }
            .alert(
                "Icône",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert(
                "Revenir à l’icône précédente ?",
                isPresented: Binding(get: { model.question != nil }, set: { _ in }),
                presenting: model.question
            ) { _ in
                Button("Oui") { Task { await model.revert() } }
                Button("Garder", role: .cancel) { model.keep() }
            } message: { question in
                Text(
                    "L’icône « \(question.dated.title) » est une icône de saison, qui s’est terminée. "
                        + "Revenir à « \(question.previous.title) » ?"
                )
            }
    }
}
