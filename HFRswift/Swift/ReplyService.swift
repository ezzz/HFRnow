import Foundation
import UIKit

struct ReplyPostingResult {
    let refreshAnchor: String?
    let refreshURL: URL?
    let statusMessage: String?
}

enum ReplyPostingError: LocalizedError {
    case emptyMessage
    case authenticationRequired
    case replyFormUnavailable
    case noActiveAccount
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case submissionRejected(message: String?)

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "Le message est vide."
        case .authenticationRequired:
            return "Session expirée. Merci de vous reconnecter."
        case .replyFormUnavailable:
            return "Impossible de charger le formulaire de réponse."
        case .noActiveAccount:
            return "Aucun compte actif disponible pour poster."
        case .invalidResponse:
            return "Réponse serveur invalide."
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Erreur serveur (\(statusCode)) : \(message)"
            }
            return "Erreur serveur (\(statusCode))."
        case .submissionRejected(let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Le serveur a refusé le message."
        }
    }
}

protocol ReplyPostingService {
    func postReply(message: String, topicURL: URL) async throws -> ReplyPostingResult
}

protocol ReplyComposerContextPreloading {
    func preloadReplyContext(topicURL: URL) async
}

protocol ReplyQuoteTemplateLoading {
    func fetchQuoteTemplate(from quoteURL: URL) async throws -> String
}

protocol MessageDeletionService {
    func deleteMessage(editURL: URL) async throws -> ReplyPostingResult
}

struct ModerationAlertPreparedForm {
    let submitURL: URL
    let params: [String: String]
}

enum ModerationAlertPreparation {
    case ready(ModerationAlertPreparedForm)
    case alreadyAlerted(message: String)
}

protocol ModerationAlertService {
    func prepareAlert(from alertURL: URL) async throws -> ModerationAlertPreparation
    func submitAlert(reason: String, with preparedForm: ModerationAlertPreparedForm) async throws -> String
}

struct ReplySessionContext {
    let pseudoDisplay: String?
    let hashCheck: String?
}

final class ForumReplyPostingService: ReplyPostingService, ReplyComposerContextPreloading {
    typealias SessionContextProvider = (HTTPCookieStorage) throws -> ReplySessionContext

    private struct FormPayload {
        var params: [String: String]
        var actionURL: URL?
    }

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let sessionContextProvider: SessionContextProvider

