import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage

/// What the Messages screen needs from the forum: one page of the private message list, fetched and parsed.
protocol PrivateMessageSource: Sendable {
    /// Page `page` (1-based) of the member's private message list.
    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage
}

/// The live source: `PageFetcher.privateMessages` (LOT-045) with the account's session, then `PrivateMessageListParser` (LOT-023).
///
/// The account's MPStorage thread is removed from the page (#1074): the one its storage sync located, never another row
/// with the same subject (#1200 P1).
///
/// Only the list is fetched: no thread page, so nothing is marked read here.
struct LivePrivateMessageSource: PrivateMessageSource {
    let fetcher: PageFetcher
    /// The account's storage thread as its MPStorage sync last located it (a thread whose first message is the account's,
    /// `MPStorageTransport`); nil when none is known, and then no row is hidden.
    let storagePost: @Sendable () async -> Int?

    /// The thread the MPStorage sync of `account` cached in the device copies (LOT-130); nil without an account.
    static func locatedStoragePost(of account: String?) -> @Sendable () async -> Int? {
        {
            guard let account else { return nil }
            return await MPStorageCopyPersistence.liveStore.copy(for: account)?.post
        }
    }

    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage {
        let raw: RawPage
        do throws(NetworkError) {
            raw = try await fetcher.privateMessages(page: page)
        } catch {
            throw ListLoadError(error)
        }
        do throws(ListPageFailure) {
            // The MPStorage thread is a technical store, not a conversation: it stays out of the list and of every count
            // read from it (#1074). The storage flows fetch and scan the list themselves, so they still find it. Only the
            // located thread is hidden: any member can send an MP with the storage subject (#1200 P1).
            let page = try PrivateMessageListParser.parse(raw.text, pageURL: raw.finalURL.absoluteString)
            return page.hidingStorageThread(post: await storagePost())
        } catch {
            throw ListLoadError(error)
        }
    }
}

/// A source with no forum behind it (previews and tests that never list messages).
struct UnavailablePrivateMessages: PrivateMessageSource {
    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage { throw .other }
}
