import Foundation
import HFRModels

/// Fetches the raw HTML of the forum pages: no parsing, no flows.
///
/// Two transports: the account's session and a cookie-less one. Topic pages default to the cookie-less one because an
/// authenticated GET marks the topic's flags read (HFR-PROTOCOL §7, E25), which prefetch must never do; every other page
/// defaults to the session. Pass `identity` to override either way, for example to read a topic as the user.
/// Cancelling the calling task cancels the exchange and throws `NetworkError.cancelled`.
public struct PageFetcher: Sendable {
    private let session: any HTTPTransport
    private let anonymous: any HTTPTransport

    /// Creates a fetcher from the account's session and a cookie-less transport.
    public init(session: any HTTPTransport, anonymous: any HTTPTransport = AnonymousTransport()) {
        self.session = session
        self.anonymous = anonymous
    }

    /// R1: the home page (forum list, `hash_check`, private message count).
    public func home(as identity: FetchIdentity = .authenticated) async throws(NetworkError) -> RawPage {
        try await fetch(HFREndpoint.home, identity)
    }

    /// R2: the topic list of a forum.
    public func topicList(
        category: CategoryID, filter: TopicListFilter = .all, page: Int = 1, as identity: FetchIdentity = .authenticated
    ) async throws(NetworkError) -> RawPage {
        try await fetch({ try HFREndpoint.topicList(category: category, filter: filter, page: page) }, identity)
    }

    /// R3: favourites across forums.
    public func favorites(
        filter: TopicListFilter = .favorites, as identity: FetchIdentity = .authenticated
    ) async throws(NetworkError) -> RawPage {
        try await fetch({ try HFREndpoint.favorites(filter: filter) }, identity)
    }

    /// R4: the private message list.
    public func privateMessages(page: Int = 1, as identity: FetchIdentity = .authenticated) async throws(NetworkError) -> RawPage {
        try await fetch({ try HFREndpoint.privateMessages(page: page) }, identity)
    }

    /// R5: one topic page through `forum2.php`; the final URL after the redirect is the canonical page.
    ///
    /// Anonymous by default (prefetch). Ask for `.authenticated` only when the user is reading the topic.
    public func topicPage(
        topic: TopicID, page: Int = 1, as identity: FetchIdentity = .anonymous
    ) async throws(NetworkError) -> FetchedTopicPage {
        let raw = try await fetch({ try HFREndpoint.topicPage(topic: topic, page: page) }, identity)
        return FetchedTopicPage(page: raw, requestedPage: page)
    }

    /// R9: the public profile of a member.
    public func profile(memberID: Int, as identity: FetchIdentity = .authenticated) async throws(NetworkError) -> RawPage {
        try await fetch({ try HFREndpoint.publicProfile(memberID: memberID) }, identity)
    }

    /// R7: the smiley search (3 characters at least).
    public func smileySearch(
        _ text: String, requireAll: Bool = false, as identity: FetchIdentity = .authenticated
    ) async throws(NetworkError) -> RawPage {
        try await fetch({ try HFREndpoint.smileySearch(text, requireAll: requireAll) }, identity)
    }

    private func fetch(_ build: () throws -> HTTPRequest, _ identity: FetchIdentity) async throws(NetworkError) -> RawPage {
        let request: HTTPRequest
        do {
            request = try build()
        } catch let error as NetworkError {
            throw error
        } catch {
            throw .invalidRequest(reason: "request could not be built")
        }
        // The transports honour cancellation while waiting; this also stops a task cancelled before it starts.
        if Task.isCancelled { throw .cancelled }
        let transport = identity == .anonymous ? anonymous : session
        return RawPage(response: try await transport.send(request))
    }
}

/// A topic page with the page number HFR resolved.
public struct FetchedTopicPage: Sendable, Equatable {
    /// The page as fetched; `finalURL` is the canonical URL.
    public let page: RawPage
    /// Topic and page read from the final URL; nil when the redirect did not lead to a `sujet_<post>_<page>.htm` URL.
    public let location: TopicPageLocation?
    /// The page asked for, which HFR may have changed (for example a page past the end).
    public let requestedPage: Int

    /// Creates a fetched topic page, reading the location from `page.finalURL`.
    public init(page: RawPage, requestedPage: Int) {
        self.page = page
        self.location = TopicPageLocation(url: page.finalURL)
        self.requestedPage = requestedPage
    }
}
