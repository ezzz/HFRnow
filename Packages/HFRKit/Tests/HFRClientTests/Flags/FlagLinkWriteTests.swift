import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// `addflag.php` and `delflag.php`: the captured answers (`P03a`, `P03b`, `P03d`) through the real flow entry point.
@Suite("Flag link writes")
struct FlagLinkWriteTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)

    /// Runs `action` on `link`, answered by `reply`.
    static func run(
        _ action: TopicFlagAction, link: URL, reply: Result<HTTPResponse, NetworkError>?
    ) async -> (result: Result<TopicFlagResult, TopicFlagError>, requests: [HTTPRequest]) {
        let session = ScriptedFlagSession(reply.map { [$0] } ?? [])
        let result: Result<TopicFlagResult, TopicFlagError>
        do {
            result = .success(try await TopicFlagFlow().follow(action, link: link, through: session))
        } catch {
            result = .failure(error)
        }
        return (result, await session.requests)
    }

    @Test("The first addflag link of R21 is the link P03a requested")
    func r21LinkIsP03aRequest() throws {
        let links = try FlagCapture.links(in: "R21-topic-p1-logged-in", path: "/user/addflag.php")
        #expect(links.count == 40)
        #expect(links.first == (try FlagCapture.requestURL("P03a")))
        #expect(links.allSatisfy { FlagLink($0, path: "/user/addflag.php")?.topic == Self.cuisine })
        let removals = try FlagCapture.links(in: "R21-topic-p1-logged-in", path: "/user/delflag.php")
        #expect(removals.count == 1)
        #expect(removals.allSatisfy { FlagLink($0, path: "/user/delflag.php")?.topic == Self.cuisine })
    }

    @Test("addflag answered P03a or P03b is confirmed, after one GET of the link, redirects not followed", arguments: ["P03a", "P03b"])
    func addFavoriteConfirmed(answer: String) async throws {
        let link = try FlagCapture.requestURL(answer)
        let (result, requests) = await Self.run(.addFavorite, link: link, reply: try FlagCapture.page(answer))
        let confirmed = try result.get()
        #expect(confirmed.action == .addFavorite)
        #expect(confirmed.topic == Self.cuisine)
        #expect(confirmed.message == "Favori positionné avec succès")
        #expect(confirmed.refreshURL.absoluteString == "https://forum.hardware.fr/hfr/Discussions/Cuisine/liste_sujet-1.htm")
        #expect(requests.count == 1)
        #expect(requests.first?.method == .get)
        #expect(requests.first?.url == link)
        #expect(requests.first?.redirectPolicy == .doNotFollow)
        #expect(requests.first?.body == nil)
    }

    @Test(
        "delflag is confirmed by its sentence whatever owntopic chooses as refresh, and again with no flag left (P03o)",
        arguments: [
            ("P03d", "owntopic=3"),
            ("P03n", "/hfr/Discussions/Cuisine/liste_sujet-1.htm"),
            ("P03o", "/hfr/Discussions/Cuisine/liste_sujet-1.htm"),
            ("P03p", "owntopic=1")
        ]
    )
    func removeFlagConfirmed(answer: String, refresh: String) async throws {
        let link = try FlagCapture.requestURL(answer)
        let (result, requests) = await Self.run(.removeFlag, link: link, reply: try FlagCapture.page(answer))
        let confirmed = try result.get()
        #expect(confirmed.action == .removeFlag)
        #expect(confirmed.topic == FlagLink(link, path: "/user/delflag.php")?.topic)
        #expect(confirmed.message == "Drapeau effacé avec succès")
        #expect(confirmed.refreshURL.absoluteString.contains(refresh))
        #expect(requests.map(\.url) == [link])
    }

    @Test("A repeated delflag gets the same bytes as the first one: its success means \"no flag left\" (P03o = P03n)")
    func repeatedRemovalIsTheSameAnswer() throws {
        #expect(try Capture.page("P03o-delflag-again") == Capture.page("P03n-delflag-owntopic0-success"))
        #expect(try FlagCapture.requestURL("P03o") == FlagCapture.requestURL("P03n"))
    }

    @Test(
        "Another write's confirmation is not this write's",
        arguments: [
            (TopicFlagAction.addFavorite, "P03d", "Drapeau effacé avec succès"),
            (.addFavorite, "W18", "Le message a été marqué comme non lu avec succès"),
            (.removeFlag, "P03a", "Favori positionné avec succès"),
            (.removeFlag, "W18", "Le message a été marqué comme non lu avec succès"),
            (.removeFlag, "W15", "Votre message a été édité avec succès !")
        ]
    )
    func otherConfirmationIsUnexpected(action: TopicFlagAction, answer: String, sentence: String) async throws {
        let link = try FlagCapture.requestURL(action == .addFavorite ? "P03a" : "P03d")
        let (result, _) = await Self.run(action, link: link, reply: try FlagCapture.page(answer))
        #expect(result == .failure(.unconfirmed(.unexpectedConfirmation(message: sentence))))
    }

    @Test("Refusals and unknown pages are never a success")
    func refusals() async throws {
        let link = try FlagCapture.requestURL("P03a")
        let flood = await Self.run(.addFavorite, link: link, reply: try FlagCapture.page("W20a"))
        guard case .failure(.rejected(let message?)) = flood.result else {
            Issue.record("W20a: \(flood.result)")
            return
        }
        #expect(message.contains("flood"))
        let badToken = await Self.run(.addFavorite, link: link, reply: try FlagCapture.page("W17b"))
        guard case .failure(.rejected(let refusal?)) = badToken.result else {
            Issue.record("W17b: \(badToken.result)")
            return
        }
        #expect(refusal.hasPrefix("Une erreur est survenue lors de l'envoi des données"))
        let loggedOut = await Self.run(.addFavorite, link: link, reply: try FlagCapture.page("W17c"))
        #expect(loggedOut.result == .failure(.notLoggedIn))
        // R12 is a read page with a back link: a refusal by shape (LOT-037), never a success.
        let readPage = await Self.run(.addFavorite, link: link, reply: try FlagCapture.page("R12"))
        #expect(readPage.result == .failure(.rejected(message: "Aucun sujet que vous avez lu n'est connu")))
        for page in ["W01", "R21"] {
            let answer = await Self.run(.addFavorite, link: link, reply: try FlagCapture.page(page))
            guard case .failure(.unconfirmed(.unrecognizedAnswer)) = answer.result else {
                Issue.record("\(page): \(answer.result)")
                continue
            }
        }
    }

    @Test("A redirect is not HFR's confirmation, even with a confirmation body")
    func redirectIsUnconfirmed() async throws {
        let link = try FlagCapture.requestURL("P03a")
        var moved = try FlagCapture.response("P03a")
        moved.statusCode = 302
        moved.headers["Location"] = "/login.php"
        let (result, requests) = await Self.run(.addFavorite, link: link, reply: .success(moved))
        #expect(result == .failure(.unconfirmed(.unrecognizedAnswer(message: nil))))
        #expect(requests.count == 1)
    }

    @Test(
        "A failure after sending is unconfirmed; a request that could not be built is a plain failure",
        arguments: [
            (NetworkError.timedOut, TopicFlagError.unconfirmed(.transport(.timedOut))),
            (.offline, .unconfirmed(.transport(.offline))),
            (.cancelled, .unconfirmed(.transport(.cancelled))),
            (.invalidRequest(reason: "x"), .network(.invalidRequest(reason: "x")))
        ]
    )
    func transportFailures(failure: NetworkError, expected: TopicFlagError) async throws {
        let (result, requests) = await Self.run(.addFavorite, link: try FlagCapture.requestURL("P03a"), reply: .failure(failure))
        #expect(result == .failure(expected))
        #expect(requests.count == 1)
    }

    @Test("An HTTP error status is unconfirmed: the GET reached HFR")
    func httpStatusIsUnconfirmed() async throws {
        let link = try FlagCapture.requestURL("P03d")
        let failed = HTTPResponse(statusCode: 500, url: link)
        let (result, _) = await Self.run(.removeFlag, link: link, reply: .success(failed))
        #expect(result == .failure(.unconfirmed(.transport(.httpStatus(code: 500, url: link)))))
    }

    @Test("A cancelled task sends nothing")
    func cancelledBeforeSending() async throws {
        let link = try FlagCapture.requestURL("P03a")
        let session = ScriptedFlagSession([try FlagCapture.page("P03a")])
        let task = Task { () async -> TopicFlagError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(TopicFlagError) {
                _ = try await TopicFlagFlow().follow(.addFavorite, link: link, through: session)
                return nil
            } catch {
                return error
            }
        }
        #expect(await task.value == .network(.cancelled))
        #expect(await session.requests.isEmpty)
    }

    @Test("A fragment is dropped from the requested link")
    func fragmentDropped() async throws {
        let link = try FlagCapture.requestURL("P03a")
        let withFragment = try FlagCapture.url(link.absoluteString + "#t2666649")
        let (result, requests) = await Self.run(.addFavorite, link: withFragment, reply: try FlagCapture.page("P03a"))
        #expect((try? result.get()) != nil)
        #expect(requests.map(\.url) == [link])
    }
}