    init(
        session: URLSession? = nil,
        cookieStorage: HTTPCookieStorage = .shared,
        sessionContextProvider: SessionContextProvider? = nil
    ) {
        self.cookieStorage = cookieStorage
        self.sessionContextProvider = sessionContextProvider ?? Self.defaultSessionContextProvider

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = cookieStorage
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            self.session = URLSession(configuration: config)
        }
    }

    func postReply(message: String, topicURL: URL) async throws -> ReplyPostingResult {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw ReplyPostingError.emptyMessage
        }

        let bodyString = message.replacingOccurrences(of: "\n", with: "\r\n")
        let sessionContext = try sessionContextProvider(cookieStorage)

        var payload = try await fetchReplyFormPayload(from: topicURL)
        let queryParams = queryParameters(from: topicURL)

        if payload.params.isEmpty {
            payload.params = queryParams
        } else {
            for (key, value) in queryParams where payload.params[key] == nil {
                payload.params[key] = value
            }
        }

        payload.params["content_form"] = bodyString
        if let pseudoDisplay = sessionContext.pseudoDisplay {
            payload.params["pseudo"] = pseudoDisplay
        }
        if let hashCheck = sessionContext.hashCheck {
            payload.params["hash_check"] = hashCheck
        }
        if payload.params["config"] == nil {
            payload.params["config"] = "hfr.inc"
        }

        let submitURL = payload.actionURL ?? defaultSubmitURL()
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true

        let formBody = urlEncodedForm(payload.params)
        request.httpBody = formBody.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)

        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }

        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }

        guard isSuccessfulPost(html) else {
            throw ReplyPostingError.submissionRejected(message: parseHopMessage(from: html))
        }

        return ReplyPostingResult(
            refreshAnchor: parseRefreshAnchor(from: html),
            refreshURL: parseRefreshURL(from: html, baseURL: topicURL),
            statusMessage: parseHopMessage(from: html)
        )
    }

    func preloadReplyContext(topicURL: URL) async {
        _ = try? await fetchReplyFormPayload(from: topicURL)
    }

    private func fetchReplyFormPayload(from url: URL) async throws -> FormPayload {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)

        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }

        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }

        let dynamicSmileys = extractDynamicSmileyEntries(from: html)
        await MainActor.run {
            ReplySmileyCacheBridge.updateForumFavorites(dynamicSmileys)
        }

        guard let formHTML = extractHopFormHTML(from: html) else {
            throw ReplyPostingError.replyFormUnavailable
        }

        var params = parseInputFields(formHTML)
        let selectParams = parseSelectFields(formHTML)
        for (key, value) in selectParams {
            params[key] = value
        }

        return FormPayload(params: params, actionURL: parseFormAction(from: formHTML, baseURL: url))
    }

    private func queryParameters(from url: URL) -> [String: String] {
        var params: [String: String] = [:]
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return params
        }

        for item in components.queryItems ?? [] {
            if let value = item.value {
                params[item.name] = value
            }
        }

        return params
    }

    private func decodeHTML(_ data: Data) -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func parseInputFields(_ html: String) -> [String: String] {
        var params: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "<input[^>]*>", options: [.caseInsensitive]) else {
            return params
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let name = attributeValue(in: tag, attribute: "name") else { continue }

            let type = attributeValue(in: tag, attribute: "type")?.lowercased()
            if type == "checkbox" {
                params[name] = attributeValue(in: tag, attribute: "checked") != nil ? "1" : "0"
                continue
            }
            if type == "radio" {
                if attributeValue(in: tag, attribute: "checked") != nil {
                    params[name] = attributeValue(in: tag, attribute: "value") ?? ""
                }
                continue
            }

            params[name] = attributeValue(in: tag, attribute: "value") ?? ""
        }

        return params
    }

    private func parseSelectFields(_ html: String) -> [String: String] {
        var params: [String: String] = [:]
        let pattern = "<select[^>]*name\\s*=\\s*(\"[^\"]+\"|'[^']+'|[^\\s>]+)[^>]*>[\\s\\S]*?</select>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return params
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            guard let selectRange = Range(match.range, in: html) else { continue }
            let selectTag = String(html[selectRange])
            guard let name = attributeValue(in: selectTag, attribute: "name") else { continue }

            if let selectedValue = firstSelectedOptionValue(in: selectTag) {
                params[name] = selectedValue
            } else if let firstValue = firstOptionValue(in: selectTag) {
                params[name] = firstValue
            }
        }

        return params
    }

    private func firstSelectedOptionValue(in selectTag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<option[^>]*selected[^>]*>", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(selectTag.startIndex..<selectTag.endIndex, in: selectTag)
        guard let match = regex.firstMatch(in: selectTag, options: [], range: range),
              let optionRange = Range(match.range, in: selectTag) else {
            return nil
        }

        return attributeValue(in: String(selectTag[optionRange]), attribute: "value")
    }

    private func firstOptionValue(in selectTag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<option[^>]*>", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(selectTag.startIndex..<selectTag.endIndex, in: selectTag)
        guard let match = regex.firstMatch(in: selectTag, options: [], range: range),
              let optionRange = Range(match.range, in: selectTag) else {
            return nil
        }

        return attributeValue(in: String(selectTag[optionRange]), attribute: "value")
    }

    private func parseFormAction(from html: String, baseURL: URL) -> URL? {
        let pattern = "<form[^>]*name\\s*=\\s*(\"hop\"|'hop'|hop)[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        let formTag = String(html[formRange])
        guard let action = attributeValue(in: formTag, attribute: "action") else {
            return nil
        }

        return URL(string: action, relativeTo: baseURL)?.absoluteURL
    }

    private func extractHopFormHTML(from html: String) -> String? {
        let pattern = "<form[^>]*name\\s*=\\s*(\"hop\"|'hop'|hop)[^>]*>[\\s\\S]*?</form>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        return String(html[formRange])
    }

    private func extractDynamicSmileyEntries(from html: String) -> [[String: String]] {
        guard let containerHTML = extractDynamicSmileyContainerHTML(from: html),
              let imgTagRegex = try? NSRegularExpression(pattern: "<img[^>]*>", options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(containerHTML.startIndex..<containerHTML.endIndex, in: containerHTML)
        var seenEntries = Set<String>()
        var entries: [[String: String]] = []

        for match in imgTagRegex.matches(in: containerHTML, options: [], range: range) {
            guard let tagRange = Range(match.range, in: containerHTML) else { continue }
            let imgTag = String(containerHTML[tagRange])
            guard let source = attributeValue(in: imgTag, attribute: "src")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let code = attributeValue(in: imgTag, attribute: "alt")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty,
                  !code.isEmpty else {
                continue
            }

            let decodedSource = decodeHTMLEntities(in: source)
            let decodedCode = decodeHTMLEntities(in: code)
            let dedupeKey = "\(decodedSource)|\(decodedCode)"
            guard seenEntries.insert(dedupeKey).inserted else { continue }
            entries.append([
                "source": decodedSource,
                "code": decodedCode
            ])
        }

        return entries
    }

    private func extractDynamicSmileyContainerHTML(from html: String) -> String? {
        let pattern = "<div[^>]*id\\s*=\\s*(\"dynamic_smilies\"|'dynamic_smilies')[^>]*>([\\s\\S]*?)</div>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }

        let contentRange = match.range(at: 2)
        guard contentRange.location != NSNotFound,
              let swiftRange = Range(contentRange, in: html) else {
            return nil
        }

        return String(html[swiftRange])
    }

    private func attributeValue(in tag: String, attribute: String) -> String? {
        let pattern = "\(attribute)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }

        for group in 2...4 {
            let groupRange = match.range(at: group)
            if groupRange.location != NSNotFound,
               let valueRange = Range(groupRange, in: tag) {
                return String(tag[valueRange])
            }
        }

        return nil
    }

    private func parseHopMessage(from html: String) -> String? {
        let hopContainerPattern = "<[^>]*class\\s*=\\s*(\"[^\"]*\\bhop\\b[^\"]*\"|'[^']*\\bhop\\b[^']*'|hop)[^>]*>([\\s\\S]*?)</[^>]+>"
        var rawHopContent: String?

        if let hopContainerRegex = try? NSRegularExpression(pattern: hopContainerPattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = hopContainerRegex.firstMatch(in: html, options: [], range: range) {
                let contentRange = match.range(at: 2)
                if contentRange.location != NSNotFound,
                   let swiftRange = Range(contentRange, in: html) {
                    rawHopContent = String(html[swiftRange])
                }
            }
        }

        if rawHopContent == nil,
           let hopRange = html.range(of: "class=\"hop\"", options: [.caseInsensitive]) {
            let fallbackSnippet = String(html[hopRange.lowerBound...].prefix(2500))
            if let startContentIndex = fallbackSnippet.firstIndex(of: ">") {
                rawHopContent = String(fallbackSnippet[fallbackSnippet.index(after: startContentIndex)...])
            } else {
                rawHopContent = fallbackSnippet
            }
        }

        guard var rawSnippet = rawHopContent else {
            return nil
        }

        if let endTagRange = rawSnippet.range(of: "</", options: [.caseInsensitive]) {
            rawSnippet = String(rawSnippet[..<endTagRange.lowerBound])
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(rawSnippet.startIndex..<rawSnippet.endIndex, in: rawSnippet)
        let stripped = tagRegex.stringByReplacingMatches(in: rawSnippet, options: [], range: nsRange, withTemplate: " ")
        let cleaned = decodeHTMLEntities(in: stripped)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    private func parseRefreshAnchor(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<meta\\s+http-equiv=\"refresh\"\\s+content=\"[^\"]*#([^\"]+)\"", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }

        let groupRange = match.range(at: 1)
        guard groupRange.location != NSNotFound,
              let valueRange = Range(groupRange, in: html) else {
            return nil
        }

        return String(html[valueRange])
    }

    private func parseRefreshURL(from html: String, baseURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "<meta\\s+http-equiv=\"refresh\"\\s+content=\"[^\"]*url=([^\"]+)\"", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }

        let urlRange = match.range(at: 1)
        guard urlRange.location != NSNotFound,
              let valueRange = Range(urlRange, in: html) else {
            return nil
        }

        let rawURL = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else {
            return nil
        }

        return URL(string: rawURL, relativeTo: baseURL)?.absoluteURL
    }

    private func isLoggedOutForm(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        if lowercased.contains("identification.php") || lowercased.contains("name=\"login\"") {
            return true
        }
        if lowercased.contains("mot de passe") && lowercased.contains("pseudo") && !lowercased.contains("name=\"hop\"") {
            return true
        }
        return false
    }

    private func isSuccessfulPost(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        if lowercased.contains("http-equiv=\"refresh\"") {
            return true
        }

        if let range = lowercased.range(of: "class=\"hop\"") {
            let snippet = lowercased[range.lowerBound...].prefix(2000)
            if !snippet.contains("<a") && !snippet.contains("<input") {
                return true
            }
        }

        return false
    }

    private func defaultSubmitURL() -> URL {
        if let base = URL(string: k.forumURL()) {
            return base.appendingPathComponent("bddpost.php")
        }
        return URL(string: "https://forum.hardware.fr/bddpost.php")!
    }

    private func urlEncodedForm(_ params: [String: String]) -> String {
        params
            .map { key, value in
                let encodedKey = escapeFormComponent(key)
                let encodedValue = escapeFormComponent(value)
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    private func escapeFormComponent(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    private func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func defaultSessionContextProvider(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        try ObjCAccountSessionService().makeReplySessionContext(cookieStorage: cookieStorage)
    }
}

final class ForumReplyQuoteTemplateService: ReplyQuoteTemplateLoading {
    typealias SessionContextProvider = (HTTPCookieStorage) throws -> ReplySessionContext

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let sessionContextProvider: SessionContextProvider

    init(
        session: URLSession? = nil,
        cookieStorage: HTTPCookieStorage = .shared,
        sessionContextProvider: SessionContextProvider? = nil
    ) {
        self.cookieStorage = cookieStorage
        self.sessionContextProvider = sessionContextProvider ?? Self.defaultSessionContextProvider

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = cookieStorage
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            self.session = URLSession(configuration: config)
        }
    }

    func fetchQuoteTemplate(from quoteURL: URL) async throws -> String {
        _ = try sessionContextProvider(cookieStorage)

        var request = URLRequest(url: quoteURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)

        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }

        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }

        guard let formHTML = extractHopFormHTML(from: html),
              let rawContent = extractContentForm(from: formHTML) else {
            throw ReplyPostingError.replyFormUnavailable
        }

        let decoded = decodeHTMLEntities(in: rawContent)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return decoded
    }

    private func decodeHTML(_ data: Data) -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func extractHopFormHTML(from html: String) -> String? {
        let pattern = "<form[^>]*name\\s*=\\s*(\"hop\"|'hop'|hop)[^>]*>[\\s\\S]*?</form>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        return String(html[formRange])
    }

    private func extractContentForm(from formHTML: String) -> String? {
        let textareaPattern = "<textarea[^>]*(?:id|name)\\s*=\\s*(?:\"content_form\"|'content_form'|content_form)[^>]*>([\\s\\S]*?)</textarea>"
        guard let regex = try? NSRegularExpression(pattern: textareaPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(formHTML.startIndex..<formHTML.endIndex, in: formHTML)
        guard let match = regex.firstMatch(in: formHTML, options: [], range: range) else {
            return nil
        }

        let contentRange = match.range(at: 1)
        guard contentRange.location != NSNotFound,
              let swiftRange = Range(contentRange, in: formHTML) else {
            return nil
        }

        return String(formHTML[swiftRange])
    }

    private func parseHopMessage(from html: String) -> String? {
        let hopContainerPattern = "<[^>]*class\\s*=\\s*(\"[^\"]*\\bhop\\b[^\"]*\"|'[^']*\\bhop\\b[^']*'|hop)[^>]*>([\\s\\S]*?)</[^>]+>"
        var rawHopContent: String?

        if let hopContainerRegex = try? NSRegularExpression(pattern: hopContainerPattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = hopContainerRegex.firstMatch(in: html, options: [], range: range) {
                let contentRange = match.range(at: 2)
                if contentRange.location != NSNotFound,
                   let swiftRange = Range(contentRange, in: html) {
                    rawHopContent = String(html[swiftRange])
                }
            }
        }

        if rawHopContent == nil,
           let hopRange = html.range(of: "class=\"hop\"", options: [.caseInsensitive]) {
            let fallbackSnippet = String(html[hopRange.lowerBound...].prefix(2500))
            if let startContentIndex = fallbackSnippet.firstIndex(of: ">") {
                rawHopContent = String(fallbackSnippet[fallbackSnippet.index(after: startContentIndex)...])
            } else {
                rawHopContent = fallbackSnippet
            }
        }

        guard var rawSnippet = rawHopContent else {
            return nil
        }

        if let endTagRange = rawSnippet.range(of: "</", options: [.caseInsensitive]) {
            rawSnippet = String(rawSnippet[..<endTagRange.lowerBound])
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(rawSnippet.startIndex..<rawSnippet.endIndex, in: rawSnippet)
        let stripped = tagRegex.stringByReplacingMatches(in: rawSnippet, options: [], range: nsRange, withTemplate: " ")
        let cleaned = decodeHTMLEntities(in: stripped)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    private func isLoggedOutForm(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        if lowercased.contains("identification.php") || lowercased.contains("name=\"login\"") {
            return true
        }
        if lowercased.contains("mot de passe") && lowercased.contains("pseudo") && !lowercased.contains("name=\"hop\"") {
            return true
        }
        return false
    }

    private func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func defaultSessionContextProvider(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        try ObjCAccountSessionService().makeReplySessionContext(cookieStorage: cookieStorage)
    }
}

final class ForumMessageDeletionService: MessageDeletionService {
    typealias SessionContextProvider = (HTTPCookieStorage) throws -> ReplySessionContext

    private struct FormPayload {
        var params: [String: String]
        var actionURL: URL?
        var existingContent: String
    }

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let sessionContextProvider: SessionContextProvider

    init(
        session: URLSession? = nil,
        cookieStorage: HTTPCookieStorage = .shared,
        sessionContextProvider: SessionContextProvider? = nil
    ) {
        self.cookieStorage = cookieStorage
        self.sessionContextProvider = sessionContextProvider ?? Self.defaultSessionContextProvider

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = cookieStorage
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            self.session = URLSession(configuration: config)
        }
    }

    func deleteMessage(editURL: URL) async throws -> ReplyPostingResult {
        let sessionContext = try sessionContextProvider(cookieStorage)
        var payload = try await fetchDeleteFormPayload(from: editURL)
        let queryParams = queryParameters(from: editURL)

        if payload.params.isEmpty {
            payload.params = queryParams
        } else {
            for (key, value) in queryParams where payload.params[key] == nil {
                payload.params[key] = value
            }
        }

        payload.params["delete"] = "1"
        payload.params["content_form"] = payload.existingContent.replacingOccurrences(of: "\n", with: "\r\n")
        if let pseudoDisplay = sessionContext.pseudoDisplay {
            payload.params["pseudo"] = pseudoDisplay
        }
        if let hashCheck = sessionContext.hashCheck {
            payload.params["hash_check"] = hashCheck
        }
        if payload.params["config"] == nil {
            payload.params["config"] = "hfr.inc"
        }

        let submitURL = payload.actionURL ?? defaultSubmitURL()
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        request.httpBody = urlEncodedForm(payload.params).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)
        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }
        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }
        guard isSuccessfulDelete(html) else {
            throw ReplyPostingError.submissionRejected(message: parseHopMessage(from: html))
        }

        return ReplyPostingResult(
            refreshAnchor: parseDeletedPostAnchor(from: editURL) ?? parseRefreshAnchor(from: html),
            refreshURL: parseRefreshURL(from: html, baseURL: editURL),
            statusMessage: parseHopMessage(from: html)
        )
    }

    private func fetchDeleteFormPayload(from editURL: URL) async throws -> FormPayload {
        var request = URLRequest(url: editURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)
        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }
        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }
        guard let formHTML = extractHopFormHTML(from: html) else {
            throw ReplyPostingError.replyFormUnavailable
        }

        var params = parseInputFields(formHTML)
        let selectParams = parseSelectFields(formHTML)
        for (key, value) in selectParams {
            params[key] = value
        }

        let existingContent = decodeHTMLEntities(in: extractContentForm(from: formHTML) ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return FormPayload(
            params: params,
            actionURL: parseFormAction(from: formHTML, baseURL: editURL),
            existingContent: existingContent
        )
    }

    private func parseDeletedPostAnchor(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let value = components.queryItems?
            .first(where: { $0.name.lowercased() == "numreponse" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private func queryParameters(from url: URL) -> [String: String] {
        var params: [String: String] = [:]
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return params
        }

        for item in components.queryItems ?? [] {
            if let value = item.value {
                params[item.name] = value
            }
        }

        return params
    }

    private func decodeHTML(_ data: Data) -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func parseInputFields(_ html: String) -> [String: String] {
        var params: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "<input[^>]*>", options: [.caseInsensitive]) else {
            return params
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let name = attributeValue(in: tag, attribute: "name") else { continue }

            let type = attributeValue(in: tag, attribute: "type")?.lowercased()
            if type == "checkbox" {
                params[name] = attributeValue(in: tag, attribute: "checked") != nil ? "1" : "0"
                continue
            }
            if type == "radio" {
                if attributeValue(in: tag, attribute: "checked") != nil {
                    params[name] = attributeValue(in: tag, attribute: "value") ?? ""
                }
                continue
            }

            params[name] = attributeValue(in: tag, attribute: "value") ?? ""
        }

        return params
    }

    private func parseSelectFields(_ html: String) -> [String: String] {
        var params: [String: String] = [:]
        let pattern = "<select[^>]*name\\s*=\\s*(\"[^\"]+\"|'[^']+'|[^\\s>]+)[^>]*>[\\s\\S]*?</select>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return params
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            guard let selectRange = Range(match.range, in: html) else { continue }
            let selectTag = String(html[selectRange])
            guard let name = attributeValue(in: selectTag, attribute: "name") else { continue }

            if let selectedValue = firstSelectedOptionValue(in: selectTag) {
                params[name] = selectedValue
            } else if let firstValue = firstOptionValue(in: selectTag) {
                params[name] = firstValue
            }
        }

        return params
    }

    private func firstSelectedOptionValue(in selectTag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<option[^>]*selected[^>]*>", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(selectTag.startIndex..<selectTag.endIndex, in: selectTag)
        guard let match = regex.firstMatch(in: selectTag, options: [], range: range),
              let optionRange = Range(match.range, in: selectTag) else {
            return nil
        }

        return attributeValue(in: String(selectTag[optionRange]), attribute: "value")
    }

    private func firstOptionValue(in selectTag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<option[^>]*>", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(selectTag.startIndex..<selectTag.endIndex, in: selectTag)
        guard let match = regex.firstMatch(in: selectTag, options: [], range: range),
              let optionRange = Range(match.range, in: selectTag) else {
            return nil
        }

        return attributeValue(in: String(selectTag[optionRange]), attribute: "value")
    }

    private func parseFormAction(from html: String, baseURL: URL) -> URL? {
        let pattern = "<form[^>]*name\\s*=\\s*(\"hop\"|'hop'|hop)[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        let formTag = String(html[formRange])
        guard let action = attributeValue(in: formTag, attribute: "action") else {
            return nil
        }

        return URL(string: action, relativeTo: baseURL)?.absoluteURL
    }

    private func extractHopFormHTML(from html: String) -> String? {
        let pattern = "<form[^>]*name\\s*=\\s*(\"hop\"|'hop'|hop)[^>]*>[\\s\\S]*?</form>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        return String(html[formRange])
    }

    private func extractContentForm(from formHTML: String) -> String? {
        let textareaPattern = "<textarea[^>]*(?:id|name)\\s*=\\s*(?:\"content_form\"|'content_form'|content_form)[^>]*>([\\s\\S]*?)</textarea>"
        guard let regex = try? NSRegularExpression(pattern: textareaPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(formHTML.startIndex..<formHTML.endIndex, in: formHTML)
        guard let match = regex.firstMatch(in: formHTML, options: [], range: range) else {
            return nil
        }

        let contentRange = match.range(at: 1)
        guard contentRange.location != NSNotFound,
              let swiftRange = Range(contentRange, in: formHTML) else {
            return nil
        }

        return String(formHTML[swiftRange])
    }

    private func attributeValue(in tag: String, attribute: String) -> String? {
        let pattern = "\(attribute)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }

        for group in 2...4 {
            let groupRange = match.range(at: group)
            if groupRange.location != NSNotFound,
               let valueRange = Range(groupRange, in: tag) {
                return String(tag[valueRange])
            }
        }

        return nil
    }

    private func parseHopMessage(from html: String) -> String? {
        let hopContainerPattern = "<[^>]*class\\s*=\\s*(\"[^\"]*\\bhop\\b[^\"]*\"|'[^']*\\bhop\\b[^']*'|hop)[^>]*>([\\s\\S]*?)</[^>]+>"
        var rawHopContent: String?

        if let hopContainerRegex = try? NSRegularExpression(pattern: hopContainerPattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = hopContainerRegex.firstMatch(in: html, options: [], range: range) {
                let contentRange = match.range(at: 2)
                if contentRange.location != NSNotFound,
                   let swiftRange = Range(contentRange, in: html) {
                    rawHopContent = String(html[swiftRange])
                }
            }
        }

        if rawHopContent == nil,
           let hopRange = html.range(of: "class=\"hop\"", options: [.caseInsensitive]) {
            let fallbackSnippet = String(html[hopRange.lowerBound...].prefix(2500))
            if let startContentIndex = fallbackSnippet.firstIndex(of: ">") {
                rawHopContent = String(fallbackSnippet[fallbackSnippet.index(after: startContentIndex)...])
            } else {
                rawHopContent = fallbackSnippet
            }
        }

        guard var rawSnippet = rawHopContent else {
            return nil
        }

        if let endTagRange = rawSnippet.range(of: "</", options: [.caseInsensitive]) {
            rawSnippet = String(rawSnippet[..<endTagRange.lowerBound])
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(rawSnippet.startIndex..<rawSnippet.endIndex, in: rawSnippet)
        let stripped = tagRegex.stringByReplacingMatches(in: rawSnippet, options: [], range: nsRange, withTemplate: " ")
        let cleaned = decodeHTMLEntities(in: stripped)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    private func parseRefreshAnchor(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<meta\\s+http-equiv=\"refresh\"\\s+content=\"[^\"]*#([^\"]+)\"", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }

        let groupRange = match.range(at: 1)
        guard groupRange.location != NSNotFound,
              let valueRange = Range(groupRange, in: html) else {
            return nil
        }

        return String(html[valueRange])
    }

    private func parseRefreshURL(from html: String, baseURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "<meta\\s+http-equiv=\"refresh\"\\s+content=\"[^\"]*url=([^\"]+)\"", options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range) else {
            return nil
        }

        let urlRange = match.range(at: 1)
        guard urlRange.location != NSNotFound,
              let valueRange = Range(urlRange, in: html) else {
            return nil
        }

        let rawURL = String(html[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else {
            return nil
        }

        return URL(string: rawURL, relativeTo: baseURL)?.absoluteURL
    }

    private func isLoggedOutForm(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        if lowercased.contains("identification.php") || lowercased.contains("name=\"login\"") {
            return true
        }
        if lowercased.contains("mot de passe") && lowercased.contains("pseudo") && !lowercased.contains("name=\"hop\"") {
            return true
        }
        return false
    }

    private func isSuccessfulDelete(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        if lowercased.contains("http-equiv=\"refresh\"") {
            return true
        }

        if let range = lowercased.range(of: "class=\"hop\"") {
            let snippet = lowercased[range.lowerBound...].prefix(2000)
            if !snippet.contains("<a") && !snippet.contains("<input") {
                return true
            }
        }

        return false
    }

    private func defaultSubmitURL() -> URL {
        if let base = URL(string: k.forumURL()) {
            return base.appendingPathComponent("bddpost.php")
        }
        return URL(string: "https://forum.hardware.fr/bddpost.php")!
    }

    private func urlEncodedForm(_ params: [String: String]) -> String {
        params
            .map { key, value in
                let encodedKey = escapeFormComponent(key)
                let encodedValue = escapeFormComponent(value)
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    private func escapeFormComponent(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    private func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func defaultSessionContextProvider(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        try ObjCAccountSessionService().makeReplySessionContext(cookieStorage: cookieStorage)
    }
}

final class ForumModerationAlertService: ModerationAlertService {
    typealias SessionContextProvider = (HTTPCookieStorage) throws -> ReplySessionContext

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let sessionContextProvider: SessionContextProvider

    init(
        session: URLSession? = nil,
        cookieStorage: HTTPCookieStorage = .shared,
        sessionContextProvider: SessionContextProvider? = nil
    ) {
        self.cookieStorage = cookieStorage
        self.sessionContextProvider = sessionContextProvider ?? Self.defaultSessionContextProvider

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieStorage = cookieStorage
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            self.session = URLSession(configuration: config)
        }
    }

    func prepareAlert(from alertURL: URL) async throws -> ModerationAlertPreparation {
        _ = try sessionContextProvider(cookieStorage)

        var request = URLRequest(url: alertURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)
        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }
        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }

        if isAlreadyAlerted(html) {
            let message = parseHopMessage(from: html) ?? "Alerte déjà envoyée."
            return .alreadyAlerted(message: message)
        }

        guard let formHTML = extractModerationFormHTML(from: html) else {
            throw ReplyPostingError.replyFormUnavailable
        }

        let submitURL = parseFormAction(from: formHTML, baseURL: alertURL) ?? defaultSubmitURL()
        let formParams = parseInputFields(formHTML)
        return .ready(
            ModerationAlertPreparedForm(
                submitURL: submitURL,
                params: formParams
            )
        )
    }

    func submitAlert(reason: String, with preparedForm: ModerationAlertPreparedForm) async throws -> String {
        _ = try sessionContextProvider(cookieStorage)

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw ReplyPostingError.emptyMessage
        }

        var formParams = preparedForm.params
        formParams["raison"] = reason.replacingOccurrences(of: "\n", with: "\r\n")

        var request = URLRequest(url: preparedForm.submitURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        request.httpBody = urlEncodedForm(formParams).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReplyPostingError.invalidResponse
        }

        let html = decodeHTML(data)
        if !(200...299).contains(http.statusCode) {
            throw ReplyPostingError.serverError(statusCode: http.statusCode, message: parseHopMessage(from: html))
        }
        if isLoggedOutForm(html) {
            throw ReplyPostingError.authenticationRequired
        }

        let statusMessage = parseHopMessage(from: html)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !statusMessage.isEmpty else {
            throw ReplyPostingError.submissionRejected(message: nil)
        }
        return statusMessage
    }

    private func decodeHTML(_ data: Data) -> String {
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func extractModerationFormHTML(from html: String) -> String? {
        let pattern = "<form[^>]*action\\s*=\\s*(\"[^\"]*modo\\.php[^\"]*\"|'[^']*modo\\.php[^']*'|[^\\s>]*modo\\.php[^\\s>]*)[^>]*>[\\s\\S]*?</form>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        return String(html[formRange])
    }

    private func isAlreadyAlerted(_ html: String) -> Bool {
        guard let hopHTML = extractHopContainerHTML(from: html) else {
            return false
        }

        let lowercased = hopHTML.lowercased()
        return lowercased.contains("<a") || lowercased.contains("<input")
    }

    private func extractHopContainerHTML(from html: String) -> String? {
        let pattern = "<[^>]*class\\s*=\\s*(\"[^\"]*\\bhop\\b[^\"]*\"|'[^']*\\bhop\\b[^']*'|hop)[^>]*>[\\s\\S]*?</[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let contentRange = Range(match.range, in: html) else {
            return nil
        }

        return String(html[contentRange])
    }

    private func parseInputFields(_ html: String) -> [String: String] {
        var params: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "<input[^>]*>", options: [.caseInsensitive]) else {
            return params
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, options: [], range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let name = attributeValue(in: tag, attribute: "name") else { continue }

            let type = attributeValue(in: tag, attribute: "type")?.lowercased()
            if type == "checkbox" {
                params[name] = attributeValue(in: tag, attribute: "checked") != nil ? "1" : "0"
                continue
            }
            if type == "radio" {
                if attributeValue(in: tag, attribute: "checked") != nil {
                    params[name] = attributeValue(in: tag, attribute: "value") ?? ""
                }
                continue
            }

            params[name] = attributeValue(in: tag, attribute: "value") ?? ""
        }

        return params
    }

    private func parseFormAction(from html: String, baseURL: URL) -> URL? {
        let pattern = "<form[^>]*action\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let formRange = Range(match.range, in: html) else {
            return nil
        }

        let formTag = String(html[formRange])
        guard let action = attributeValue(in: formTag, attribute: "action") else {
            return nil
        }
        return URL(string: action, relativeTo: baseURL)?.absoluteURL
    }

    private func attributeValue(in tag: String, attribute: String) -> String? {
        let pattern = "\(attribute)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, options: [], range: range) else {
            return nil
        }

        for group in 2...4 {
            let groupRange = match.range(at: group)
            if groupRange.location != NSNotFound,
               let valueRange = Range(groupRange, in: tag) {
                return String(tag[valueRange])
            }
        }

        return nil
    }

    private func parseHopMessage(from html: String) -> String? {
        let hopContainerPattern = "<[^>]*class\\s*=\\s*(\"[^\"]*\\bhop\\b[^\"]*\"|'[^']*\\bhop\\b[^']*'|hop)[^>]*>([\\s\\S]*?)</[^>]+>"
        var rawHopContent: String?

        if let hopContainerRegex = try? NSRegularExpression(pattern: hopContainerPattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = hopContainerRegex.firstMatch(in: html, options: [], range: range) {
                let contentRange = match.range(at: 2)
                if contentRange.location != NSNotFound,
                   let swiftRange = Range(contentRange, in: html) {
                    rawHopContent = String(html[swiftRange])
                }
            }
        }

        if rawHopContent == nil,
           let hopRange = html.range(of: "class=\"hop\"", options: [.caseInsensitive]) {
            let fallbackSnippet = String(html[hopRange.lowerBound...].prefix(2500))
            if let startContentIndex = fallbackSnippet.firstIndex(of: ">") {
                rawHopContent = String(fallbackSnippet[fallbackSnippet.index(after: startContentIndex)...])
            } else {
                rawHopContent = fallbackSnippet
            }
        }

        guard var rawSnippet = rawHopContent else {
            return nil
        }

        if let endTagRange = rawSnippet.range(of: "</", options: [.caseInsensitive]) {
            rawSnippet = String(rawSnippet[..<endTagRange.lowerBound])
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(rawSnippet.startIndex..<rawSnippet.endIndex, in: rawSnippet)
        let stripped = tagRegex.stringByReplacingMatches(in: rawSnippet, options: [], range: nsRange, withTemplate: " ")
        let cleaned = decodeHTMLEntities(in: stripped)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    private func isLoggedOutForm(_ html: String) -> Bool {
        let lowercased = html.lowercased()
        if lowercased.contains("identification.php")
            || lowercased.contains("name=\"login\"")
            || lowercased.contains("name='login'") {
            return true
        }

        let hasPseudoField =
            lowercased.contains("name=\"pseudo\"")
            || lowercased.contains("name='pseudo'")
            || lowercased.contains("id=\"pseudo\"")
            || lowercased.contains("id='pseudo'")
        let hasPasswordField =
            lowercased.contains("type=\"password\"")
            || lowercased.contains("type='password'")
            || lowercased.contains("name=\"password\"")
            || lowercased.contains("name='password'")
            || lowercased.contains("name=\"pass\"")
            || lowercased.contains("name='pass'")
        let hasHopForm = lowercased.contains("name=\"hop\"") || lowercased.contains("name='hop'")

        if hasPseudoField && hasPasswordField && !hasHopForm {
            return true
        }
        return false
    }

    private func defaultSubmitURL() -> URL {
        if let base = URL(string: k.forumURL()) {
            return base.appendingPathComponent("user/modo.php")
        }
        return URL(string: "https://forum.hardware.fr/user/modo.php")!
    }

    private func urlEncodedForm(_ params: [String: String]) -> String {
        params
            .map { key, value in
                let encodedKey = escapeFormComponent(key)
                let encodedValue = escapeFormComponent(value)
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    private func escapeFormComponent(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    private func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func defaultSessionContextProvider(cookieStorage: HTTPCookieStorage) throws -> ReplySessionContext {
        try ObjCAccountSessionService().makeReplySessionContext(cookieStorage: cookieStorage)
    }
}

enum RehostBBCodeMode: Int, CaseIterable, Identifiable, Codable {
    case imageWithLink = 0
    case imageNoLink = 1
    case linkOnly = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .imageWithLink:
            return "Image et lien"
        case .imageNoLink:
            return "Image sans lien"
        case .linkOnly:
            return "Lien seul"
        }
    }
}

enum RehostUploadMaxDimension: Int, CaseIterable, Identifiable, Codable {
    case px1200 = 1200
    case px1000 = 1000
    case px800 = 800
    case px600 = 600
    case px400 = 400

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) px"
    }
}

