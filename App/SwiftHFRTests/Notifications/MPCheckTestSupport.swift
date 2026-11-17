import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR

/// A scripted forum side: each read answers the next reading, and is recorded.
final class FakeMPCheckForum: MPCheckForum, @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [MPForumReading]
    private var accounts: [String] = []

    init(_ readings: [MPForumReading]) { self.readings = readings }

    /// Pseudos of the accounts read, in order.
    var reads: [String] { lock.withLock { accounts } }

    func read(as account: Account) async -> MPForumReading {
        lock.withLock {
            accounts.append(account.pseudo)
            return readings.isEmpty ? MPForumReading() : readings.removeFirst()
        }
    }
}

/// Records what the check shows.
actor FakeMPDelivery: MPNotificationDelivering {
    private(set) var delivered: [MPNotificationContent] = []
    private(set) var badges: [Int] = []
    private(set) var withdrawn: [String] = []
    /// What `setBadge` answers: false while iOS would not show the badge (no permission yet).
    private(set) var badgeAllowed: Bool

    init(badgeAllowed: Bool = true) { self.badgeAllowed = badgeAllowed }

    func deliver(_ content: MPNotificationContent) { delivered.append(content) }
    func withdraw(_ identifier: String) { withdrawn.append(identifier) }
    func setBadge(_ count: Int) -> Bool {
        badges.append(count)
        return badgeAllowed
    }

    func allowBadge() { badgeAllowed = true }
}

/// An MP list page 1 with the given unread and read conversations (numbers), one-to-one unless listed in `groups`.
func mpPage(unread: [Int], read: [Int] = [], groups: Set<Int> = []) -> PrivateMessageListPage {
    PrivateMessageListPage(
        threads: unread.map { messageThread($0, unread: true, group: groups.contains($0)) }
            + read.map { messageThread($0, unread: false, group: groups.contains($0)) }
    )
}
