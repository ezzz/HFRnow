// AnswerView.swift
// SwiftUI view to compose and post a reply via HTTP POST
// Created by Assistant

import SwiftUI

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.queryItems = queryItems
        return components.url ?? self
    }
}

struct AnswerView: View {
    // Pass the full answer endpoint URL from MessagesView
    let topicURL: URL?

    @Binding var composerDraftText: String
    @Binding var isComposerPresented: Bool
    @FocusState.Binding var isComposerFocused: Bool

    // Message content typed by the user
    @State private var message: String

    // Posting state
    @State private var isPosting: Bool = false

    // Toast presentation
    @State private var showToast: Bool = false
    @State private var toastText: String = ""
    @State private var toastIsSuccess: Bool = true

    init(topicURL: URL?, composerDraftText: Binding<String>, isComposerPresented: Binding<Bool>, isComposerFocused: FocusState<Bool>.Binding) {
        self.topicURL = topicURL
        self._composerDraftText = composerDraftText
        self._isComposerPresented = isComposerPresented
        self._isComposerFocused = isComposerFocused
        self._message = State(initialValue: composerDraftText.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $message)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(false)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Spacer()
                Button {
                    Task { await postMessage() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(isPosting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.2) : Color.accentColor)
                        .foregroundColor(isPosting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .white)
                        .clipShape(Capsule())
                        .accessibilityLabel("Send")
                }
                .disabled(isPosting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding()
            }
        }
        .navigationTitle("Reply")
        .toolbarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if showToast {
                ToastBanner(text: toastText, isSuccess: toastIsSuccess)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showToast)
        .onChange(of: message) { newValue in
            composerDraftText = newValue
        }
    }

    // MARK: - Networking
    private func postMessage() async {
        guard !isPosting else { return }
        isPosting = true
        defer { isPosting = false }

        guard let topicURL = topicURL else {
            await presentToast(success: false, text: "URL manquante")
            return
        }

        print("URL de réponse présente \(topicURL)")

        // Prepare body similar to Objective-C version: key `content_form` with CRLFs
        var bodyString = message
        bodyString = bodyString.replacingOccurrences(of: "\n", with: "\r\n")

        let multisManager = MultisManager.sharedManager() as! MultisManager
        let mainCompteDict = multisManager.getMainCompte() as? [AnyHashable: Any]
        if let mainCompteDict {
            multisManager.forceCookies(forCompte: mainCompteDict)
        }

        let pseudoDisplay = (mainCompteDict?["PSEUDO_DISPLAY"] as? String) ?? (mainCompteDict?["PSEUDO"] as? String)
        var hashCheck = mainCompteDict?["HASH"] as? String
        if hashCheck == nil, let appDelegate = HFRplusAppDelegate.shared() as? HFRplusAppDelegate {
            hashCheck = appDelegate.hash_check
        }
        if let hashCheck, let mainCompteDict {
            multisManager.setHashForCompte(mainCompteDict, andHash: hashCheck)
        }

        let accountCookies = (mainCompteDict?["COOKIES"] as? [HTTPCookie]) ?? []
        let sharedStorage = HTTPCookieStorage.shared
        let urlCookies = sharedStorage.cookies(for: topicURL) ?? []
        let urlCookieHeader = HTTPCookie.requestHeaderFields(with: urlCookies)["Cookie"]
        let logCookieHeader = urlCookieHeader == nil ? "no" : "yes"
        let logPseudoDisplay = pseudoDisplay != nil ? "yes" : "no"
        let logHashCheck = hashCheck != nil ? "yes" : "no"
        
        print("POST debug: cookies=\(accountCookies.count) urlCookies=\(urlCookies.count) header=\(logCookieHeader) pseudo=\(logPseudoDisplay) hash=\(logHashCheck)")
        print("POST debug: stored cookie names=\(cookieNames(accountCookies))")
        print("POST debug: url cookie names=\(cookieNames(urlCookies))")
        if let urlCookieHeader {
            print("POST debug: url cookie header=\(urlCookieHeader)")
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpCookieStorage = sharedStorage
        sessionConfig.httpCookieAcceptPolicy = .always
        sessionConfig.httpShouldSetCookies = true
        let session = URLSession(configuration: sessionConfig)

        var formParams: FormPayload
        do {
            formParams = try await fetchReplyFormPayload(from: topicURL, session: session)
        } catch {
            await presentToast(success: false, text: "Ooops")
            print("GET form error: \(error)")
            return
        }

        // The forum always displays the "inscription" hint even when logged in.
        // Rely on POST response instead of this heuristic.
        if formParams.params.isEmpty {
            formParams.params = queryParameters(from: topicURL)
        } else {
            for (key, value) in queryParameters(from: topicURL) where formParams.params[key] == nil {
                formParams.params[key] = value
            }
        }
        formParams.params["content_form"] = bodyString
        if let pseudoDisplay {
            formParams.params["pseudo"] = pseudoDisplay
        }
        if let hashCheck {
            formParams.params["hash_check"] = hashCheck
        }
        if formParams.params["config"] == nil {
            formParams.params["config"] = "hfr.inc"
        }

        // Build URLRequest
        let submitURL = defaultSubmitURL()
        var request = URLRequest(url: submitURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true

        // URL-encode the form field
        let formBody = urlEncodedForm(formParams.params)
        request.httpBody = formBody.data(using: .utf8)
        debugPrintPostRequest(request, body: formBody)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            let serverText = String(data: data, encoding: .utf8) ?? ""
            if 200..<300 ~= http.statusCode, isSuccessfulPost(serverText) {
                await presentToast(success: true, text: "Hooray")
                await MainActor.run {
                    message = ""
                    composerDraftText = ""
                    isComposerPresented = false
                    isComposerFocused = false
                }
            } else {
                await presentToast(success: false, text: "Ooops")
                print("POST failed: status=\(http.statusCode) body=\(serverText)")
            }
        } catch {
            await presentToast(success: false, text: "Ooops")
            print("POST error: \(error)")
        }
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

    private struct FormPayload {
        var params: [String: String]
        var rawHTML: String
        var actionURL: URL?
    }

    private func fetchReplyFormPayload(from url: URL, session: URLSession) async throws -> FormPayload {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = true
        debugPrintGetRequest(request)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            let headerDump = http.allHeaderFields
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: " | ")
            print("POST debug: GET form status=\(http.statusCode)")
            print("POST debug: GET form finalURL=\(http.url?.absoluteString ?? "nil")")
            print("POST debug: GET form headers=\(headerDump)")
        }
        let html = decodeHTML(data)
        let snippet = html.prefix(400)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        print("POST debug: GET form snippet=\(snippet)")
        let formHTML = extractHopFormHTML(from: html) ?? html
        var params = parseInputFields(formHTML)
        let selectParams = parseSelectFields(formHTML)
        for (key, value) in selectParams {
            params[key] = value
        }
        let actionURL = parseFormAction(from: formHTML, baseURL: url)
        return FormPayload(params: params, rawHTML: html, actionURL: actionURL)
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
                let checked = attributeValue(in: tag, attribute: "checked") != nil
                params[name] = checked ? "1" : "0"
                continue
            }
            if type == "radio" {
                if attributeValue(in: tag, attribute: "checked") != nil {
                    params[name] = attributeValue(in: tag, attribute: "value") ?? ""
                }
                continue
            }
            let value = attributeValue(in: tag, attribute: "value") ?? ""
            params[name] = value
        }
        return params
    }

    private func parseSelectFields(_ html: String) -> [String: String] {
        var params: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "<select[^>]*name\\s*=\\s*(\"[^\"]+\"|'[^']+'|[^\\s>]+)[^>]*>[\\s\\S]*?</select>", options: [.caseInsensitive]) else {
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
        let optionTag = String(selectTag[optionRange])
        return attributeValue(in: optionTag, attribute: "value")
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
        let optionTag = String(selectTag[optionRange])
        return attributeValue(in: optionTag, attribute: "value")
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
            if groupRange.location != NSNotFound, let valueRange = Range(groupRange, in: tag) {
                return String(tag[valueRange])
            }
        }
        return nil
    }

    private func isLoggedOutForm(_ html: String) -> Bool {
        _ = html
        return false
    }

    private func defaultSubmitURL() -> URL {
        if let base = URL(string: k.forumURL()) {
            return base.appendingPathComponent("bddpost.php")
        }
        return URL(string: "https://forum.hardware.fr/bddpost.php")!
    }

    private func cookieNames(_ cookies: [HTTPCookie]) -> String {
        cookies
            .map { "\($0.name)@\($0.domain)" }
            .joined(separator: ", ")
    }

    private func urlEncodedForm(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = escapeFormComponent(key)
            let v = escapeFormComponent(value)
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private func escapeFormComponent(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
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

    private func debugPrintGetRequest(_ request: URLRequest) {
        let headers = request.allHTTPHeaderFields ?? [:]
        let cookieHeader = cookieHeaderForURL(request.url)
        print("POST debug: GET request url=\(request.url?.absoluteString ?? "nil")")
        print("POST debug: GET request headers=\(headers)")
        print("POST debug: GET request cookie header=\(cookieHeader ?? "nil")")
    }

    private func debugPrintPostRequest(_ request: URLRequest, body: String) {
        let headers = request.allHTTPHeaderFields ?? [:]
        let cookieHeader = cookieHeaderForURL(request.url)
        print("POST debug: POST request url=\(request.url?.absoluteString ?? "nil")")
        print("POST debug: POST request headers=\(headers)")
        print("POST debug: POST request cookie header=\(cookieHeader ?? "nil")")
        print("POST debug: POST request body length=\(body.count)")
    }

    private func cookieHeaderForURL(_ url: URL?) -> String? {
        guard let url else { return nil }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    @MainActor private func presentToast(success: Bool, text: String) {
        toastIsSuccess = success
        toastText = text
        withAnimation {
            showToast = true
        }
        // Auto-dismiss after delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Toast UI
private struct ToastBanner: View {
    let text: String
    let isSuccess: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6, y: 3)
    }
}

// MARK: - Preview
private struct AnswerViewPreviewWrapper: View {
    @State private var draft: String = ""
    @State private var presented: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            AnswerView(topicURL: URL(string: "https://example.com/post")!,
                       composerDraftText: $draft,
                       isComposerPresented: $presented,
                       isComposerFocused: $focused)
        }
    }
}

#Preview {
    AnswerViewPreviewWrapper()
}