enum RehostImageSizeVariant: String, CaseIterable, Identifiable, Codable {
    case full
    case medium
    case preview
    case mini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full:
            return "Maxi"
        case .medium:
            return "Medium"
        case .preview:
            return "Preview"
        case .mini:
            return "Mini"
        }
    }
}

struct RehostPreferences: Equatable, Codable {
    var bbCodeMode: RehostBBCodeMode
    var maxDimension: RehostUploadMaxDimension
}

enum RehostPreferencesStore {
    private static let bbCodeKey = "rehost_use_link"
    private static let maxDimensionKey = "rehost_resize_before_upload"

    static func load(defaults: UserDefaults = .standard) -> RehostPreferences {
        let bbCodeMode = RehostBBCodeMode(rawValue: defaults.integer(forKey: bbCodeKey)) ?? .imageWithLink
        let storedMax = defaults.integer(forKey: maxDimensionKey)
        let maxDimension = RehostUploadMaxDimension(rawValue: storedMax) ?? .px1200
        return RehostPreferences(bbCodeMode: bbCodeMode, maxDimension: maxDimension)
    }

    static func save(_ preferences: RehostPreferences, defaults: UserDefaults = .standard) {
        defaults.set(preferences.bbCodeMode.rawValue, forKey: bbCodeKey)
        defaults.set(preferences.maxDimension.rawValue, forKey: maxDimensionKey)
    }
}

