import XCTest
import UIKit
@testable import HFRswift

final class ReplyPostingServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.handledRequests = []
        ReplySmileyCacheBridge.updateForumFavorites([])
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
                let params = Self.formEncodedBodyParameters(from: Self.requestBodyData(from: request))
                XCTAssertEqual(params["content_form"], "Bonjour\r\nMonde")
                XCTAssertEqual(params["pseudo"], "testeur")
                XCTAssertEqual(params["hash_check"], "hash123")
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

    func testPostReplyAppliesSubjectAndRecipientOverrides() async throws {
        let session = makeSession()
        var step = 0

        URLProtocolMock.requestHandler = { request in
            step += 1
            switch step {
            case 1:
                let html = """
                <html><body>
                <form name=\"hop\" action=\"/bddpost.php\">
                  <input type=\"hidden\" name=\"cat\" value=\"prive\" />
                  <input type=\"text\" name=\"sujet\" value=\"Sujet initial\" />
                  <input type=\"text\" name=\"dest\" value=\"PseudoSource\" />
                </form>
                </body></html>
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(html.utf8)
                )
            case 2:
                let params = Self.formEncodedBodyParameters(from: Self.requestBodyData(from: request))
                XCTAssertEqual(params["content_form"], "Bonjour")
                XCTAssertEqual(params["sujet"], "Sujet final")
                XCTAssertEqual(params["dest"], "PseudoCible")
                let html = """
                <html><body><div class=\"hop\">Message envoyé</div></body></html>
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

        _ = try await service.postReply(
            message: "Bonjour",
            topicURL: URL(string: "https://forum.hardware.fr/message.php?cat=prive")!,
            formOverrides: [
                "sujet": "Sujet final",
                "dest": "PseudoCible"
            ]
        )

        XCTAssertEqual(step, 2)
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

    func testPostReplyWhenMessageIsBlankFailsEarlyWithoutNetworkRequest() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { _ in
            XCTFail("No network request should be sent when message is blank")
            throw URLError(.badServerResponse)
        }

        let service = ForumReplyPostingService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        do {
            _ = try await service.postReply(
                message: " \n\t ",
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
            )
            XCTFail("Expected emptyMessage")
        } catch let error as ReplyPostingError {
            switch error {
            case .emptyMessage:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(URLProtocolMock.handledRequests.isEmpty)
    }

    func testPostReplySubmissionRejectedParsesHopMessage() async {
        let session = makeSession()
        var step = 0

        URLProtocolMock.requestHandler = { request in
            step += 1
            switch step {
            case 1:
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
                let html = """
                <html><body>
                <div class=\"hop\">Afin de prévenir le flood, veuillez patienter.<a href=\"/faq.php\">Aide</a></div>
                </body></html>
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

        do {
            _ = try await service.postReply(
                message: "Bonjour",
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
            )
            XCTFail("Expected submissionRejected")
        } catch let error as ReplyPostingError {
            switch error {
            case .submissionRejected(let message):
                XCTAssertEqual(message, "Afin de prévenir le flood, veuillez patienter. Aide")
                XCTAssertFalse(message?.contains("class=\"hop\"") ?? false)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
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

    func testFetchQuoteTemplateWhenHopFormIsMissingReturnsReplyFormUnavailable() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <div>Pas de formulaire hop ici</div>
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

        do {
            _ = try await service.fetchQuoteTemplate(
                from: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
            )
            XCTFail("Expected replyFormUnavailable")
        } catch let error as ReplyPostingError {
            switch error {
            case .replyFormUnavailable:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPostReplyServerErrorParsesHopMessageWithoutClassPrefix() async {
        let session = makeSession()
        var step = 0

        URLProtocolMock.requestHandler = { request in
            step += 1
            switch step {
            case 1:
                let html = """
                <html><body>
                <form name=\"hop\" action=\"/bddpost.php\">
                  <input type=\"hidden\" name=\"cat\" value=\"13\" />
                  <input type=\"hidden\" name=\"post\" value=\"42\" />
                </form>
                </body></html>
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(html.utf8)
                )
            case 2:
                let html = """
                <html><body>
                <div class=\"hop\">Afin de prévenir le flood, veuillez patienter.</div>
                </body></html>
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
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

        do {
            _ = try await service.postReply(
                message: "Bonjour",
                topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
            )
            XCTFail("Expected serverError")
        } catch let error as ReplyPostingError {
            switch error {
            case .serverError(let statusCode, let message):
                XCTAssertEqual(statusCode, 400)
                XCTAssertEqual(message, "Afin de prévenir le flood, veuillez patienter.")
                XCTAssertFalse(message?.contains("class=\"hop\"") ?? false)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchQuoteTemplateServerErrorParsesHopMessageWithoutClassPrefix() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <p class=\"hop\">Afin de prévenir le flood, veuillez patienter.</p>
            </body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumReplyQuoteTemplateService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        do {
            _ = try await service.fetchQuoteTemplate(
                from: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
            )
            XCTFail("Expected serverError")
        } catch let error as ReplyPostingError {
            switch error {
            case .serverError(let statusCode, let message):
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(message, "Afin de prévenir le flood, veuillez patienter.")
                XCTAssertFalse(message?.contains("class=\"hop\"") ?? false)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
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

    func testPreloadReplyContextLoadsForumFavoriteSmileysFromDynamicSmileys() async {
        ReplySmileyCacheBridge.updateForumFavorites([])
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <div id=\"dynamic_smilies\">
              <img src=\"https://forum-images.hardware.fr/icones/foo.gif\" alt=\":foo:\" />
              <img src=\"https://forum-images.hardware.fr/icones/bar.gif\" alt=\":bar:\" />
            </div>
            <form name=\"hop\" action=\"/bddpost.php\">
              <input type=\"hidden\" name=\"cat\" value=\"13\" />
            </form>
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

        await service.preloadReplyContext(
            topicURL: URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=1&p=1")!
        )

        let favorites = BundleReplySmileyCatalogLoader().loadFavoriteSmileys()
        let favoriteByCode = Dictionary(uniqueKeysWithValues: favorites.map { ($0.code, $0) })

        XCTAssertNotNil(favoriteByCode[":foo:"])
        XCTAssertNotNil(favoriteByCode[":bar:"])

        if case .remote(let fooURL) = favoriteByCode[":foo:"]?.imageSource {
            XCTAssertEqual(fooURL.absoluteString, "https://forum-images.hardware.fr/icones/foo.gif")
        } else {
            XCTFail("Expected :foo: to be loaded as remote favorite")
        }
    }

    func testFetchComposerContextReturnsPrivateMessageSubjectAndRecipient() async throws {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <form name=\"hop\" action=\"/bddpost.php\">
              <input type=\"text\" name=\"sujet\" value=\"Mon sujet MP\" />
              <input type=\"text\" name=\"dest\" value=\"Pseudo MP\" />
              <textarea id=\"content_form\"></textarea>
            </form>
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

        let context = try await service.fetchComposerContext(
            topicURL: URL(string: "https://forum.hardware.fr/message.php?cat=prive")!
        )

        XCTAssertEqual(context.subject, "Mon sujet MP")
        XCTAssertEqual(context.recipient, "Pseudo MP")
    }

    func testDeleteMessageSuccessPostsDeleteFormAndReturnsRefreshInfo() async throws {
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
                  <textarea id=\"content_form\">Message &amp; initial\nligne 2</textarea>
                </form>
                </body></html>
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(html.utf8)
                )
            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.absoluteString, "https://forum.hardware.fr/bddpost.php")

                let params = Self.formEncodedBodyParameters(from: Self.requestBodyData(from: request))
                XCTAssertEqual(params["delete"], "1")
                XCTAssertEqual(params["content_form"], "Message & initial\r\nligne 2")
                XCTAssertEqual(params["pseudo"], "testeur")
                XCTAssertEqual(params["hash_check"], "hash123")
                XCTAssertEqual(params["numreponse"], "55767559")

                let html = """
                <html><head>
                <meta http-equiv=\"Refresh\" content=\"0;url=/forum2.php?config=hfr.inc&cat=13&post=42&page=2&p=1#t55767559\" />
                </head><body><div class=\"hop\">Message supprimé</div></body></html>
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

        let service = ForumMessageDeletionService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        let result = try await service.deleteMessage(
            editURL: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42&page=2&p=1&numreponse=55767559")!
        )

        XCTAssertEqual(step, 2)
        XCTAssertEqual(result.refreshAnchor, "55767559")
        XCTAssertEqual(result.refreshURL?.absoluteString, "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=2&p=1#t55767559")
        XCTAssertEqual(result.statusMessage, "Message supprimé")
    }

    func testModerationPrepareAlertReturnsAlreadyAlertedWhenHopContainsLink() async throws {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <div class=\"hop\">Alerte déjà envoyée. <a href=\"/forum2.php\">Retour</a></div>
            </body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumModerationAlertService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        let preparation = try await service.prepareAlert(
            from: URL(string: "https://forum.hardware.fr/modo.php?config=hfr.inc&cat=13&post=42")!
        )

        switch preparation {
        case .alreadyAlerted(let message):
            XCTAssertEqual(message, "Alerte déjà envoyée. Retour")
        case .ready:
            XCTFail("Expected alreadyAlerted state")
        }
    }

    func testModerationPrepareAlertDoesNotMisdetectLoginFromGenericPseudoPasswordText() async throws {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <p>Pour modifier votre mot de passe, renseignez votre pseudo dans votre profil.</p>
            <form action=\"/user/modo.php\" method=\"post\">
              <input type=\"hidden\" name=\"cat\" value=\"13\" />
              <input type=\"hidden\" name=\"post\" value=\"42\" />
              <textarea name=\"raison\"></textarea>
            </form>
            </body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumModerationAlertService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        let preparation = try await service.prepareAlert(
            from: URL(string: "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=42")!
        )

        switch preparation {
        case .ready(let prepared):
            XCTAssertEqual(prepared.submitURL.absoluteString, "https://forum.hardware.fr/user/modo.php")
            XCTAssertEqual(prepared.params["cat"], "13")
            XCTAssertEqual(prepared.params["post"], "42")
        case .alreadyAlerted:
            XCTFail("Expected ready moderation form")
        }
    }

    func testModerationPrepareAlertReturnsAuthenticationRequiredWhenLoginFormIsPresent() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let html = """
            <html><body>
            <form action=\"/identification.php\" method=\"post\">
              <input type=\"text\" name=\"pseudo\" />
              <input type=\"password\" name=\"password\" />
              <input type=\"submit\" name=\"login\" value=\"Connexion\" />
            </form>
            </body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumModerationAlertService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )

        do {
            _ = try await service.prepareAlert(
                from: URL(string: "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=42")!
            )
            XCTFail("Expected authenticationRequired")
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

    func testModerationSubmitAlertPostsReasonAndReturnsHopMessage() async throws {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://forum.hardware.fr/modo.php")
            let params = Self.formEncodedBodyParameters(from: Self.requestBodyData(from: request))
            XCTAssertEqual(params["cat"], "13")
            XCTAssertEqual(params["post"], "42")
            XCTAssertEqual(params["raison"], "Ligne 1\r\nLigne 2")

            let html = """
            <html><body><div class=\"hop\">Alerte envoyée.</div></body></html>
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(html.utf8)
            )
        }

        let service = ForumModerationAlertService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )
        let prepared = ModerationAlertPreparedForm(
            submitURL: URL(string: "https://forum.hardware.fr/modo.php")!,
            params: [
                "cat": "13",
                "post": "42"
            ]
        )

        let status = try await service.submitAlert(reason: "Ligne 1\nLigne 2", with: prepared)
        XCTAssertEqual(status, "Alerte envoyée.")
    }

    func testModerationSubmitAlertWithBlankReasonFailsWithoutNetworkRequest() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { _ in
            XCTFail("No network request should be sent when moderation reason is blank")
            throw URLError(.badServerResponse)
        }

        let service = ForumModerationAlertService(
            session: session,
            sessionContextProvider: { _ in
                ReplySessionContext(pseudoDisplay: "testeur", hashCheck: "hash123")
            }
        )
        let prepared = ModerationAlertPreparedForm(
            submitURL: URL(string: "https://forum.hardware.fr/modo.php")!,
            params: [:]
        )

        do {
            _ = try await service.submitAlert(reason: " \n\t ", with: prepared)
            XCTFail("Expected emptyMessage")
        } catch let error as ReplyPostingError {
            switch error {
            case .emptyMessage:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertTrue(URLProtocolMock.handledRequests.isEmpty)
    }

    func testImg3UploadParsesSuccessfulPayload() async throws {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/upload")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)

            let bodyString = String(data: Self.requestBodyData(from: request), encoding: .isoLatin1) ?? ""
            XCTAssertTrue(bodyString.contains("name=\"source\""))

            let json = """
            {
              "status_code": 200,
              "image": {
                "width": 1151,
                "height": 898,
                "url": "https://img3.super-h.fr/images/full.jpg",
                "medium": { "url": "https://img3.super-h.fr/images/medium.jpg" },
                "thumb": { "url": "https://img3.super-h.fr/images/thumb.jpg" }
              }
            }
            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let service = Img3ReplyImageUploadService(
            session: session,
            uploadURL: URL(string: "https://example.com/upload")!
        )
        let uploadedImage = try await service.uploadImage(makeTestImage(), maxDimension: .px1200)

        XCTAssertEqual(uploadedImage.fullURL, "https://img3.super-h.fr/images/full.jpg")
        XCTAssertEqual(uploadedImage.mediumURL, "https://img3.super-h.fr/images/medium.jpg")
        XCTAssertEqual(uploadedImage.miniURL, "https://img3.super-h.fr/images/thumb.jpg")
        XCTAssertEqual(uploadedImage.fullWidth, 1151)
        XCTAssertEqual(uploadedImage.fullHeight, 898)
    }

    func testImg3UploadReturnsPayloadErrorWhenStatusCodeIsNotSuccess() async {
        let session = makeSession()

        URLProtocolMock.requestHandler = { request in
            let json = """
            {
              "status_code": 400,
              "error": { "message": "File too big - max 500 KB" }
            }
            """

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(json.utf8)
            )
        }

        let service = Img3ReplyImageUploadService(
            session: session,
            uploadURL: URL(string: "https://example.com/upload")!
        )

        do {
            _ = try await service.uploadImage(makeTestImage(), maxDimension: .px1200)
            XCTFail("Expected serverError")
        } catch let error as ReplyImageUploadError {
            switch error {
            case .serverError(let statusCode, let message):
                XCTAssertEqual(statusCode, 400)
                XCTAssertEqual(message, "File too big - max 500 KB")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRehostUploadedImageFormatsBBCodeByModeAndVariant() {
        let uploadedImage = RehostUploadedImage(
            fullWidth: 1200,
            fullHeight: 900,
            fullURL: "https://img3.super-h.fr/images/full.jpg",
            mediumURL: "https://img3.super-h.fr/images/medium.jpg",
            previewURL: nil,
            miniURL: "https://img3.super-h.fr/images/thumb.jpg"
        )

        XCTAssertEqual(
            uploadedImage.formattedSnippet(for: .full, mode: .imageNoLink),
            "[img]https://img3.super-h.fr/images/full.jpg[/img]\n"
        )
        XCTAssertEqual(
            uploadedImage.formattedSnippet(for: .medium, mode: .imageWithLink),
            "[url=https://img3.super-h.fr/images/full.jpg][img]https://img3.super-h.fr/images/medium.jpg[/img][/url]\n"
        )
        XCTAssertEqual(
            uploadedImage.formattedSnippet(for: .mini, mode: .linkOnly),
            "https://img3.super-h.fr/images/thumb.jpg"
        )
    }

    func testReplyQuoteDraftMergerReturnsQuoteWhenDraftIsEmpty() {
        let merged = ReplyQuoteDraftMerger.merge(
            quoteTemplate: "[quotemsg=1,2,3]Salut[/quotemsg]\n",
            into: ""
        )

        XCTAssertEqual(merged, "[quotemsg=1,2,3]Salut[/quotemsg]\n")
    }

    func testReplyQuoteDraftMergerAppendsQuoteWhenDraftAlreadyHasText() {
        let merged = ReplyQuoteDraftMerger.merge(
            quoteTemplate: "[quotemsg=1,2,3]Salut[/quotemsg]\n",
            into: "Mon brouillon"
        )

        XCTAssertEqual(merged, "Mon brouillon\n\n[quotemsg=1,2,3]Salut[/quotemsg]\n")
    }

    func testReplyQuoteDraftMergerDoesNotDuplicateExistingQuote() {
        let existing = "Mon brouillon\n\n[quotemsg=1,2,3]Salut[/quotemsg]\n"
        let merged = ReplyQuoteDraftMerger.merge(
            quoteTemplate: "[quotemsg=1,2,3]Salut[/quotemsg]\n",
            into: existing
        )

        XCTAssertEqual(merged, existing)
    }

    func testReplyQuoteDraftMergerIgnoresEmptyQuoteTemplate() {
        let merged = ReplyQuoteDraftMerger.merge(
            quoteTemplate: " \n\t ",
            into: "Mon brouillon"
        )

        XCTAssertEqual(merged, "Mon brouillon")
    }

    func testComposerDraftPersistenceKeepsStoredDraftWhenEphemeralComposerCloses() {
        let persistedDraft = AnswerView.ComposerDraftPersistence.draftAfterDismiss(
            currentMessage: "[quotemsg=1,2,3]Citation[/quotemsg]\nRéponse en cours",
            existingDraft: "Brouillon du bouton plus",
            persistsDraft: false
        )

        XCTAssertEqual(persistedDraft, "Brouillon du bouton plus")
    }

    func testComposerDraftPersistenceClearsStoredDraftOnlyForPersistentComposerAfterPost() {
        XCTAssertEqual(
            AnswerView.ComposerDraftPersistence.draftAfterSuccessfulPost(
                existingDraft: "Brouillon du bouton plus",
                persistsDraft: true
            ),
            ""
        )

        XCTAssertEqual(
            AnswerView.ComposerDraftPersistence.draftAfterSuccessfulPost(
                existingDraft: "Brouillon du bouton plus",
                persistsDraft: false
            ),
            "Brouillon du bouton plus"
        )
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        return renderer.image { context in
            UIColor.systemRed.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    private static func requestBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }

        return data
    }

    private static func formEncodedBodyParameters(from data: Data) -> [String: String] {
        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            return [:]
        }

        var result: [String: String] = [:]
        for pair in body.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let keyPart = parts.first else { continue }
            let key = Self.decodeFormComponent(String(keyPart))
            let value = parts.count > 1 ? Self.decodeFormComponent(String(parts[1])) : ""
            result[key] = value
        }
        return result
    }

    private static func decodeFormComponent(_ value: String) -> String {
        let plusDecoded = value.replacingOccurrences(of: "+", with: " ")
        return plusDecoded.removingPercentEncoding ?? plusDecoded
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
