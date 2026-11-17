import BackgroundTasks
import Foundation
import HFRStorage
import OSLog

// Port of HFRswift/Swift/MPBackgroundService.swift (taskIdentifier, scheduleAppRefresh) @ 87fe0d1c. Differences: the
// earliest date is the "Vérifier les messages" interval instead of 60 s, and Jamais cancels the request; the handler is
// SwiftUI's `.backgroundTask(.appRefresh)` in `SwiftHFRApp` instead of `BGTaskScheduler.register` (GAP-190).
/// Schedules the background MP check (LOT-140).
enum MPBackgroundScheduler {
    /// The legacy identifier (`MPBackgroundService.swift:15`, `HFRswift/Info.plist:5-8`), in `Info-Keys.plist` too.
    static let taskIdentifier = "com.hfrplus.refresh_mp"

    private static let log = Logger(subsystem: "SwiftHFR", category: "MPBackgroundScheduler")

    /// The earliest date of the next check, or nil for Jamais (operator: a minimum, iOS picks the real moment).
    static func earliestBeginDate(for interval: MPCheckInterval, now: Date) -> Date? {
        interval.seconds.map(now.addingTimeInterval)
    }

    /// Submits the next check per the setting, replacing a pending one; cancels it for Jamais.
    static func schedule(settings: any SettingsStore = UserDefaultsSettingsStore(), now: Date = .now) async {
        guard let date = earliestBeginDate(for: settings.value(for: SettingKey.mpCheckInterval), now: now) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = date
        do {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } catch {
            // The simulator, or background refresh turned off for the app: nothing to tell the member here.
            log.error("Background MP check not scheduled")
        }
    }
}
