import Foundation
import HFRModels
import HFRParsing
import Testing
@testable import HFRClient

/// The page-by-page search of the MP list (`MPStorage.m:692-736`), driven with pager values; the captured page 1 → page 2
/// walk (`R333a`, `R333b`, #333) is in `MPStorageTransportReadTests`.
struct MPStorageListWalkTests {
    static let first = URL(string: "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1")
        ?? URL(fileURLWithPath: "/")

    static func page(_ current: Int, next: String?, candidates: [Int] = []) -> MPStorageThreadSearch {
        MPStorageThreadSearch(
            candidates: candidates, navigation: PageNavigation(current: current, last: current + 1, nextPath: next)
        )
    }

    /// Serves `pages` in order and records the URLs asked.
    actor Pages {
        private var pages: [MPStorageThreadSearch]
        private(set) var asked: [URL] = []

        init(_ pages: [MPStorageThreadSearch]) { self.pages = pages }

        func next(_ url: URL) -> MPStorageThreadSearch {
            asked.append(url)
            return pages.isEmpty ? MPStorageThreadSearch(candidates: [], navigation: PageNavigation()) : pages.removeFirst()
        }
    }

    /// Records the candidates asked about; the account's threads are `accepted`.
    actor Checks {
        let accepted: Set<Int>
        private(set) var asked: [Int] = []

        init(accepting accepted: Set<Int>) { self.accepted = accepted }

        func check(_ post: Int) -> Bool {
            asked.append(post)
            return accepted.contains(post)
        }
    }

    static func walk(
        _ pages: Pages, maximumPages: Int = 50, checks: Checks = Checks(accepting: [42])
    ) async -> Result<Int?, MPStorageTransportError> {
        do throws(MPStorageTransportError) {
            return .success(try await MPStorageTransport.walk(
                from: first, maximumPages: maximumPages, fetch: { url in await pages.next(url) },
                isAccountThread: { post in await checks.check(post) }
            ))
        } catch {
            return .failure(error)
        }
    }

    @Test func followsTheNextPageUntilTheThread() async throws {
        let pages = Pages([
            Self.page(1, next: "/forum1.php?config=hfr.inc&cat=prive&page=2"),
            Self.page(2, next: "/forum1.php?config=hfr.inc&cat=prive&page=3"),
            Self.page(3, next: nil, candidates: [42])
        ])
        #expect(try await Self.walk(pages).get() == 42)
        #expect(await pages.asked.map(\.absoluteString) == [
            Self.first.absoluteString,
            "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2",
            "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=3"
        ])
    }

    @Test("#1200 P1: candidates that are not the account's are skipped, on the page and on the next ones, in list order")
    func skipsCandidatesThatAreNotTheAccountsThread() async throws {
        let pages = Pages([
            Self.page(1, next: "/forum1.php?config=hfr.inc&cat=prive&page=2", candidates: [7, 8]),
            Self.page(2, next: "/forum1.php?config=hfr.inc&cat=prive&page=3", candidates: [9, 42, 43])
        ])
        let checks = Checks(accepting: [42, 43])
        #expect(try await Self.walk(pages, checks: checks).get() == 42)
        #expect(await checks.asked == [7, 8, 9, 42])
        #expect(await pages.asked.count == 2)
    }

    @Test("#1200 P1: a list whose only storage-subject rows are other members' threads has no storage thread")
    func onlyForeignCandidatesIsNotFound() async throws {
        let pages = Pages([Self.page(1, next: nil, candidates: [7, 8])])
        let checks = Checks(accepting: [42])
        #expect(try await Self.walk(pages, checks: checks).get() == nil)
        #expect(await checks.asked == [7, 8])
    }

    @Test func theLastPageWithoutTheThreadIsNotFound() async throws {
        let pages = Pages([Self.page(1, next: "/forum1.php?config=hfr.inc&cat=prive&page=2"), Self.page(2, next: nil)])
        #expect(try await Self.walk(pages).get() == nil)
    }

    @Test func aPagerThatDoesNotMoveOnStops() async throws {
        let pages = Pages([
            Self.page(1, next: "/forum1.php?config=hfr.inc&cat=prive&page=2"),
            Self.page(1, next: "/forum1.php?config=hfr.inc&cat=prive&page=2")
        ])
        #expect(await Self.walk(pages) == .failure(.unexpectedPage))
        #expect(await pages.asked.count == 2)
    }

    @Test(arguments: ["https://www.hardware.fr/forum1.php?page=2", "http://forum.hardware.fr:8080/forum1.php?page=2", "//evil.example/x"])
    func aNextLinkOffTheForumIsNotFollowed(next: String) async throws {
        let pages = Pages([Self.page(1, next: next)])
        #expect(await Self.walk(pages) == .failure(.unexpectedPage))
        #expect(await pages.asked.count == 1)
    }

    @Test("#1200 P5: an http next link on the forum is followed over https, never in clear")
    func anHTTPNextLinkIsFollowedOverHTTPS() async throws {
        let pages = Pages([
            Self.page(1, next: "http://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2"), Self.page(2, next: nil)
        ])
        #expect(try await Self.walk(pages).get() == nil)
        #expect(await pages.asked.last?.absoluteString == "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2")
    }

    @Test func stopsAtTheLimitWithoutSayingNotFound() async throws {
        let pages = Pages((1...5).map { Self.page($0, next: "/forum1.php?config=hfr.inc&cat=prive&page=\($0 + 1)") })
        #expect(await Self.walk(pages, maximumPages: 3) == .failure(.searchLimitReached(pages: 3)))
        #expect(await pages.asked.count == 3)
    }
}
