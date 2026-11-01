import HFRModels
import HFRNetwork
import HFRParsing

/// What the Messages screen needs from the forum: one page of the private message list, fetched and parsed.
protocol PrivateMessageSource: Sendable {
    /// Page `page` (1-based) of the member's private message list.
    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage
}

/// The live source: `PageFetcher.privateMessages` (LOT-045) with the account's session, then `PrivateMessageListParser` (LOT-023).
///
/// Only the list is fetched: no thread page, so nothing is marked read here.
struct LivePrivateMessageSource: PrivateMessageSource {
    let fetcher: PageFetcher

    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage {
        let raw: RawPage
        do throws(NetworkError) {
            raw = try await fetcher.privateMessages(page: page)
        } catch {
            throw ListLoadError(error)
        }
        do throws(ListPageFailure) {
            return try PrivateMessageListParser.parse(raw.text, pageURL: raw.finalURL.absoluteString)
        } catch {
            throw ListLoadError(error)
        }
    }
}

/// A source with no forum behind it (previews and tests that never list messages).
struct UnavailablePrivateMessages: PrivateMessageSource {
    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage { throw .other }
}