struct RehostUploadedImage: Identifiable, Equatable, Codable {
    let fullWidth: Int?
    let fullHeight: Int?
    let fullURL: String
    let mediumURL: String?
    let previewURL: String?
    let miniURL: String?
    let timeStamp: Date

    init(
        fullWidth: Int?,
        fullHeight: Int?,
        fullURL: String,
        mediumURL: String?,
        previewURL: String?,
        miniURL: String?,
        timeStamp: Date = Date()
    ) {
        self.fullWidth = fullWidth
        self.fullHeight = fullHeight
        self.fullURL = fullURL
        self.mediumURL = mediumURL
        self.previewURL = previewURL
        self.miniURL = miniURL
        self.timeStamp = timeStamp
    }

    var id: String {
        "\(fullURL)|\(timeStamp.timeIntervalSince1970)"
    }

    var availableVariants: [RehostImageSizeVariant] {
        var variants: [RehostImageSizeVariant] = [.full]
        if mediumURL?.isEmpty == false {
            variants.append(.medium)
        }
        if previewURL?.isEmpty == false {
            variants.append(.preview)
        }
        if miniURL?.isEmpty == false {
            variants.append(.mini)
        }
        return variants
    }

    var thumbnailURL: String {
        miniURL ?? mediumURL ?? fullURL
    }

