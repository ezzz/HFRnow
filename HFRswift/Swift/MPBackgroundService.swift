//
//  MPBackgroundService.swift
//  HFRswift
//
//  Background MP check: Swift port of ObjC checkForNewMP / scheduleAppRefresh.
//

import BackgroundTasks
import UserNotifications
import Foundation

final class MPBackgroundService {

    static let shared = MPBackgroundService()
    static let taskIdentifier = "com.hfrplus.refresh_mp"

    private init() {}

    // MARK: - Registration (call before applicationDidFinishLaunching returns)

    func registerBGTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: .main) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task {
                await MPBackgroundService.shared.performBackgroundCheck(task: refreshTask)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set(0, forKey: "nb_mp_failure")
        } catch {
            print("MPBackgroundService: failed to submit task — \(error)")
        }
    }

    // MARK: - Permission

    func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            print("MPBackgroundService: notification authorization error — \(error)")
        }
    }

    // MARK: - App icon badge

    func updateAppIconBadge(count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            print("MPBackgroundService: badge update error — \(error)")
        }
    }

    // MARK: - Background check

    private func performBackgroundCheck(task: BGAppRefreshTask) async {
        scheduleAppRefresh()

        let oldFailureCount = UserDefaults.standard.integer(forKey: "nb_mp_failure")
        UserDefaults.standard.set(oldFailureCount + 1, forKey: "nb_mp_failure")

        task.expirationHandler = {
            print("MPBackgroundService: task expired")
        }

        guard let url = URL(string: "https://forum.hardware.fr") else {
            task.setTaskCompleted(success: false)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            if let html = String(data: data, encoding: .utf8),
               let newCount = extractMPCount(from: html) {

                var oldCount = UserDefaults.standard.integer(forKey: "nb_mp")
                if oldCount > 1000 || oldCount < 0 { oldCount = 0 }

                UserDefaults.standard.set(oldFailureCount, forKey: "nb_mp_failure")
                UserDefaults.standard.set(newCount, forKey: "nb_mp")

                if newCount > oldCount {
                    await scheduleNotification(text: "Vous avez un nouveau message privé")
                }
            }
        } catch {
            print("MPBackgroundService: network error — \(error)")
        }

        task.setTaskCompleted(success: true)
    }

    // MARK: - HTML parsing

    private func extractMPCount(from html: String) -> Int? {
        // Find the unread MP count in the "cCatTopic red" element, matching the
        // ObjC legacy approach (HTMLParser + regex "[^.0-9]+([0-9]{1,})[^.0-9]+").
        guard let nodeRegex = try? NSRegularExpression(
            pattern: #"class=[\"']cCatTopic red[\"'][^>]*>(.*?)<"#,
            options: .dotMatchesLineSeparators
        ) else { return nil }

        let nsHTML = html as NSString
        guard
            let nodeMatch = nodeRegex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
            nodeMatch.numberOfRanges >= 2,
            let textRange = Range(nodeMatch.range(at: 1), in: html)
        else { return nil }

        let text = String(html[textRange])

        // Extract the first integer from the text content.
        guard let numRegex = try? NSRegularExpression(pattern: #"(\d+)"#),
              let numMatch = numRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(numMatch.range(at: 1), in: text)
        else { return nil }

        return Int(text[numRange])
    }

    // MARK: - Notification

    private func scheduleNotification(text: String) async {
        let content = UNMutableNotificationContent()
        content.body = text
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("MPBackgroundService: notification scheduling error — \(error)")
        }
    }
}
