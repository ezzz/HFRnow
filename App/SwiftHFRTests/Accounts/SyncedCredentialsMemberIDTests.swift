import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing

/// #1420: adopting another device's copy of an account (LOT-173) never takes away the `md_id` this session holds for the same
/// member: only a login sets it (`W1420a`) and HFR refuses profiles without it (`R1420c`). Nothing is sent: jars only.
struct SyncedCredentialsMemberIDTests {
    private static let tomorrow = Date().addingTimeInterval(86_400)

    private static func cookie(_ name: String, _ value: String, expires: Date = tomorrow) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr", expiresDate: expires)
    }

    /// The jar a login left (`W1420a`): `md_user`, `md_passs`, `md_id`.
    private static func loggedIn(_ user: String = "user1") -> HFRSession {
        HFRSession(cookies: [cookie("md_user", user), cookie("md_passs", "local-pass"), cookie("md_id", "900001")])
    }

    private static func pairs(_ session: HFRSession) async -> [String] {
        await session.cookies().map { "\($0.name)=\($0.value)" }
    }

    /// A copy without `md_id` (another device's legacy import, or its login past 30 days), or listing it expired.
    @Test(arguments: [[StoredCookie](), [cookie("md_id", "900001", expires: Date().addingTimeInterval(-60))]])
    func aCopyOfTheSameMemberWithoutMemberIDKeepsTheJars(extra: [StoredCookie]) async {
        let session = Self.loggedIn()
        let copy = [Self.cookie("md_user", "user1"), Self.cookie("md_passs", "synced-pass")] + extra
        await session.adoptSyncedCredentials(cookies: copy, hashCheck: "synced-hash")
        #expect(await Self.pairs(session) == ["md_id=900001", "md_passs=synced-pass", "md_user=user1"])
        #expect(await session.profileLoginState().hasMemberID)
        #expect(await session.hashCheck == "synced-hash")
    }

    @Test func aCopyWithItsOwnMemberIDWins() async {
        let session = Self.loggedIn()
        let copy = [Self.cookie("md_user", "user1"), Self.cookie("md_passs", "synced-pass"), Self.cookie("md_id", "900009")]
        await session.adoptSyncedCredentials(cookies: copy, hashCheck: nil)
        #expect(await Self.pairs(session) == ["md_id=900009", "md_passs=synced-pass", "md_user=user1"])
    }

    /// Another member's copy is taken as it is: the jar's `md_id` is not theirs.
    @Test func aCopyOfAnotherMemberTakesNoMemberID() async {
        let session = Self.loggedIn("user1")
        await session.adoptSyncedCredentials(
            cookies: [Self.cookie("md_user", "user2"), Self.cookie("md_passs", "synced-pass")], hashCheck: nil
        )
        #expect(await Self.pairs(session) == ["md_passs=synced-pass", "md_user=user2"])
        #expect(await !session.profileLoginState().hasMemberID)
    }
}