    var maxDimensionText: String? {
        guard let fullWidth, let fullHeight else { return nil }
        return "\(max(fullWidth, fullHeight)) px"
    }

    func formattedSnippet(for variant: RehostImageSizeVariant, mode: RehostBBCodeMode) -> String? {
        guard let variantURL = resolvedURL(for: variant) else {
            return nil
        }

        switch mode {
        case .linkOnly:
            return variantURL
        case .imageNoLink:
            return "[img]\(variantURL)[/img]\n"
        case .imageWithLink:
            return "[url=\(fullURL)][img]\(variantURL)[/img][/url]\n"
        }
    }

    private func resolvedURL(for variant: RehostImageSizeVariant) -> String? {
        switch variant {
        case .full:
            return fullURL
        case .medium:
            return mediumURL ?? fullURL
        case .preview:
            return previewURL ?? mediumURL ?? miniURL ?? fullURL
        case .mini:
            return miniURL ?? mediumURL ?? fullURL
        }
    }
}

enum RehostUploadHistoryStore {
    private static let fileName = "rehostImagesSwiftUI.json"

    static func load(fileManager: FileManager = .default) -> [RehostUploadedImage] {
        guard let fileURL = historyFileURL(fileManager: fileManager),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder().decode([RehostUploadedImage].self, from: data)) ?? []
    }

    static func save(_ images: [RehostUploadedImage], fileManager: FileManager = .default) {
        guard let fileURL = historyFileURL(fileManager: fileManager),
              let data = try? JSONEncoder().encode(images) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func historyFileURL(fileManager: FileManager) -> URL? {
        guard let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).last else {
            return nil
        }
        return directory.appendingPathComponent(fileName)
    }
}

