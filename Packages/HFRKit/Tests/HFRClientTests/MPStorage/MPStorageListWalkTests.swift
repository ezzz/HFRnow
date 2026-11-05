import Foundation
import HFRModels
import HFRParsing
import Testing
@testable import HFRClient

/// The page-by-page search of the MP list (`MPStorage.m:692-736`). No capture has an MP list past page 1 (#333), so the
/// walk is driven with pager values, not pages.
struct MPStorageListWalkTests {
    static let first = URL(string: "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1")
        ?? URL(fileURLWithPath: "/")

    static func page(_ current: Int, next: String?) -> MPStorageThreadSearch {
        .notOnPage(navigation: PageNavigation(current: current, last: current + 1, nextPath: next))
    }

    /// Serves `pages` in order and records the URLs asked.
    actor Pages {
        private var pages: [MPStorageThreadSearch]
        private(set) var asked: [URL] = []

        init(_ pages: [MPStorageThreadSearch]) { self.pages = pages }

        func next(_ url: URL) -> MPStorageThreadSearch {
            asked.append(url)
            return pages.isEmpty ? .notOnPage(navigation: PageNavigation()) : pages.removeFirst()
        }
    }

    static func walk(_ pages: Pages, maximumPages: Int = 50) async -> Result<Int?, MPStorageTransportError> {
        do throws(MPStorageTransportError) {
            return .success(try await MPStorageTransport.walk(from: first, maximumPages: maximumPages) { url in
                await pages.next(url)
            })
        } catch {
            return .failure(error)
        }
    }

    @Test func followsTheNextPageUntilTheThread() async throws {
        let pages = Pages([
            Self.page(1, next: "/forum1.php?config=hfr.inc&cat=prive&page=2"),
            Self.page(2, next: "/forum1.php?config=hfr.inc&cat=prive&page=3"),
            .found(post: 42)
        ])
        #expect(try await Self.walk(pages).get() == 42)
        #expect(await pages.asked.map(\.absoluteString) == [
            Self.first.absoluteString,
            "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2",
            "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=3"
        ])
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

    @Test(arguments: ["https://www.hardware.fr/forum1.php?page=2", "http://forum.hardware.fr/forum1.php?page=2", "//evil.example/x"])
    func aNextLinkOffTheForumIsNotFollowed(next: String) async throws {
        let pages = Pages([Self.page(1, next: next)])
        #expect(await Self.walk(pages) == .failure(.unexpectedPage))
        #expect(await pages.asked.count == 1)
    }

    @Test func stopsAtTheLimitWithoutSayingNotFound() async throws {
        let pages = Pages((1...5).map { Self.page($0, next: "/forum1.php?config=hfr.inc&cat=prive&page=\($0 + 1)") })
        #expect(await Self.walk(pages, maximumPages: 3) == .failure(.searchLimitReached(pages: 3)))
        #expect(await pages.asked.count == 3)
    }
}
