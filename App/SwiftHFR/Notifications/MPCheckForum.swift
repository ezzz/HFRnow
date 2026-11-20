import HFRClient
import HFRModels
import HFRNetwork

/// What one background check read from the forum for an account (LOT-140).
struct MPForumReading: Sendable, Equatable {
    /// The unread private messages count of the home page (LOT-047); nil is "no information" (logged out, an unknown
    /// page, an expired session or a failure), never 0.
    var count: Int?
    /// Page 1 of the MP list; nil when it could not be read, or when the count was not read (it is not asked for then).
    var page: PrivateMessageListPage?
}

/// The forum side of the background check: the seam its tests replace.
protocol MPCheckForum: Sendable {
    /// Reads the count, then page 1 of the list when there is a count, as `account`.
    func read(as account: Account) async -> MPForumReading
}

/// The live forum side: `MPUnreadPoll` (LOT-047), then `PageFetcher.privateMessages(page: 1)` (LOT-045) parsed by
/// `PrivateMessageListParser` (LOT-023). At most two requests, never a thread page (E25).
///
/// The session is built from the stored cookies and token for this run only: what the answers set is written back nowhere,
/// so a run that overlaps a login or a session refresh in the app never undoes it (LOT-047 D3).
struct LiveMPCheckForum: MPCheckForum {
    func read(as account: Account) async -> MPForumReading {
        let session = HFRSession(cookies: account.cookies, hashCheck: account.hashCheck)
        let count: Int?
        // DO NOT MERGE (#1276): the MP count poll.
        T1276.log("mp poll start")
        defer { T1276.log("mp poll end") }
        do throws(MPUnreadPollError) {
            count = try await MPUnreadPoll(session: session).unreadCount()
        } catch {
            // An expired session, a maintenance page or a network failure: no information (#230 acceptance).
            return MPForumReading()
        }
        guard let count else { return MPForumReading() }
        let source = LivePrivateMessageSource(
            fetcher: PageFetcher(session: session), storagePost: LivePrivateMessageSource.locatedStoragePost(of: account.pseudo)
        )
        let page = try? await source.privateMessages(page: 1)
        return MPForumReading(count: count, page: page)
    }
}