protocol ReplyImageUploadService {
    func uploadImage(_ image: UIImage, maxDimension: RehostUploadMaxDimension) async throws -> RehostUploadedImage
}

enum ReplyImageUploadError: LocalizedError, Equatable {
    case invalidUploadURL
    case encodingFailed
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case serverError(statusCode: Int, message: String)
    case missingImageURL
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidUploadURL:
            return "URL d'upload invalide."
        case .encodingFailed:
            return "Impossible d'encoder l'image."
        case .invalidResponse:
            return "Réponse serveur invalide."
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Erreur serveur (\(statusCode)) : \(message)"
            }
            return "Erreur serveur (\(statusCode))."
        case .serverError(let statusCode, let message):
            return "\(statusCode) - \(message)"
        case .missingImageURL:
            return "Le serveur n'a pas renvoyé d'URL d'image."
        case .cancelled:
            return "Upload annulé."
        }
    }
}

final class Img3ReplyImageUploadService: ReplyImageUploadService {
    private let session: URLSession
    private let uploadURL: URL

    // Keep in sync with legacy API_KEY_CHEVERETO_IMG3.
    private static let defaultAPIKey = "hawyikcxboxfkcp1aiqcrhhm8r9xua1c"

    init(
        session: URLSession? = nil,
        uploadURL: URL? = nil,
        apiKey: String = defaultAPIKey
    ) {
        self.uploadURL = uploadURL ?? URL(string: "https://img3.super-h.fr/api/1/upload/?key=\(apiKey)")!

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            self.session = URLSession(configuration: config)
        }
    }

    func uploadImage(_ image: UIImage, maxDimension: RehostUploadMaxDimension) async throws -> RehostUploadedImage {
        let preparedImage = image.rehostPreparedForUpload(maxResolution: maxDimension.rawValue)
        guard let jpegData = preparedImage.jpegData(compressionQuality: 1.0) else {
            throw ReplyImageUploadError.encodingFailed
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 60

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = makeMultipartBody(jpegData: jpegData, boundary: boundary, filename: "snapshot_\(Int.random(in: 1...Int.max)).jpg")
        request.httpBody = body
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReplyImageUploadError.invalidResponse
            }

            let payload = try parseJSONPayload(data)
            let payloadStatus = intValue(payload["status_code"]) ?? httpResponse.statusCode
            let payloadMessage = parsePayloadMessage(payload)

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ReplyImageUploadError.httpError(statusCode: httpResponse.statusCode, message: payloadMessage)
            }

            guard payloadStatus == 200 else {
                throw ReplyImageUploadError.serverError(statusCode: payloadStatus, message: payloadMessage ?? "Erreur inconnue")
            }

            guard let imagePayload = payload["image"] as? [String: Any],
                  let fullURL = imagePayload["url"] as? String,
                  !fullURL.isEmpty else {
                throw ReplyImageUploadError.missingImageURL
            }

            let mediumURL = (imagePayload["medium"] as? [String: Any])?["url"] as? String
            let miniURL = (imagePayload["thumb"] as? [String: Any])?["url"] as? String

            return RehostUploadedImage(
                fullWidth: intValue(imagePayload["width"]),
                fullHeight: intValue(imagePayload["height"]),
                fullURL: fullURL,
                mediumURL: mediumURL,
                previewURL: nil,
                miniURL: miniURL
            )
        } catch let error as ReplyImageUploadError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw ReplyImageUploadError.cancelled
        } catch {
            throw ReplyImageUploadError.invalidResponse
        }
    }

    private func makeMultipartBody(jpegData: Data, boundary: String, filename: String) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"imageCaption\"\r\n\r\n".data(using: .utf8)!)
        body.append("Some Caption\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"source\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    private func parseJSONPayload(_ data: Data) throws -> [String: Any] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReplyImageUploadError.invalidResponse
        }
        return payload
    }

    private func parsePayloadMessage(_ payload: [String: Any]) -> String? {
        if let errorPayload = payload["error"] as? [String: Any],
           let message = errorPayload["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let successPayload = payload["success"] as? [String: Any],
           let message = successPayload["message"] as? String,
           !message.isEmpty {
            return message
        }

        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }
}

private extension UIImage {
    func rehostPreparedForUpload(maxResolution: Int) -> UIImage {
        let normalized = rehostNormalizedOrientation()
        let resolution = max(maxResolution, 1)
        let pixelWidth = CGFloat(normalized.cgImage?.width ?? Int(normalized.size.width * normalized.scale))
        let pixelHeight = CGFloat(normalized.cgImage?.height ?? Int(normalized.size.height * normalized.scale))
        let currentMax = max(pixelWidth, pixelHeight)

        guard currentMax > CGFloat(resolution) else {
            return normalized
        }

        let ratio = CGFloat(resolution) / currentMax
        let targetSize = CGSize(
            width: max(floor(pixelWidth * ratio), 1),
            height: max(floor(pixelHeight * ratio), 1)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            normalized.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func rehostNormalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
