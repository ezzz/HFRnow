import XCTest
@testable import HFRswift

final class ReplyPostingServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.handledRequests = []
    }

    func testPostReplySuccessUsesReplyFormThenPostsBody() async throws {
        let session = makeSession()
        var step = 0

        URLProtocolMock.requestHandler = { request in
            step += 1
            switch step {
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                let html = """
                <html><body>
                <form name=\"hop\" action=\"/bddpost.php\">
                  <input type=\"hidden\" name=\"cat\" value=\"13\" />
                  <input type=\"hidden\" name=\"post\" value=\"42\" />
                  <input type=\"hidden\" name=\"p\" value=\"1\" />
                </form>
                </body></html>
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(html.utf8)
                )
            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains("content_form=Bonjour%0D%0AMonde"))
                XCTAssertTrue(body.contains("pseudo=testeur"))
                XCTAssertTrue(body.contains("hash_check=hash123"))
                let html = """
                <html><head>
                <meta http-equiv=\"Refresh\" content=\"0;url=/forum2.php?page=12#t789\" />
                </head><body><div class=\"hop\">Message envoyé</div></body></html>
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(html.utf8)
                )
            default:
                XCTFail("Unexpected extra request")
                throw URLError(.badServerResponse)
            }
        }

        let service = ForumReplyPostingService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        let result = try await service.postReply(
            message: "Bonjour\nMonde",
            topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=12&p=1")!
        )

        XCTAssertEqual(step, 2)
        XCTAssertEqual(result.refreshAnchor, "t789")
    }

    func testPostReplyFailsWhenAuthIsRequired() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <a href=\"identification.php\">Connexion</a>
            </body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumReplyPostingService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        do {
            _ = try await service.postReply(
                message: "Salut",
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=12&p=1")!
            )
            XCTFail("Expected authenticationRequired error")
        } catch let error as ReplyPostingError {
            switch error {
            case .authenticationRequired:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPostReplyWhenSessionContextFailsDoesNotSendNetworkRequest() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { _ in
            XCTFail("No network request should be sent when session context fails early")
            throw URLError(.badServerResponse)
        }

        let service = ForumReplyPostingService(
            session: session,
            sessionContextProvider: { _ in
                throw ReplyPostingError.noActiveAccount
            }
        )

        do {
            _ = try await service.postReply(
                message: "Bonjour",
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=12&p=1")!
            )
            XCTFail("Expected noActiveAccount error")
        } catch let error as ReplyPostingError {
            switch error {
            case .noActiveAccount:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(URLProtocolMock.handledRequests.isEmpty)
    }

    func testFetchQuoteTemplateReturnsPrefilledContentForm() async throws {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <form name=\"hop\" action=\"/bddpost.php\">
              <textarea id=\"content_form\">[quotemsg=1,2,3]Salut &amp; merci[/quotemsg]\r\n</textarea>
            </form>
            </body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumReplyQuoteTemplateService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        let template = try await service.fetchQuoteTemplate(
            from: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
        )

        XCTAssertEqual(template, "[quotemsg=1,2,3]Salut & merci[/quotemsg]\n")
    }

    func testFetchQuoteTemplateWhenSessionContextFailsDoesNotSendNetworkRequest() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { _ in
            XCTFail("No network request should be sent when session context fails early")
            throw URLError(.badServerResponse)
        }

        let service = ForumReplyQuoteTemplateService(
            session: session,
            sessionContextProvider: { _ in
                throw ReplyPostingError.noActiveAccount
            }
        )

        do {
            _ = try await service.fetchQuoteTemplate(
                from: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
            )
            XCTFail("Expected noActiveAccount error")
        } catch let error as ReplyPostingError {
            switch error {
            case .noActiveAccount:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(URLProtocolMock.handledRequests.isEmpty)
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }
}

private final class URLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var handledRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.handledRequests.append(request)

        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
