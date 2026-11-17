import Foundation
import HFRClient
@testable import SwiftHFR
import Testing

/// LOT-140: where a tap leads (GAP-011) and what a notification carries.
@MainActor
struct MPNotificationRoutingTests {
    @Test("A conversation's notification carries the legacy destination and its number, and reads back as that conversation")
    func conversationRoundTrip() {
        let info = MPNotificationDestination(topic: 42).userInfo
        #expect(info["destination"] as? String == "messages")
        #expect(info["mpTopic"] as? Int == 42)
        #expect(MPNotificationDestination(userInfo: info) == .thread(42))
        // As the system hands it back (an NSNumber).
        #expect(MPNotificationDestination(userInfo: ["destination": "messages", "mpTopic": NSNumber(value: 42)]) == .thread(42))
    }

    @Test("A summary opens the list; so does a legacy notification without a destination; another kind opens nothing")
    func otherNotifications() {
        #expect(MPNotificationDestination(topic: nil) == .list)
        #expect(MPNotificationDestination(userInfo: MPNotificationDestination.list.userInfo) == .list)
        #expect(MPNotificationDestination(userInfo: [:]) == .list)
        #expect(MPNotificationDestination(userInfo: ["destination": "messages", "mpTopic": 0]) == .list)
        #expect(MPNotificationDestination(userInfo: ["destination": "aq"]) == nil)
    }

    @Test("The system content: title, body, thread, category, sound, never time-sensitive, and the tap's destination")
    func systemContent() {
        let content = MPNotificationCenter.content(MPNotificationContent(
            identifier: "mp-7", threadIdentifier: "mp-7", title: "pseudo7", body: "Sujet 7", topic: 7
        ))
        #expect(content.title == "pseudo7")
        #expect(content.body == "Sujet 7")
        #expect(content.threadIdentifier == "mp-7")
        #expect(content.categoryIdentifier == MPNotificationCenter.categoryIdentifier)
        #expect(content.sound != nil)
        #expect(content.interruptionLevel == .active)
        #expect(MPNotificationDestination(userInfo: content.userInfo) == .thread(7))
    }

    @Test("A tap is held until the root takes it, once; a later tap replaces an earlier one")
    func router() {
        let router = MPNotificationRouter()
        #expect(router.consume() == nil)
        router.receive(.list)
        router.receive(.thread(3))
        #expect(router.pending == .thread(3))
        #expect(router.consume() == .thread(3))
        #expect(router.consume() == nil)
    }

    @Test("The earliest date of the next check is the chosen interval after now; Jamais schedules nothing")
    func schedule() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(MPBackgroundScheduler.earliestBeginDate(for: .thirtyMinutes, now: now) == now.addingTimeInterval(1800))
        #expect(MPBackgroundScheduler.earliestBeginDate(for: .fourHours, now: now) == now.addingTimeInterval(14_400))
        #expect(MPBackgroundScheduler.earliestBeginDate(for: .never, now: now) == nil)
        #expect(MPBackgroundScheduler.taskIdentifier == "com.hfrplus.refresh_mp")
    }
}
