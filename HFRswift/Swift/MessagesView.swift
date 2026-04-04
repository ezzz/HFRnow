//
//  MessagesView.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/3/25.
//

import SwiftUI
import WebKit
import UIKit
import SafariServices
import ImageIO

enum ReplyQuoteDraftMerger {
    static func merge(quoteTemplate: String, into draft: String) -> String {
        let trimmedQuote = quoteTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty else {
            return draft
        }

        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            return quoteTemplate
        }

        if draft.localizedStandardContains(trimmedQuote) {
            return draft
        }

        let separator = draft.hasSuffix("\n") ? "\n" : "\n\n"
        return draft + separator + quoteTemplate
    }
}

enum MessagePopupMenuActionKind: Equatable {
    case quote
    case quoteSelection(isSelected: Bool)
    case edit
    case profile
    case privateMessage
    case blacklist
    case whitelist
    case favorite
    case link
    case alert
    case aq
    case bookmark
    case delete

    var title: String {
        switch self {
        case .quote:
            return "Citer"
        case .quoteSelection(let isSelected):
            return isSelected ? "Citer ☑" : "Citer ☐"
        case .edit:
            return "Editer"
        case .profile:
            return "Profil"
        case .privateMessage:
            return "MP"
        case .blacklist:
            return "Blacklist"
        case .whitelist:
            return "Whitelist"
        case .favorite:
            return "Favoris"
        case .link:
            return "Link"
        case .alert:
            return "Alerter"
        case .aq:
            return "AQ"
        case .bookmark:
            return "Bookmark"
        case .delete:
            return "Supprimer"
        }
    }

    var systemImageName: String {
        switch self {
        case .quote:
            return "quote.bubble"
        case .quoteSelection:
            return "text.quote"
        case .edit:
            return "square.and.pencil"
        case .profile:
            return "person.crop.circle"
        case .privateMessage:
            return "message"
        case .blacklist:
            return "hand.raised"
        case .whitelist:
            return "heart"
        case .favorite:
            return "star"
        case .link:
            return "link"
        case .alert:
            return "exclamationmark.bubble"
        case .aq:
            return "bubble.left.and.exclamationmark.bubble.right"
        case .bookmark:
            return "bookmark"
        case .delete:
            return "trash"
        }
    }

    var isDestructive: Bool {
        if case .delete = self {
            return true
        }
        return false
    }
}

enum MessagePopupMenuPolicy {
    static func orderedActionKinds(
        for actions: TopicPageMessageActions,
        source: MessageWebPopupSource,
        isQuoteSelectionEnabled: Bool,
        messageIndex: Int? = nil
    ) -> [MessagePopupMenuActionKind] {
        var actionKinds: [MessagePopupMenuActionKind] = []

        if source == .avatar {
            if actions.profileURL != nil {
                actionKinds.append(.profile)
            }

            if !actions.isOwnMessage, actions.privateMessageURL != nil {
                actionKinds.append(.privateMessage)
            }

            if !actions.isOwnMessage, hasAuthorName(actions.authorName) {
                actionKinds.append(.blacklist)
                actionKinds.append(.whitelist)
            }
        } else {
            if actions.quoteURL != nil {
                actionKinds.append(.quote)
            }

            if actions.quoteJS != nil {
                actionKinds.append(.quoteSelection(isSelected: isQuoteSelectionEnabled))
            }

            if actions.canBeFavorite, actions.favoriteURL != nil {
                actionKinds.append(.favorite)
            }

            if actions.permalinkURL != nil {
                actionKinds.append(.link)
            }

            if !actions.isOwnMessage {
                if actions.alertURL != nil {
                    actionKinds.append(.alert)
                } else if actions.permalinkURL != nil {
                    actionKinds.append(.alert)
                }
            }

            if actions.canAQ {
                actionKinds.append(.aq)
            }

            if actions.canBookmark {
                actionKinds.append(.bookmark)
            }

            if actions.editURL != nil {
                actionKinds.append(.edit)
            }

            if actions.canDelete, actions.editURL != nil, messageIndex != 0 {
                actionKinds.append(.delete)
            }
        }

        return actionKinds.enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = priority(for: lhs.element)
                let rhsPriority = priority(for: rhs.element)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func hasAuthorName(_ authorName: String?) -> Bool {
        guard let authorName else { return false }
        return !authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func priority(for actionKind: MessagePopupMenuActionKind) -> Int {
        switch actionKind {
        case .quote:
            return 0
        case .quoteSelection:
            return 1
        case .edit:
            return 2
        case .profile:
            return 3
        case .privateMessage:
            return 4
        case .blacklist:
            return 5
        case .whitelist:
            return 6
        case .favorite:
            return 7
        case .link:
            return 8
        case .alert:
            return 9
        case .aq:
            return 10
        case .bookmark:
            return 11
        case .delete:
            return 12
        }
    }
}

enum MessagePopupActionSupport {
    enum AQCreateResult {
        case success
        case failure(String)
        case networkError
    }

    static func numericPostID(from rawPostID: String?) -> String? {
        guard let rawPostID else {
            return nil
        }
        let digits = rawPostID.unicodeScalars.filter(CharacterSet.decimalDigits.contains)
        let numeric = String(String.UnicodeScalarView(digits))
        return numeric.isEmpty ? nil : numeric
    }

    static func isAQAlreadySignaled(topicID: String, postID: String) async -> Bool? {
        let encodedTopic = topicID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topicID
        guard let url = URL(string: "https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=\(encodedTopic)") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            return content.contains(postID)
        } catch {
            return nil
        }
    }

    static func createAQ(
        title: String,
        topicID: String,
        topicTitle: String,
        postID: String,
        postURL: String,
        author: String
    ) async -> AQCreateResult {
        guard let url = URL(string: "https://aq.super-h.fr/api/addAlerte.php") else {
            return .networkError
        }

        let pseudo = currentPseudoLowercased()
        let bodyString = aqRequestBody(
            title: title,
            topicID: topicID,
            topicTitle: topicTitle,
            pseudo: pseudo,
            postID: postID,
            postURL: postURL,
            author: author
        )

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .ascii, allowLossyConversion: true)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = String(data: data, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return response == "1" ? .success : .failure(response.isEmpty ? "?" : response)
        } catch {
            return .networkError
        }
    }

    static func aqRequestBody(
        title: String,
        topicID: String,
        topicTitle: String,
        pseudo: String,
        postID: String,
        postURL: String,
        author: String
    ) -> String {
        let comment = "post de \(author)"
        return [
            "alerte_qualitay_id=-1",
            "nom=\(legacyPercentEncode(title))",
            "topic_id=\(legacyPercentEncode(topicID))",
            "topic_titre=\(legacyPercentEncode(topicTitle))",
            "pseudo=\(legacyPercentEncode(pseudo))",
            "post_id=\(legacyPercentEncode(postID))",
            "post_url=\(legacyPercentEncode(postURL))",
            "commentaire=\(legacyPercentEncode(comment))"
        ].joined(separator: "&")
    }

    static func hasBookmark(topicID: String, postID: String) -> Bool {
        guard let storage = sharedMPStorageObject() else {
            return false
        }
        let selector = NSSelectorFromString("getBookmarkForPost:numreponse:")
        guard storage.responds(to: selector) else {
            return false
        }

        typealias Function = @convention(c) (AnyObject, Selector, NSString, NSString) -> AnyObject?
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, topicID as NSString, postID as NSString) != nil
    }

    static func createBookmark(
        topicID: String,
        topicCategory: String,
        postID: String,
        title: String,
        author: String
    ) -> Bool {
        guard let storage = sharedMPStorageObject(),
              let bookmarkClass = NSClassFromString("Bookmark") as? NSObject.Type else {
            return false
        }

        let bookmark = bookmarkClass.init()
        bookmark.setValue(topicID, forKey: "sPost")
        bookmark.setValue(topicCategory, forKey: "sCat")
        bookmark.setValue(postID, forKey: "sNumResponse")
        bookmark.setValue(title, forKey: "sLabel")
        bookmark.setValue(author, forKey: "sAuthorPost")
        bookmark.setValue(Date(), forKey: "dateBookmarkCreation")

        let selector = NSSelectorFromString("addBookmarkSynchronous:")
        guard storage.responds(to: selector) else {
            return false
        }

        typealias Function = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let implementation = storage.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        return function(storage, selector, bookmark)
    }

    static func favoriteResponseMessage(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<div class="hop">([^<]+)</div>"#) else {
            return nil
        }
        let nsRange = NSRange(location: 0, length: (html as NSString).length)
        guard let match = regex.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let message = String(html[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    private static func legacyPercentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func currentPseudoLowercased() -> String {
        if let mainCompte = ObjCLegacyAccountsManager.shared.mainCompte(),
           let pseudo = mainCompte["PSEUDO_DISPLAY"] as? String {
            return pseudo.lowercased()
        }
        return ""
    }

    private static func sharedMPStorageObject() -> NSObject? {
        guard let klass = NSClassFromString("MPStorage") as? NSObject.Type else {
            return nil
        }
        let selector = NSSelectorFromString("shared")
        guard klass.responds(to: selector),
              let unmanaged = klass.perform(selector) else {
            return nil
        }
        return unmanaged.takeUnretainedValue() as? NSObject
    }
}

private struct MessagePopupSheetSubmissionError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct MessagePopupPromptSheet: View {
    let title: String
    let message: String
    let placeholder: String
    let actionTitle: String
    let onSubmit: (String) async throws -> String
    let onSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var value = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField(placeholder, text: $value)
                        .textInputAutocapitalization(.sentences)
                        .focused($isTextFieldFocused)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(actionTitle) {
                        submit()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView()
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                    }
                }
            }
            .task {
                await MainActor.run {
                    isTextFieldFocused = true
                }
            }
            .alert("Action impossible", isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Erreur inconnue.")
            }
        }
    }

    private func submit() {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !isSubmitting else { return }

        Task { @MainActor in
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                let successMessage = try await onSubmit(trimmedValue)
                dismiss()
                onSuccess(successMessage)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private enum MessageBlackWhiteListActionBridge {
    static func toggleBlacklist(pseudo: String) -> String? {
        guard let object = sharedObject() else {
            return nil
        }

        let isBLSelector = NSSelectorFromString("isBL:")
        guard object.responds(to: isBLSelector) else {
            return nil
        }
        typealias IsBLFunction = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let isBLImplementation = object.method(for: isBLSelector)
        let isBLFunction = unsafeBitCast(isBLImplementation, to: IsBLFunction.self)
        let isBL = isBLFunction(object, isBLSelector, pseudo as NSString)

        if isBL {
            let selector = NSSelectorFromString("removeFromBlackList:andSave:")
            guard object.responds(to: selector) else {
                return nil
            }
            typealias Function = @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool
            let implementation = object.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            let result = function(object, selector, pseudo as NSString, true)
            return result
                ? "\(pseudo) a été supprimé de la liste noire"
                : "Erreur! \(pseudo) n'a pas pu être supprimé de la liste noire"
        }

        let selector = NSSelectorFromString("addToBlackList:andSave:")
        guard object.responds(to: selector) else {
            return nil
        }
        typealias Function = @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool
        let implementation = object.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        let result = function(object, selector, pseudo as NSString, true)
        return result
            ? "BIM! \(pseudo) ajouté à la liste noire"
            : "Erreur! \(pseudo) n'a pas pu être ajouté à la liste noire"
    }

    static func toggleWhitelist(pseudo: String) -> String? {
        guard let object = sharedObject() else {
            return nil
        }
        let isWLSelector = NSSelectorFromString("isWL:")
        guard object.responds(to: isWLSelector) else {
            return nil
        }
        typealias IsWLFunction = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let isWLImplementation = object.method(for: isWLSelector)
        let isWLFunction = unsafeBitCast(isWLImplementation, to: IsWLFunction.self)
        let isWL = isWLFunction(object, isWLSelector, pseudo as NSString)

        if isWL {
            let selector = NSSelectorFromString("removeFromWhiteList:")
            guard object.responds(to: selector) else {
                return nil
            }
            typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Bool
            let implementation = object.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            _ = function(object, selector, pseudo as NSString)
            return "OH NOES ! \(pseudo) a été supprimé de la love list"
        }

        let selector = NSSelectorFromString("addToWhiteList:")
        guard object.responds(to: selector) else {
            return nil
        }
        typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Void
        let implementation = object.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(object, selector, pseudo as NSString)
        return "BOUM BOUM ! \(pseudo) ajouté à la love list ♥"
    }

    private static func sharedObject() -> NSObject? {
        guard let klass = NSClassFromString("BlackList") as? NSObject.Type else {
            return nil
        }
        let selector = NSSelectorFromString("shared")
        guard klass.responds(to: selector),
              let unmanaged = klass.perform(selector) else {
            return nil
        }
        return unmanaged.takeUnretainedValue() as? NSObject
    }
}

struct WebView: UIViewRepresentable {
    enum InitialScroll {
        case top
        case bottom
    }

    let fileURL: URL?
    let readAccessURL: URL?
    var anchor: String?
    var initialScroll: InitialScroll?
    var currentPage: Int
    var maxPage: Int
    var colorScheme: ColorScheme
    var baseBackgroundColor: UIColor
    var themeRevision: Int
    var messageActionsByIndex: [Int: TopicPageMessageActions]
    var actionHandler: any MessageWebActionHandling
    var onWebAction: ((MessageWebAction) -> Void)?
    var onPopupQuoteRequest: ((URL) -> Void)?
    var onPopupEditRequest: ((URL) -> Void)?
    var onPopupPrivateMessageRequest: ((URL, TopicPageMessageActions) -> Void)?
    var onPopupDeleteRequest: ((URL) -> Void)?
    var onPopupAlertRequest: ((URL) -> Void)?
    var onPopupAlertMailRequest: ((URL) -> Void)?
    var onPopupAvatarSheetRequest: ((TopicPageMessageActions) -> Void)?
    var onPopupProfileRequest: ((URL) -> Void)?
    var onPopupAQRequest: ((TopicPageMessageActions) -> Void)?
    var onPopupBookmarkRequest: ((TopicPageMessageActions) -> Void)?
    var onContentReady: (() -> Void)?
    var onScrollPositionChange: ((Bool) -> Void)?

    init(
        fileURL: URL? = nil,
        readAccessURL: URL? = nil,
        anchor: String? = nil,
        initialScroll: InitialScroll? = nil,
        currentPage: Int = 1,
        maxPage: Int = 1,
        colorScheme: ColorScheme = .light,
        baseBackgroundColor: UIColor = .systemGray6,
        themeRevision: Int = 0,
        messageActionsByIndex: [Int: TopicPageMessageActions] = [:],
        actionHandler: any MessageWebActionHandling = MessageWebActionHandler(),
        onWebAction: ((MessageWebAction) -> Void)? = nil,
        onPopupQuoteRequest: ((URL) -> Void)? = nil,
        onPopupEditRequest: ((URL) -> Void)? = nil,
        onPopupPrivateMessageRequest: ((URL, TopicPageMessageActions) -> Void)? = nil,
        onPopupDeleteRequest: ((URL) -> Void)? = nil,
        onPopupAlertRequest: ((URL) -> Void)? = nil,
        onPopupAlertMailRequest: ((URL) -> Void)? = nil,
        onPopupAvatarSheetRequest: ((TopicPageMessageActions) -> Void)? = nil,
        onPopupProfileRequest: ((URL) -> Void)? = nil,
        onPopupAQRequest: ((TopicPageMessageActions) -> Void)? = nil,
        onPopupBookmarkRequest: ((TopicPageMessageActions) -> Void)? = nil,
        onContentReady: (() -> Void)? = nil,
        onScrollPositionChange: ((Bool) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
        self.anchor = anchor
        self.initialScroll = initialScroll
        self.currentPage = currentPage
        self.maxPage = maxPage
        self.colorScheme = colorScheme
        self.baseBackgroundColor = baseBackgroundColor
        self.themeRevision = themeRevision
        self.messageActionsByIndex = messageActionsByIndex
        self.actionHandler = actionHandler
        self.onWebAction = onWebAction
        self.onPopupQuoteRequest = onPopupQuoteRequest
        self.onPopupEditRequest = onPopupEditRequest
        self.onPopupPrivateMessageRequest = onPopupPrivateMessageRequest
        self.onPopupDeleteRequest = onPopupDeleteRequest
        self.onPopupAlertRequest = onPopupAlertRequest
        self.onPopupAlertMailRequest = onPopupAlertMailRequest
        self.onPopupAvatarSheetRequest = onPopupAvatarSheetRequest
        self.onPopupProfileRequest = onPopupProfileRequest
        self.onPopupAQRequest = onPopupAQRequest
        self.onPopupBookmarkRequest = onPopupBookmarkRequest
        self.onContentReady = onContentReady
        self.onScrollPositionChange = onScrollPositionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let bootstrapThemeScriptSource: String
        if colorScheme == .dark {
            bootstrapThemeScriptSource = """
            (function() {
              var root = document.documentElement;
              if (!root) { return; }
              root.setAttribute('data-theme', 'dark');
              root.style.setProperty('--color-message-background', '#242529');
              root.style.setProperty('--color-message-modo-background', '#4A2E3C');
              root.style.setProperty('--color-separator-new-message', 'rgba(206, 206, 206, 0.30)');
              root.style.setProperty('--color-text', '#CECECE');
              root.style.setProperty('--color-text2', '#3C3C3C');
              root.style.setProperty('--color-background-bars', 'rgba(46, 47, 51, 0.70)');
              root.style.setProperty('--color-searchintra-nextresults', 'rgba(46, 47, 51, 0.90)');
              root.style.setProperty('--color-border-quotation', 'rgba(255, 255, 255, 0.20)');
              root.style.setProperty('--color-border-avatar', '#222222');
              root.style.setProperty('--color-text-pseudo', '#CECECE');
              root.style.setProperty('--color-text-pseudo-bl', 'rgba(206, 206, 206, 0.50)');
              root.style.setProperty('--imagefile-avatar', 'url(avatar_male_gray_on_dark_48x48.png)');
              root.style.setProperty('--imagefile-loadinfo', 'url(loadinfo.net.gif)');
            })();
            """
        } else {
            bootstrapThemeScriptSource = """
            (function() {
              var root = document.documentElement;
              if (!root) { return; }
              root.setAttribute('data-theme', 'light');
            })();
            """
        }

        let contentController = WKUserContentController()
        let bootstrapThemeScript = WKUserScript(
            source: bootstrapThemeScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bootstrapThemeScript)
        contentController.add(context.coordinator, name: "scrollState")

        let scrollTrackingScript = WKUserScript(
            source: """
            (function() {
              function notifyScrollState() {
                var root = document.documentElement || {};
                var body = document.body || {};
                var viewport = window.innerHeight || root.clientHeight || 0;
                var scrollY = window.scrollY || window.pageYOffset || root.scrollTop || body.scrollTop || 0;
                var contentHeight = Math.max(
                  body.scrollHeight || 0,
                  root.scrollHeight || 0,
                  body.offsetHeight || 0,
                  root.offsetHeight || 0
                );
                var distanceToBottom = contentHeight - (scrollY + viewport);
                var atBottom = distanceToBottom <= 2;
                try { window.webkit.messageHandlers.scrollState.postMessage(atBottom); } catch (e) {}
              }

              window.addEventListener('scroll', notifyScrollState, { passive: true });
              window.addEventListener('resize', notifyScrollState, { passive: true });
              window.addEventListener('load', function() {
                setTimeout(notifyScrollState, 0);
                setTimeout(notifyScrollState, 120);
              });
              setTimeout(notifyScrollState, 0);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(scrollTrackingScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = baseBackgroundColor
        webView.scrollView.backgroundColor = baseBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = baseBackgroundColor
        }
        webView.navigationDelegate = context.coordinator
        if #available(iOS 16.0, *) {
            let editMenuInteraction = UIEditMenuInteraction(delegate: context.coordinator)
            webView.addInteraction(editMenuInteraction)
            context.coordinator.editMenuInteraction = editMenuInteraction
        }
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.anchor = anchor
        context.coordinator.initialScroll = initialScroll
        context.coordinator.colorScheme = colorScheme
        context.coordinator.themeRevision = themeRevision
        webView.backgroundColor = baseBackgroundColor
        webView.scrollView.backgroundColor = baseBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = baseBackgroundColor
        }
        print("WebView.updateUIView anchor:", anchor as Any, "fileURL:", fileURL as Any, "baseURL:", readAccessURL as Any)

        if let fileURL = fileURL, let readAccessURL = readAccessURL {
            let shouldReload =
                context.coordinator.loadedFileURL != fileURL ||
                context.coordinator.loadedReadAccessURL != readAccessURL
            let shouldForceThemeApplication = context.coordinator.lastAppliedThemeRevision != themeRevision

            if shouldReload {
                context.coordinator.loadedFileURL = fileURL
                context.coordinator.loadedReadAccessURL = readAccessURL
                context.coordinator.lastAppliedTheme = nil
                context.coordinator.lastAppliedThemeRevision = -1
                context.coordinator.isWaitingForThemeApplication = true
                context.coordinator.didNotifyContentReadyForCurrentLoad = false
                webView.isHidden = true
                webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
            } else {
                context.coordinator.applyThemeIfNeeded(in: webView, force: shouldForceThemeApplication)
                if !context.coordinator.isWaitingForThemeApplication {
                    webView.isHidden = false
                }
            }
        }

    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIEditMenuInteractionDelegate {
        var parent: WebView
        var anchor: String?
        var initialScroll: WebView.InitialScroll?
        var colorScheme: ColorScheme
        var themeRevision: Int
        var loadedFileURL: URL?
        var loadedReadAccessURL: URL?
        var lastAppliedTheme: String?
        var lastAppliedThemeRevision: Int = -1
        var isWaitingForThemeApplication = false
        var didNotifyContentReadyForCurrentLoad = false
        @available(iOS 16.0, *)
        weak var editMenuInteraction: UIEditMenuInteraction?
        private var pendingPopupContext: PendingPopupContext?
        private weak var popupWebView: WKWebView?

        private struct PendingPopupContext {
            let payload: MessageWebPopupPayload
            let actions: TopicPageMessageActions
        }

        private struct PopupMenuEntry {
            let title: String
            let systemImageName: String?
            let isDestructive: Bool
            let handler: () -> Void
        }

        init(_ parent: WebView) {
            self.parent = parent
            self.colorScheme = parent.colorScheme
            self.themeRevision = parent.themeRevision
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WKWebView didFinish. anchor =", anchor as Any, "initialScroll =", String(describing: initialScroll), "url:", webView.url?.absoluteString ?? "nil")
            applyThemeIfNeeded(in: webView, force: true) {
                self.isWaitingForThemeApplication = false
                webView.isHidden = false
                self.notifyContentReadyIfNeeded()
            }

            if let a = anchor, !a.isEmpty {
                // Probe: check if element exists by id or name
                let probe = """
                (function(a){
                  var byId = document.getElementById(a);
                  var byName = document.getElementsByName(a)[0];
                  return 'probe byId='+(!!byId)+' byName='+(!!byName)+' a='+a;
                })('\(a)')
                """
                webView.evaluateJavaScript(probe) { result, error in
                    print("Anchor probe:", result ?? "nil", "error:", error?.localizedDescription ?? "none")
                }

                // Timed scroll with fallback to location.hash
                let js = """
                setTimeout(function(){
                  var a = '\(a)';
                  var el = document.getElementById(a) || document.getElementsByName(a)[0];
                  if (el) {
                    try { el.scrollIntoView({behavior:'auto', block:'start', inline:'nearest'}); }
                    catch(e) { el.scrollIntoView(true); }
                  } else {
                    try { location.hash = '#' + a; } catch(e) {}
                  }
                }, 50);
                """

                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        print("Anchor scroll JS error:", error.localizedDescription)
                    } else {
                        print("Anchor scroll JS executed")
                    }
                }
                // Anchor URLs (for example "last post" links) can land exactly at the
                // browser's natural bottom. When a transparent bottom toolbar overlays
                // content, this hides a small portion of the page. If we detect this
                // state, re-align using the legacy end-of-page marker logic.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    self.adjustBottomAfterAnchorIfNeeded(in: webView)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    self.adjustBottomAfterAnchorIfNeeded(in: webView)
                }
                return
            }

            // No anchor: apply initial scroll if requested
            guard let initial = initialScroll else { return }
            switch initial {
            case .top:
                let js = "setTimeout(function(){ try { window.scrollTo(0, 0); } catch(e) {} }, 50);"
                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        print("Initial scroll JS error:", error.localizedDescription)
                    } else {
                        print("Initial scroll JS executed (\(initial))")
                    }
                }
            case .bottom:
                // Mirror legacy behavior: scroll to the in-page bottom anchor.
                // This avoids persistent UIScrollView insets that create a visible gap
                // when the native bottom toolbar is transparent.
                scrollToBottom(in: webView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.scrollToBottom(in: webView)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    self.scrollToBottom(in: webView)
                }
                print("Initial bottom scroll executed (native)")
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "scrollState" else { return }

            let isAtBottom: Bool
            if let boolValue = message.body as? Bool {
                isAtBottom = boolValue
            } else if let numberValue = message.body as? NSNumber {
                isAtBottom = numberValue.boolValue
            } else {
                return
            }

            DispatchQueue.main.async {
                self.parent.onScrollPositionChange?(isAtBottom)
            }
        }

        private func notifyContentReadyIfNeeded() {
            guard !didNotifyContentReadyForCurrentLoad else { return }
            didNotifyContentReadyForCurrentLoad = true
            parent.onContentReady?()
        }

        func applyThemeIfNeeded(
            in webView: WKWebView,
            force: Bool = false,
            completion: (() -> Void)? = nil
        ) {
            let targetTheme = colorScheme == .dark ? "dark" : "light"
            guard force || lastAppliedTheme != targetTheme else {
                completion?()
                return
            }

            let script = """
            (function() {
              var theme = '\(targetTheme)';
              var root = document.documentElement;
              if (!root) { return; }
              root.setAttribute('data-theme', theme);

              var meta = document.querySelector("meta[name='color-scheme']");
              if (!meta && document.head) {
                meta = document.createElement('meta');
                meta.setAttribute('name', 'color-scheme');
                document.head.appendChild(meta);
              }
              if (meta) {
                meta.setAttribute('content', 'light dark');
              }

              var cssLink = document.getElementById('light-styles');
              if (cssLink) {
                cssLink.setAttribute('href', 'style-liste-light.css');
              }

              var darkOverrides = {
                '--color-message-background': '#242529',
                '--color-message-modo-background': '#4A2E3C',
                '--color-separator-new-message': 'rgba(206, 206, 206, 0.30)',
                '--color-text': '#CECECE',
                '--color-text2': '#3C3C3C',
                '--color-background-bars': 'rgba(46, 47, 51, 0.70)',
                '--color-searchintra-nextresults': 'rgba(46, 47, 51, 0.90)',
                '--color-border-quotation': 'rgba(255, 255, 255, 0.20)',
                '--color-border-avatar': '#222222',
                '--color-text-pseudo': '#CECECE',
                '--color-text-pseudo-bl': 'rgba(206, 206, 206, 0.50)',
                '--imagefile-avatar': 'url(avatar_male_gray_on_dark_48x48.png)',
                '--imagefile-loadinfo': 'url(loadinfo.net.gif)'
              };

              var overrideKeys = Object.keys(darkOverrides);
              var storageKey = '__hfrswiftThemeBaseVars';
              var baseVars = window[storageKey];
              if (!baseVars) {
                baseVars = {};
                overrideKeys.forEach(function(key) {
                  baseVars[key] = root.style.getPropertyValue(key);
                });
                window[storageKey] = baseVars;
              }

              if (theme === 'dark') {
                overrideKeys.forEach(function(key) {
                  root.style.setProperty(key, darkOverrides[key]);
                });
              } else {
                overrideKeys.forEach(function(key) {
                  var baseValue = baseVars[key];
                  if (baseValue && baseValue.trim().length > 0) {
                    root.style.setProperty(key, baseValue);
                  } else {
                    root.style.removeProperty(key);
                  }
                });
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error = error {
                    print("Theme JS error:", error.localizedDescription)
                } else {
                    self?.lastAppliedTheme = targetTheme
                    self?.lastAppliedThemeRevision = self?.themeRevision ?? -1
                    print("Theme JS applied:", targetTheme)
                }
                completion?()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let navigationType = MessageWebNavigationType(navigationAction.navigationType)
            let action = parent.actionHandler.action(
                for: url,
                navigationType: navigationType,
                currentPage: parent.currentPage,
                maxPage: parent.maxPage
            )
            popupWebView = webView

            switch action {
            case .allowNavigation:
                decisionHandler(.allow)
            case .ignore:
                decisionHandler(.cancel)
            case .showPopupMenu(let payload):
                if !presentPopupMenu(for: payload, in: webView) {
                    parent.onWebAction?(action)
                }
                decisionHandler(.cancel)
            case .manageSmileyFavorite(let payload):
                parent.onWebAction?(action)
                decisionHandler(.cancel)
            case .loadPage, .refreshCurrentPage, .presentImageViewer, .openInternalTopic, .openExternalURL:
                parent.onWebAction?(action)
                decisionHandler(.cancel)
            }
        }

        private func presentPopupMenu(for payload: MessageWebPopupPayload, in webView: WKWebView) -> Bool {
            guard let actions = parent.messageActionsByIndex[payload.messageIndex] else {
                return false
            }
            if payload.source == .avatar {
                let actionKinds = MessagePopupMenuPolicy.orderedActionKinds(
                    for: actions,
                    source: .avatar,
                    isQuoteSelectionEnabled: false,
                    messageIndex: payload.messageIndex
                )
                guard !actionKinds.isEmpty else {
                    return false
                }
                parent.onPopupAvatarSheetRequest?(actions)
                return true
            }
            let entries = popupMenuEntries(for: actions, payload: payload, in: webView)
            guard !entries.isEmpty else {
                return false
            }
            let anchor = popupAnchor(for: payload, in: webView)
            let title = popupMenuTitle(for: actions)
            if #available(iOS 16.0, *) {
                guard let editMenuInteraction else {
                    return presentLegacyPopupMenu(
                        entries: entries,
                        title: title,
                        anchor: anchor,
                        in: webView
                    )
                }
                pendingPopupContext = PendingPopupContext(payload: payload, actions: actions)
                let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: anchor.sourcePoint)
                configuration.preferredArrowDirection = anchor.sourcePoint.y <= (anchor.topInset + 40) ? .up : .down
                editMenuInteraction.presentEditMenu(with: configuration)
                return true
            }
            return presentLegacyPopupMenu(
                entries: entries,
                title: title,
                anchor: anchor,
                in: webView
            )
        }

        private struct PopupAnchor {
            let sourcePoint: CGPoint
            let topInset: CGFloat
        }

        private func popupAnchor(for payload: MessageWebPopupPayload, in webView: WKWebView) -> PopupAnchor {
            // Popup offsets come from JS viewport coordinates. Re-apply content/safe-area
            // insets so UIKit menu anchoring matches the tapped point on screen.
            let leftInset = max(webView.safeAreaInsets.left, webView.scrollView.adjustedContentInset.left)
            let topInset = max(webView.safeAreaInsets.top, webView.scrollView.adjustedContentInset.top)

            let fallbackX: CGFloat = payload.source == .avatar ? 38 : max(webView.bounds.width - 15, 0)
            let resolvedX = payload.xOffset.map { CGFloat($0) + leftInset } ?? fallbackX
            var y = CGFloat(payload.yOffset) + topInset
            if y < topInset + 40 {
                y += 44
            }

            let sourcePoint = CGPoint(
                x: min(max(resolvedX, 0), max(webView.bounds.width - 1, 0)),
                y: min(max(y, 0), max(webView.bounds.height - 1, 0))
            )
            return PopupAnchor(sourcePoint: sourcePoint, topInset: topInset)
        }

        private func popupMenuTitle(for actions: TopicPageMessageActions) -> String? {
            if let rawAuthor = actions.authorName {
                let author = rawAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
                if !author.isEmpty {
                    return "Post de \(author)"
                }
            }
            if let rawPostID = actions.postID {
                let postID = rawPostID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !postID.isEmpty {
                    return "Post \(postID)"
                }
            }
            return nil
        }

        private func popupMenuEntries(
            for actions: TopicPageMessageActions,
            payload: MessageWebPopupPayload,
            in webView: WKWebView
        ) -> [PopupMenuEntry] {
            var entries: [PopupMenuEntry] = []
            let isQuoteSelectionEnabled = actions.quoteJS.map { Self.isQuoteSelectionEnabled(from: $0) } ?? false
            let actionKinds = MessagePopupMenuPolicy.orderedActionKinds(
                for: actions,
                source: payload.source,
                isQuoteSelectionEnabled: isQuoteSelectionEnabled,
                messageIndex: payload.messageIndex
            )

            for actionKind in actionKinds {
                switch actionKind {
                case .quote:
                    guard let quoteURL = actions.quoteURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupQuoteRequest?(quoteURL)
                            }
                        )
                    )
                case .quoteSelection:
                    guard let quoteJS = actions.quoteJS else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: {
                                _ = Self.toggleQuoteSelection(from: quoteJS)
                            }
                        )
                    )
                case .edit:
                    guard let editURL = actions.editURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupEditRequest?(editURL)
                            }
                        )
                    )
                case .profile:
                    guard let profileURL = actions.profileURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupProfileRequest?(profileURL)
                            }
                        )
                    )
                case .privateMessage:
                    guard let privateMessageURL = actions.privateMessageURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupPrivateMessageRequest?(privateMessageURL, actions)
                            }
                        )
                    )
                case .blacklist:
                    guard let authorName = actions.authorName else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                guard let self else { return }
                                let message = MessageBlackWhiteListBridge.toggleBlacklist(pseudo: authorName)
                                if let message {
                                    MessageLegacyAlertBridge.showToast(message)
                                }
                                self.parent.onWebAction?(.refreshCurrentPage)
                            }
                        )
                    )
                case .whitelist:
                    guard let authorName = actions.authorName else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                guard let self else { return }
                                let message = MessageBlackWhiteListBridge.toggleWhitelist(pseudo: authorName)
                                if let message {
                                    MessageLegacyAlertBridge.showToast(message)
                                }
                                self.parent.onWebAction?(.refreshCurrentPage)
                            }
                        )
                    )
                case .favorite:
                    guard let favoriteURL = actions.favoriteURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: {
                                Self.performFavoriteAction(favoriteURL)
                            }
                        )
                    )
                case .link:
                    guard let permalinkURL = actions.permalinkURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.presentShareSheet(for: permalinkURL, in: webView)
                            }
                        )
                    )
                case .alert:
                    if let alertURL = actions.alertURL {
                        entries.append(
                            PopupMenuEntry(
                                title: actionKind.title,
                                systemImageName: actionKind.systemImageName,
                                isDestructive: actionKind.isDestructive,
                                handler: { [weak self] in
                                    self?.parent.onPopupAlertRequest?(alertURL)
                                }
                            )
                        )
                    } else if let permalinkURL = actions.permalinkURL {
                        entries.append(
                            PopupMenuEntry(
                                title: actionKind.title,
                                systemImageName: actionKind.systemImageName,
                                isDestructive: actionKind.isDestructive,
                                handler: { [weak self] in
                                    self?.parent.onPopupAlertMailRequest?(permalinkURL)
                                }
                            )
                        )
                    }
                case .aq:
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupAQRequest?(actions)
                            }
                        )
                    )
                case .bookmark:
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupBookmarkRequest?(actions)
                            }
                        )
                    )
                case .delete:
                    guard payload.messageIndex > 0, let editURL = actions.editURL else { continue }
                    entries.append(
                        PopupMenuEntry(
                            title: actionKind.title,
                            systemImageName: actionKind.systemImageName,
                            isDestructive: actionKind.isDestructive,
                            handler: { [weak self] in
                                self?.parent.onPopupDeleteRequest?(editURL)
                            }
                        )
                    )
                }
            }

            return entries
        }

        private func presentLegacyPopupMenu(
            entries: [PopupMenuEntry],
            title: String?,
            anchor: PopupAnchor,
            in webView: WKWebView
        ) -> Bool {
            guard let ownerController = closestViewController(from: webView),
                  ownerController.presentedViewController == nil else {
                return false
            }

            let alert = UIAlertController(
                title: title,
                message: nil,
                preferredStyle: .actionSheet
            )

            guard !entries.isEmpty else {
                return false
            }

            for entry in entries {
                let style: UIAlertAction.Style = entry.isDestructive ? .destructive : .default
                alert.addAction(
                    UIAlertAction(title: entry.title, style: style) { _ in
                        entry.handler()
                    }
                )
            }
            alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))

            if let popover = alert.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = CGRect(
                    x: anchor.sourcePoint.x,
                    y: anchor.sourcePoint.y,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = anchor.sourcePoint.y <= (anchor.topInset + 40) ? .up : .down
            }

            ownerController.present(alert, animated: true)
            return true
        }

        private static func quoteComponents(from quoteJS: String) -> (cookieName: String, quoteID: String)? {
            guard
                let openingParenthesis = quoteJS.firstIndex(of: "("),
                let closingParenthesis = quoteJS[openingParenthesis...].firstIndex(of: ")")
            else {
                return nil
            }

            let argumentRange = quoteJS.index(after: openingParenthesis)..<closingParenthesis
            let rawArguments = quoteJS[argumentRange]
            let values = rawArguments
                .split(separator: ",", omittingEmptySubsequences: false)
                .map {
                    $0
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "'", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                }
                .filter { !$0.isEmpty }

            guard values.count >= 4 else {
                return nil
            }

            let cookieName = "quotes\(values[0])-\(values[1])-\(values[2])"
            return (cookieName, values[3])
        }

        private static func readCookieValue(named name: String) -> String {
            let storage = HTTPCookieStorage.shared
            guard let cookies = storage.cookies else {
                return ""
            }
            let now = Date()
            for cookie in cookies where cookie.name == name {
                if let expires = cookie.expiresDate, expires <= now {
                    continue
                }
                return cookie.value
            }
            return ""
        }

        private static func writeCookie(name: String, value: String) {
            guard
                let cookie = HTTPCookie(properties: [
                    .name: name,
                    .value: value,
                    .domain: ".hardware.fr",
                    .path: "/",
                    .expires: Date().addingTimeInterval(60 * 60)
                ])
            else {
                return
            }
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        private static func deleteCookie(named name: String) {
            let storage = HTTPCookieStorage.shared
            storage.cookies?.filter { $0.name == name }.forEach { storage.deleteCookie($0) }
        }

        private static func isQuoteSelectionEnabled(from quoteJS: String) -> Bool {
            guard let components = quoteComponents(from: quoteJS) else {
                return false
            }
            let current = readCookieValue(named: components.cookieName)
            return current.contains("|\(components.quoteID)")
        }

        @discardableResult
        private static func toggleQuoteSelection(from quoteJS: String) -> Bool? {
            guard let components = quoteComponents(from: quoteJS) else {
                return nil
            }

            let marker = "|\(components.quoteID)"
            var quotes = readCookieValue(named: components.cookieName)
            let isSelected = quotes.contains(marker)

            if isSelected {
                quotes = quotes.replacingOccurrences(of: marker, with: "")
            } else {
                quotes += marker
            }

            if quotes.isEmpty {
                deleteCookie(named: components.cookieName)
            } else {
                writeCookie(name: components.cookieName, value: quotes)
            }
            return !isSelected
        }

        private static func performFavoriteAction(_ url: URL) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            URLSession.shared.dataTask(with: request) { data, _, error in
                if error != nil {
                    DispatchQueue.main.async {
                        MessageLegacyAlertBridge.showToast("Erreur réseau")
                    }
                    return
                }

                let response = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let message = MessagePopupActionSupport.favoriteResponseMessage(from: response) ?? "Favori mis à jour"
                DispatchQueue.main.async {
                    MessageLegacyAlertBridge.showToast(message)
                }
            }.resume()
        }

        private func presentShareSheet(for permalinkURL: URL, in webView: WKWebView) {
            guard let ownerController = closestViewController(from: webView) else {
                return
            }

            let activityController = UIActivityViewController(
                activityItems: [permalinkURL.absoluteString],
                applicationActivities: nil
            )
            activityController.excludedActivityTypes = [.airDrop]
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = CGRect(
                    x: webView.bounds.midX,
                    y: webView.bounds.midY,
                    width: 1,
                    height: 1
                )
            }
            ownerController.present(activityController, animated: true)
        }

        private func presentAQPrompt(for actions: TopicPageMessageActions, in webView: WKWebView) {
            guard
                let ownerController = closestViewController(from: webView),
                ownerController.presentedViewController == nil,
                let topicID = actions.topicID,
                let topicTitle = actions.topicTitle,
                let postID = MessagePopupActionSupport.numericPostID(from: actions.postID),
                let permalinkURL = actions.permalinkURL
            else {
                MessageLegacyAlertBridge.showToast("Données AQ incomplètes")
                return
            }

            Task { @MainActor in
                let alreadySignaled = await MessagePopupActionSupport.isAQAlreadySignaled(topicID: topicID, postID: postID)
                if alreadySignaled == true {
                    MessageLegacyAlertBridge.showToast("Post déjà signalé")
                    return
                }
                if alreadySignaled == nil {
                    MessageLegacyAlertBridge.showTitleAndMessage(
                        title: "Erreur réseau",
                        message: "Création d'AQ impossible"
                    )
                    return
                }

                let author = actions.authorName ?? ""
                let message = "Créer une Alerte Qualitay sur le post de \(author)"
                let alert = UIAlertController(
                    title: "Alerte Qualitay ?",
                    message: message,
                    preferredStyle: .alert
                )
                alert.addTextField { textField in
                    textField.placeholder = "Ajoutez un titre"
                    textField.clearButtonMode = .whileEditing
                }
                alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
                alert.addAction(
                    UIAlertAction(title: "Créer", style: .default) { _ in
                        let title = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !title.isEmpty else { return }
                        let authorName = actions.authorName ?? ""
                        Task { @MainActor in
                            let result = await MessagePopupActionSupport.createAQ(
                                title: title,
                                topicID: topicID,
                                topicTitle: topicTitle,
                                postID: postID,
                                postURL: permalinkURL.absoluteString,
                                author: authorName
                            )
                            switch result {
                            case .success:
                                MessageLegacyAlertBridge.showTitleAndMessage(
                                    title: "Hooray !",
                                    message: "Alerte Qualitay créée."
                                )
                            case .failure(let code):
                                MessageLegacyAlertBridge.showTitleAndMessage(
                                    title: "Oups !",
                                    message: "Code erreur \(code)"
                                )
                            case .networkError:
                                MessageLegacyAlertBridge.showTitleAndMessage(
                                    title: "Erreur réseau",
                                    message: "Création d'AQ impossible"
                                )
                            }
                        }
                    }
                )

                ownerController.present(alert, animated: true)
            }
        }

        private func presentBookmarkPrompt(for actions: TopicPageMessageActions, in webView: WKWebView) {
            guard
                let ownerController = closestViewController(from: webView),
                ownerController.presentedViewController == nil,
                let topicID = actions.topicID,
                let topicCategory = actions.topicCategory,
                let postID = MessagePopupActionSupport.numericPostID(from: actions.postID)
            else {
                MessageLegacyAlertBridge.showToast("Données bookmark incomplètes")
                return
            }

            if MessagePopupActionSupport.hasBookmark(topicID: topicID, postID: postID) {
                MessageLegacyAlertBridge.showToast("Post déjà dans les bookmarks")
                return
            }

            let author = actions.authorName ?? ""
            let alert = UIAlertController(
                title: "Bookmark",
                message: "Créer un bookmark sur le post de \(author) ?",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = "Ajoutez un titre"
                textField.clearButtonMode = .whileEditing
            }
            alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
            alert.addAction(
                UIAlertAction(title: "Créer", style: .default) { _ in
                    let title = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !title.isEmpty else { return }
                    let created = MessagePopupActionSupport.createBookmark(
                        topicID: topicID,
                        topicCategory: topicCategory,
                        postID: postID,
                        title: title,
                        author: author
                    )
                    if created {
                        MessageLegacyAlertBridge.showTitleAndMessage(title: "Hooray !", message: "Bookmark créé")
                    } else {
                        MessageLegacyAlertBridge.showTitleAndMessage(
                            title: "Oups !",
                            message: "Erreur à la création du bookmark"
                        )
                    }
                }
            )

            ownerController.present(alert, animated: true)
        }

        private func presentSmileyFavoriteMenu(
            for payload: MessageWebSmileyPayload,
            in webView: WKWebView
        ) -> Bool {
            guard let ownerController = closestViewController(from: webView),
                  ownerController.presentedViewController == nil else {
                return false
            }

            let isFavorite = MessageSmileyFavoritesBridge.isFavoriteFromApp(code: payload.code)
            let actionTitle = isFavorite ? "Retirer des favoris" : "Ajouter aux favoris"

            let alert = UIAlertController(
                title: payload.code,
                message: nil,
                preferredStyle: .actionSheet
            )

            alert.addAction(
                UIAlertAction(title: actionTitle, style: .default) { _ in
                    _ = MessageSmileyFavoritesBridge.updateFavorite(
                        code: payload.code,
                        imageURL: payload.imageURL,
                        add: !isFavorite
                    )
                }
            )
            alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))

            if let popover = alert.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = CGRect(
                    x: webView.bounds.midX,
                    y: webView.bounds.midY,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }

            ownerController.present(alert, animated: true)
            return true
        }

        private enum MessageLegacyAlertBridge {
            static func showToast(_ title: String) {
                guard let alertClass = NSClassFromString("HFRAlertView") as? NSObject.Type else {
                    return
                }
                let selector = NSSelectorFromString("DisplayAlertViewWithTitle:forDuration:")
                guard alertClass.responds(to: selector) else {
                    return
                }

                typealias Function = @convention(c) (AnyObject, Selector, NSString, Int) -> Void
                let implementation = alertClass.method(for: selector)
                let function = unsafeBitCast(implementation, to: Function.self)
                function(alertClass, selector, title as NSString, 1)
            }

            static func showTitleAndMessage(title: String, message: String) {
                guard let alertClass = NSClassFromString("HFRAlertView") as? NSObject.Type else {
                    return
                }
                let selector = NSSelectorFromString("DisplayAlertViewWithTitle:andMessage:forDuration:")
                guard alertClass.responds(to: selector) else {
                    return
                }

                typealias Function = @convention(c) (AnyObject, Selector, NSString, NSString, Int) -> Void
                let implementation = alertClass.method(for: selector)
                let function = unsafeBitCast(implementation, to: Function.self)
                function(alertClass, selector, title as NSString, message as NSString, 1)
            }
        }

        private enum MessageBlackWhiteListBridge {
            static func toggleBlacklist(pseudo: String) -> String? {
                guard let object = sharedObject() else {
                    return nil
                }

                let isBLSelector = NSSelectorFromString("isBL:")
                guard object.responds(to: isBLSelector) else {
                    return nil
                }
                typealias IsBLFunction = @convention(c) (AnyObject, Selector, NSString) -> Bool
                let isBLImplementation = object.method(for: isBLSelector)
                let isBLFunction = unsafeBitCast(isBLImplementation, to: IsBLFunction.self)
                let isBL = isBLFunction(object, isBLSelector, pseudo as NSString)

                if isBL {
                    let selector = NSSelectorFromString("removeFromBlackList:andSave:")
                    guard object.responds(to: selector) else {
                        return nil
                    }
                    typealias Function = @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool
                    let implementation = object.method(for: selector)
                    let function = unsafeBitCast(implementation, to: Function.self)
                    let result = function(object, selector, pseudo as NSString, true)
                    return result
                        ? "\(pseudo) a été supprimé de la liste noire"
                        : "Erreur! \(pseudo) n'a pas pu être supprimé de la liste noire"
                }

                let selector = NSSelectorFromString("addToBlackList:andSave:")
                guard object.responds(to: selector) else {
                    return nil
                }
                typealias Function = @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool
                let implementation = object.method(for: selector)
                let function = unsafeBitCast(implementation, to: Function.self)
                let result = function(object, selector, pseudo as NSString, true)
                return result
                    ? "BIM! \(pseudo) ajouté à la liste noire"
                    : "Erreur! \(pseudo) n'a pas pu être ajouté à la liste noire"
            }

            static func toggleWhitelist(pseudo: String) -> String? {
                guard let object = sharedObject() else {
                    return nil
                }
                let isWLSelector = NSSelectorFromString("isWL:")
                guard object.responds(to: isWLSelector) else {
                    return nil
                }
                typealias IsWLFunction = @convention(c) (AnyObject, Selector, NSString) -> Bool
                let isWLImplementation = object.method(for: isWLSelector)
                let isWLFunction = unsafeBitCast(isWLImplementation, to: IsWLFunction.self)
                let isWL = isWLFunction(object, isWLSelector, pseudo as NSString)

                if isWL {
                    let selector = NSSelectorFromString("removeFromWhiteList:")
                    guard object.responds(to: selector) else {
                        return nil
                    }
                    typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Bool
                    let implementation = object.method(for: selector)
                    let function = unsafeBitCast(implementation, to: Function.self)
                    _ = function(object, selector, pseudo as NSString)
                    return "OH NOES ! \(pseudo) a été supprimé de la love list"
                }

                let selector = NSSelectorFromString("addToWhiteList:")
                guard object.responds(to: selector) else {
                    return nil
                }
                typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Void
                let implementation = object.method(for: selector)
                let function = unsafeBitCast(implementation, to: Function.self)
                function(object, selector, pseudo as NSString)
                return "BOUM BOUM ! \(pseudo) ajouté à la love list ♥"
            }

            private static func sharedObject() -> NSObject? {
                guard let klass = NSClassFromString("BlackList") as? NSObject.Type else {
                    return nil
                }
                let selector = NSSelectorFromString("shared")
                guard klass.responds(to: selector),
                      let unmanaged = klass.perform(selector) else {
                    return nil
                }
                return unmanaged.takeUnretainedValue() as? NSObject
            }
        }

        private enum MessageSmileyFavoritesBridge {
            static func isFavoriteFromApp(code: String) -> Bool {
                guard let cache = sharedCacheObject() else {
                    return false
                }
                let selector = NSSelectorFromString("isFavoriteSmileyFromApp:")
                guard cache.responds(to: selector) else {
                    return false
                }

                typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Bool
                let implementation = cache.method(for: selector)
                let function = unsafeBitCast(implementation, to: Function.self)
                return function(cache, selector, code as NSString)
            }

            static func updateFavorite(code: String, imageURL: String, add: Bool) -> Bool {
                guard let cache = sharedCacheObject() else {
                    return false
                }
                let selector = NSSelectorFromString("AddAndSaveDicFavoritesApp:source:addSmiley:")
                guard cache.responds(to: selector) else {
                    return false
                }

                typealias Function = @convention(c) (AnyObject, Selector, NSString, NSString, Bool) -> Bool
                let implementation = cache.method(for: selector)
                let function = unsafeBitCast(implementation, to: Function.self)
                return function(cache, selector, code as NSString, imageURL as NSString, add)
            }

            private static func sharedCacheObject() -> NSObject? {
                guard let cacheClass = NSClassFromString("SmileyCache") as? NSObject.Type else {
                    return nil
                }
                let sharedSelector = NSSelectorFromString("shared")
                guard cacheClass.responds(to: sharedSelector),
                      let unmanaged = cacheClass.perform(sharedSelector) else {
                    return nil
                }
                return unmanaged.takeUnretainedValue() as? NSObject
            }
        }

        private func closestViewController(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController {
                    return controller
                }
                responder = current.next
            }
            return nil
        }

        private func scrollToBottom(in webView: WKWebView) {
            let script = """
            (function() {
              var marker = document.getElementById('endofpagetoolbar')
                || document.getElementById('endofpage')
                || document.getElementById('bas');

              if (marker && typeof marker.offsetTop === 'number') {
                window.scrollTo(0, marker.offsetTop);
                return true;
              }

              var root = document.documentElement || {};
              var body = document.body || {};
              var y = Math.max(
                body.scrollHeight || 0,
                root.scrollHeight || 0,
                body.offsetHeight || 0,
                root.offsetHeight || 0
              );
              window.scrollTo(0, y);
              return true;
            })();
            """

            webView.evaluateJavaScript(script) { _, error in
                if error != nil {
                    let scrollView = webView.scrollView
                    let minOffsetY = -scrollView.adjustedContentInset.top
                    let maxOffsetY = max(
                        minOffsetY,
                        scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
                    )
                    let targetOffset = CGPoint(x: -scrollView.adjustedContentInset.left, y: maxOffsetY)
                    scrollView.setContentOffset(targetOffset, animated: false)
                }
            }
        }

        private func adjustBottomAfterAnchorIfNeeded(in webView: WKWebView) {
            let script = """
            (function() {
              var root = document.documentElement || {};
              var body = document.body || {};
              var viewport = window.innerHeight || root.clientHeight || 0;
              var scrollY = window.scrollY || window.pageYOffset || root.scrollTop || body.scrollTop || 0;
              var contentHeight = Math.max(
                body.scrollHeight || 0,
                root.scrollHeight || 0,
                body.offsetHeight || 0,
                root.offsetHeight || 0
              );
              var distanceToBottom = contentHeight - (scrollY + viewport);
              return distanceToBottom <= 2;
            })();
            """

            webView.evaluateJavaScript(script) { result, error in
                guard error == nil else { return }

                let isAtNaturalBottom: Bool
                if let boolValue = result as? Bool {
                    isAtNaturalBottom = boolValue
                } else if let numberValue = result as? NSNumber {
                    isAtNaturalBottom = numberValue.boolValue
                } else {
                    isAtNaturalBottom = false
                }

                guard isAtNaturalBottom else { return }
                self.scrollToBottom(in: webView)
            }
        }

        @available(iOS 16.0, *)
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let context = pendingPopupContext, let webView = popupWebView else {
                return nil
            }

            let entries = popupMenuEntries(for: context.actions, payload: context.payload, in: webView)
            let children: [UIMenuElement] = entries.map { entry in
                let attributes: UIMenuElement.Attributes = entry.isDestructive ? .destructive : []
                return UIAction(
                    title: entry.title,
                    image: entry.systemImageName.flatMap { UIImage(systemName: $0) },
                    identifier: nil,
                    attributes: attributes
                ) { _ in
                    entry.handler()
                }
            }
            if children.isEmpty {
                return nil
            }

            let menuTitle = popupMenuTitle(for: context.actions) ?? ""
            return UIMenu(title: menuTitle, children: children)
        }
    }
}

private struct SafariInAppView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private extension MessageWebNavigationType {
    init(_ navigationType: WKNavigationType) {
        switch navigationType {
        case .linkActivated:
            self = .linkActivated
        case .formSubmitted:
            self = .formSubmitted
        case .backForward:
            self = .backForward
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
        case .other:
            self = .other
        @unknown default:
            self = .unknown
        }
    }
}

struct MessagesView: View {
    private enum ComposerPrefillMode {
        case quote
        case edit

        var loadingLabel: String {
            switch self {
            case .quote:
                return "Chargement de la citation..."
            case .edit:
                return "Chargement de l'edition..."
            }
        }

        var alertTitle: String {
            switch self {
            case .quote:
                return "Citation impossible"
            case .edit:
                return "Edition impossible"
            }
        }
    }

    private struct SafariDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct SmileySheetState: Identifiable {
        let id = UUID()
        let payload: MessageWebSmileyPayload
        let isFavorite: Bool
    }

    private struct AvatarActionSheetState: Identifiable {
        let id = UUID()
        let actions: TopicPageMessageActions
    }

    private struct PhotoViewerDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct ModerationAlertDestination: Identifiable {
        let id = UUID()
        let preparedForm: ModerationAlertPreparedForm
    }

    private enum ComposerPresentationKind {
        case reply
        case edit
        case privateMessage

        var title: String {
            switch self {
            case .reply:
                return "Reply"
            case .edit:
                return "Edition"
            case .privateMessage:
                return "Nouv. Message"
            }
        }

        var shouldRefreshTopicOnSuccess: Bool {
            switch self {
            case .privateMessage:
                return false
            case .reply, .edit:
                return true
            }
        }

        var successToastText: String {
            switch self {
            case .privateMessage:
                return "Message privé envoyé"
            case .reply, .edit:
                return "Hooray"
            }
        }
    }

    private struct AQPromptState: Identifiable {
        let id = UUID()
        let topicID: String
        let topicTitle: String
        let postID: String
        let postURL: URL
        let authorName: String
    }

    private struct BookmarkPromptState: Identifiable {
        let id = UUID()
        let topicID: String
        let topicCategory: String
        let postID: String
        let authorName: String
    }

    let topic: Topic
    let curPage: Int // Stored again as it can be updated when reloading the topic
    let maxPage: Int
    let separatorNewMessages: Bool
    let initialLoadScroll: WebView.InitialScroll?
    let navigationDepth: Int
    let topicPageLoader: TopicPageLoading
    let topicPageRenderer: TopicPageRendering
    let replyQuoteTemplateLoader: ReplyQuoteTemplateLoading
    let messageDeletionService: any MessageDeletionService
    let moderationAlertService: any ModerationAlertService

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appTheme = AppThemeStore.shared
    @State private var page: Int
    @State private var availableMaxPage: Int
    @State private var topicDisplayTitle: String
    @State private var fileURL: URL?
    @State private var cacheURL: URL?
    @State private var errorMessage: String?
    @State private var anchor: String?
    @State private var initialScroll: WebView.InitialScroll?
    @State private var topicAnswerURL: URL?
    @State private var composerSubmitURL: URL?
    @State private var messageActionsByIndex: [Int: TopicPageMessageActions] = [:]
    @AppStorage("composerDraftText") private var composerDraftText: String = ""
    @State private var isComposerPresented = false
    @State private var isPresentingComposer = false  // This will be removed now
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var isComposerMinimized = false
    @State private var animateLoadingSpinner = false
    @State private var isPagePickerPresented = false
    @State private var pagePickerInput: String = ""
    @State private var linkedTopic: Topic?
    @State private var navigateToLinkedTopic = false
    @State private var safariDestination: SafariDestination?
    @State private var smileySheetState: SmileySheetState?
    @State private var avatarActionSheetState: AvatarActionSheetState?
    @State private var photoViewerDestination: PhotoViewerDestination?
    @State private var isLoadingQuoteTemplate = false
    @State private var activeComposerPrefillMode: ComposerPrefillMode = .quote
    @State private var activeComposerPresentationKind: ComposerPresentationKind = .reply
    @State private var composerNavigationTitle: String = ComposerPresentationKind.reply.title
    @State private var composerRequiresSubject = false
    @State private var composerRecipientName: String?
    @State private var quoteTemplateErrorMessage: String?
    @State private var lastFailedQuoteTemplateURL: URL?
    @State private var lastFailedComposerPrefillMode: ComposerPrefillMode = .quote
    @State private var moderationAlertDestination: ModerationAlertDestination?
    @State private var isPreparingModerationAlert = false
    @State private var moderationAlertErrorMessage: String?
    @State private var pendingAlertMailURL: URL?
    @State private var pendingDeleteEditURL: URL?
    @State private var deleteErrorMessage: String?
    @State private var isDeletingMessage = false
    @State private var aqPromptState: AQPromptState?
    @State private var bookmarkPromptState: BookmarkPromptState?
    @State private var popupActionErrorMessage: String?
    @State private var isPreparingAQPrompt = false
    @State private var pollData: PollData?
    @State private var isPollSheetPresented = false
    @State private var showWebViewLoadCover = true
    @State private var isWebContentAtBottom = false
    @State private var pendingPostedReply: ReplyPostingResult?
    @State private var showPostSuccessToast = false
    @State private var postSuccessToastText = "Hooray"
    // Remove the unused
    // @State private var isPresentingAddMessage = false

    private var themePalette: AppThemePalette {
        appTheme.palette
    }

    init(
        topic: Topic,
        curPage: Int,
        maxPage: Int,
        separatorNewMessages: Bool,
        initialLoadScroll: WebView.InitialScroll? = nil,
        navigationDepth: Int = 0,
        topicPageLoader: TopicPageLoading = ObjCTopicPageLoader(),
        topicPageRenderer: TopicPageRendering = OfflineStorageTopicPageRenderer(),
        replyQuoteTemplateLoader: ReplyQuoteTemplateLoading = ForumReplyQuoteTemplateService(),
        messageDeletionService: any MessageDeletionService = ForumMessageDeletionService(),
        moderationAlertService: any ModerationAlertService = ForumModerationAlertService()
    ) {
        self.topic = topic
        self.curPage = curPage
        self.maxPage = maxPage
        self.separatorNewMessages = separatorNewMessages
        self.initialLoadScroll = initialLoadScroll
        self.navigationDepth = navigationDepth
        self.topicPageLoader = topicPageLoader
        self.topicPageRenderer = topicPageRenderer
        self.replyQuoteTemplateLoader = replyQuoteTemplateLoader
        self.messageDeletionService = messageDeletionService
        self.moderationAlertService = moderationAlertService
        self._page = State(initialValue: curPage)
        self._availableMaxPage = State(initialValue: max(max(maxPage, curPage), 1))
        self._topicDisplayTitle = State(initialValue: topic._aTitle ?? "")
        self._initialScroll = State(initialValue: initialLoadScroll)

        // extraire l’ancre (#xxxx) si présente
        if let url = URL(string: topic.aURL), let fragment = url.fragment {
            self._anchor = State(initialValue: fragment)
            print("INIT extracted anchor:", fragment)
        }
    }

    private func urlForPage(_ page: Int) -> String {
        let baseURL = topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfFirstPage ?? ""
        print("Current url: \(baseURL)")
        return TopicPageURLRouting.replacingPage(in: baseURL, page: page)
    }

    private var currentMaxPage: Int {
        max(max(availableMaxPage, page), 1)
    }

    private func synchronizeTopicPagination(currentPage resolvedPage: Int, maxPage resolvedMaxPage: Int) {
        topic.curTopicPage = Int32(resolvedPage)
        topic.maxTopicPage = Int32(resolvedMaxPage)

        let baseURL = topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfFirstPage ?? ""
        guard !baseURL.isEmpty else { return }

        let currentPageURL = TopicPageURLRouting.replacingPage(in: baseURL, page: resolvedPage)
        let lastPageURL = TopicPageURLRouting.replacingPage(in: baseURL, page: resolvedMaxPage)

        topic.aURL = currentPageURL
        topic.aURLOfLastPage = lastPageURL
        if topic.aURLOfFirstPage == nil || topic.aURLOfFirstPage.isEmpty {
            topic.aURLOfFirstPage = TopicPageURLRouting.replacingPage(in: baseURL, page: 1)
        }
    }

    private func applyLoadedPagination(from content: TopicPageContent, requestedPage: Int) {
        let resolvedPage = max(content.currentPage ?? requestedPage, 1)
        let parsedMaxPage = content.maxPage ?? currentMaxPage
        let resolvedMaxPage = max(max(parsedMaxPage, resolvedPage), 1)

        if page != resolvedPage {
            page = resolvedPage
        }
        if availableMaxPage != resolvedMaxPage {
            availableMaxPage = resolvedMaxPage
        }
        synchronizeTopicPagination(currentPage: resolvedPage, maxPage: resolvedMaxPage)
    }

    private func loadPage(_ page: Int) {
        let url = urlForPage(page)
        print("loadPage(\(page)) url:", url, "current anchor:", self.anchor as Any)
        showWebViewLoadCover = true
        isWebContentAtBottom = false
        errorMessage = nil
        messageActionsByIndex = [:]
        topicPageLoader.fetchTopicPage(url: url, anchor: self.anchor) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                case .success(let content):
                    do {
                        let rendered = try topicPageRenderer.render(html: content.html)
                        self.fileURL = rendered.fileURL
                        self.cacheURL = rendered.readAccessURL
                        if self.fileURL == nil || self.cacheURL == nil {
                            self.errorMessage = "Failed to render topic page to local file."
                        }
                    } catch {
                        self.fileURL = nil
                        self.cacheURL = nil
                        self.errorMessage = error.localizedDescription
                    }
                    applyLoadedPagination(from: content, requestedPage: page)
                    self.topicAnswerURL = content.topicAnswerURL
                    self.messageActionsByIndex = content.messageActionsByIndex
                    self.pollData = content.pollData
                    if let newTitle = content.topicTitle, !newTitle.isEmpty {
                        self.topicDisplayTitle = newTitle
                    }
                }
            }
        }
    }

    private func loadDirectURL(_ topicURL: String, initialScroll: WebView.InitialScroll? = nil) {
        guard !topicURL.isEmpty else { return }
        self.anchor = URL(string: topicURL)?.fragment
        self.initialScroll = initialScroll
        showWebViewLoadCover = true
        isWebContentAtBottom = false
        self.errorMessage = nil
        messageActionsByIndex = [:]

        topicPageLoader.fetchTopicPage(url: topicURL, anchor: self.anchor) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                case .success(let content):
                    do {
                        let rendered = try topicPageRenderer.render(html: content.html)
                        self.fileURL = rendered.fileURL
                        self.cacheURL = rendered.readAccessURL
                    } catch {
                        self.fileURL = nil
                        self.cacheURL = nil
                        self.errorMessage = error.localizedDescription
                    }
                    let requestedPage = content.currentPage
                        ?? TopicPageURLRouting.pageNumber(from: topicURL)
                        ?? self.page
                    applyLoadedPagination(from: content, requestedPage: requestedPage)
                    self.topicAnswerURL = content.topicAnswerURL
                    self.messageActionsByIndex = content.messageActionsByIndex
                    self.pollData = content.pollData
                    if let newTitle = content.topicTitle, !newTitle.isEmpty {
                        self.topicDisplayTitle = newTitle
                    }
                }
            }
        }
    }

    private func normalizedForumTopicURLString(from url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()

        guard (scheme == "http" || scheme == "https"), host == "forum.hardware.fr" else {
            return url.absoluteString
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var relativeURL = url.path
        if let query = components?.percentEncodedQuery, !query.isEmpty {
            relativeURL += "?\(query)"
        }
        if let fragment = components?.percentEncodedFragment, !fragment.isEmpty {
            relativeURL += "#\(fragment)"
        }

        return relativeURL.isEmpty ? "/" : relativeURL
    }

    private func openInternalTopic(_ url: URL) {
        let topicURLString = normalizedForumTopicURLString(from: url)
        guard !topicURLString.isEmpty else { return }

        let pageFromURL = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value
            .flatMap(Int.init) ?? 1
        let boundedPage = max(pageFromURL, 1)
        let derivedMaxPage = max(currentMaxPage, boundedPage)

        let topicForNavigation = Topic()
        topicForNavigation._aTitle = topic._aTitle
        topicForNavigation.aURL = topicURLString
        topicForNavigation.aURLOfLastPage = topicURLString
        topicForNavigation.curTopicPage = Int32(boundedPage)
        topicForNavigation.maxTopicPage = Int32(derivedMaxPage)

        linkedTopic = topicForNavigation
        navigateToLinkedTopic = true
    }

    private func webViewInitialScroll(_ value: MessageWebInitialScroll) -> WebView.InitialScroll {
        switch value {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    private func handleWebAction(_ action: MessageWebAction) {
        switch action {
        case .allowNavigation:
            break
        case .ignore:
            break
        case .loadPage(let targetPage, let initialScroll):
            navigateToPage(targetPage, initialScroll: webViewInitialScroll(initialScroll))
        case .refreshCurrentPage:
            loadPage(page)
        case .showPopupMenu:
            break
        case .manageSmileyFavorite(let payload):
            let isFavorite = SmileyFavoritesBridge.isFavoriteFromApp(code: payload.code)
            smileySheetState = SmileySheetState(payload: payload, isFavorite: isFavorite)
        case .presentImageViewer(let url):
            photoViewerDestination = PhotoViewerDestination(url: normalizeImageViewerURL(url))
        case .openInternalTopic(let url):
            if url.scheme?.lowercased() == "file" {
                loadDirectURL(url.absoluteString)
            } else {
                openInternalTopic(url)
            }
        case .openExternalURL(let url):
            safariDestination = SafariDestination(url: url)
        }
    }

    private func normalizeImageViewerURL(_ url: URL) -> URL {
        let raw = url.absoluteString
        let normalized: String
        if raw.contains("https://img3.super-h.fr/images/") {
            normalized = raw.replacingOccurrences(of: ".th.", with: ".")
        } else if raw.contains("reho.st/thumb/") {
            normalized = raw.replacingOccurrences(of: "reho.st/thumb/", with: "reho.st/")
        } else if raw.contains("rehost.diberie.com/Picture/Get/t/") {
            normalized = raw.replacingOccurrences(of: "rehost.diberie.com/Picture/Get/t/", with: "rehost.diberie.com/Picture/Get/f/")
        } else {
            normalized = raw
        }
        return URL(string: normalized) ?? url
    }

    private func updateSmileyFavorite(code: String, imageURL: String, add: Bool) -> Bool {
        SmileyFavoritesBridge.updateFavorite(code: code, imageURL: imageURL, add: add)
    }

    private func fetchSmileyKeywords(code: String) async -> Result<[String], Error> {
        let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        guard let url = URL(string: "https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=\(encodedCode)") else {
            return .failure(
                NSError(
                    domain: "MessagesView",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "URL invalide."]
                )
            )
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return .failure(
                    NSError(
                        domain: "MessagesView",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Réponse serveur invalide."]
                    )
                )
            }

            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return .failure(
                    NSError(
                        domain: "MessagesView",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Réponse illisible."]
                    )
                )
            }

            let pattern = #"name\s*=\s*"keywords0"[^>]*value\s*=\s*"([^"]*)""#
            guard
                let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..<html.endIndex, in: html)),
                match.numberOfRanges > 1,
                let valueRange = Range(match.range(at: 1), in: html)
            else {
                return .failure(
                    NSError(
                        domain: "MessagesView",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Aucun mot clé trouvé."]
                    )
                )
            }

            let rawValue = String(html[valueRange])
            let decodedEntities = rawValue
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&#x2F;", with: "/")
                .replacingOccurrences(of: "&#47;", with: "/")

            let keywords = decodedEntities
                .replacingOccurrences(of: ",", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }

            if keywords.isEmpty {
                return .failure(
                    NSError(
                        domain: "MessagesView",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Aucun mot clé trouvé."]
                    )
                )
            }
            return .success(keywords)
        } catch {
            return .failure(error)
        }
    }

    private enum SmileyFavoritesBridge {
        static func isFavoriteFromApp(code: String) -> Bool {
            guard let cache = sharedCacheObject() else {
                return false
            }
            let selector = NSSelectorFromString("isFavoriteSmileyFromApp:")
            guard cache.responds(to: selector) else {
                return false
            }

            typealias Function = @convention(c) (AnyObject, Selector, NSString) -> Bool
            let implementation = cache.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            return function(cache, selector, code as NSString)
        }

        static func updateFavorite(code: String, imageURL: String, add: Bool) -> Bool {
            guard let cache = sharedCacheObject() else {
                return false
            }
            let selector = NSSelectorFromString("AddAndSaveDicFavoritesApp:source:addSmiley:")
            guard cache.responds(to: selector) else {
                return false
            }

            typealias Function = @convention(c) (AnyObject, Selector, NSString, NSString, Bool) -> Bool
            let implementation = cache.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            return function(cache, selector, code as NSString, imageURL as NSString, add)
        }

        private static func sharedCacheObject() -> NSObject? {
            guard let cacheClass = NSClassFromString("SmileyCache") as? NSObject.Type else {
                return nil
            }
            let sharedSelector = NSSelectorFromString("shared")
            guard cacheClass.responds(to: sharedSelector),
                  let unmanaged = cacheClass.perform(sharedSelector) else {
                return nil
            }
            return unmanaged.takeUnretainedValue() as? NSObject
        }
    }

    private var isQuoteTemplateAlertPresented: Binding<Bool> {
        Binding(
            get: { quoteTemplateErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    quoteTemplateErrorMessage = nil
                }
            }
        )
    }

    private var isDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteEditURL != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteEditURL = nil
                }
            }
        )
    }

    private var isDeleteErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    private var isModerationAlertErrorPresented: Binding<Bool> {
        Binding(
            get: { moderationAlertErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    moderationAlertErrorMessage = nil
                }
            }
        )
    }

    private var isAlertMailConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingAlertMailURL != nil },
            set: { isPresented in
                if !isPresented {
                    pendingAlertMailURL = nil
                }
            }
        )
    }

    private var isPopupActionErrorPresented: Binding<Bool> {
        Binding(
            get: { popupActionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    popupActionErrorMessage = nil
                }
            }
        )
    }

    private func openQuoteComposer(with url: URL) {
        activeComposerPresentationKind = .reply
        composerNavigationTitle = ComposerPresentationKind.reply.title
        composerRequiresSubject = false
        composerRecipientName = nil
        prefillComposer(with: url, mode: .quote)
    }

    private func openEditComposer(with url: URL) {
        activeComposerPresentationKind = .edit
        composerNavigationTitle = ComposerPresentationKind.edit.title
        composerRequiresSubject = false
        composerRecipientName = nil
        prefillComposer(with: url, mode: .edit)
    }

    private func openPrivateMessageComposer(with url: URL, actions: TopicPageMessageActions) {
        guard !isLoadingQuoteTemplate else { return }
        activeComposerPresentationKind = .privateMessage
        composerRequiresSubject = true
        composerRecipientName = actions.authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let composerRecipientName, !composerRecipientName.isEmpty {
            composerNavigationTitle = "MP à \(composerRecipientName)"
        } else {
            composerNavigationTitle = "Nouv. MP"
        }
        composerSubmitURL = url
        isComposerPresented = true
    }

    private func prefillComposer(with url: URL, mode: ComposerPrefillMode) {
        guard !isLoadingQuoteTemplate else { return }

        Task { @MainActor in
            isLoadingQuoteTemplate = true
            activeComposerPrefillMode = mode
            defer { isLoadingQuoteTemplate = false }

            do {
                let template = try await replyQuoteTemplateLoader.fetchQuoteTemplate(from: url)
                switch mode {
                case .quote:
                    composerDraftText = ReplyQuoteDraftMerger.merge(
                        quoteTemplate: template,
                        into: composerDraftText
                    )
                    composerSubmitURL = topicAnswerURL ?? url
                case .edit:
                    composerDraftText = template
                    composerSubmitURL = url
                }
                lastFailedQuoteTemplateURL = nil
                quoteTemplateErrorMessage = nil
                isComposerPresented = true
            } catch {
                lastFailedQuoteTemplateURL = url
                lastFailedComposerPrefillMode = mode
                quoteTemplateErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func openProfile(for url: URL) {
        safariDestination = SafariDestination(url: url)
    }

    private func presentAvatarActionSheet(with actions: TopicPageMessageActions) {
        avatarActionSheetState = AvatarActionSheetState(actions: actions)
    }

    private func dismissAvatarActionSheet(then action: @escaping @MainActor () -> Void) {
        avatarActionSheetState = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            action()
        }
    }

    private func openAvatarProfile(_ url: URL) {
        dismissAvatarActionSheet {
            openProfile(for: url)
        }
    }

    private func openAvatarPrivateMessage(_ url: URL, actions: TopicPageMessageActions) {
        dismissAvatarActionSheet {
            openPrivateMessageComposer(with: url, actions: actions)
        }
    }

    private func toggleAvatarBlacklist(for pseudo: String) {
        dismissAvatarActionSheet {
            let message = MessageBlackWhiteListActionBridge.toggleBlacklist(pseudo: pseudo)
            if let message {
                showSuccessToast(message)
            } else {
                popupActionErrorMessage = "Blacklist impossible"
            }
            loadPage(page)
        }
    }

    private func toggleAvatarWhitelist(for pseudo: String) {
        dismissAvatarActionSheet {
            let message = MessageBlackWhiteListActionBridge.toggleWhitelist(pseudo: pseudo)
            if let message {
                showSuccessToast(message)
            } else {
                popupActionErrorMessage = "Whitelist impossible"
            }
            loadPage(page)
        }
    }

    private func askAQPrompt(with actions: TopicPageMessageActions) {
        guard !isPreparingAQPrompt else { return }
        guard
            let topicID = actions.topicID,
            let topicTitle = actions.topicTitle,
            let postID = MessagePopupActionSupport.numericPostID(from: actions.postID),
            let postURL = actions.permalinkURL
        else {
            showSuccessToast("Données AQ incomplètes")
            return
        }

        Task { @MainActor in
            isPreparingAQPrompt = true
            defer { isPreparingAQPrompt = false }

            let alreadySignaled = await MessagePopupActionSupport.isAQAlreadySignaled(
                topicID: topicID,
                postID: postID
            )
            if alreadySignaled == true {
                showSuccessToast("Post déjà signalé")
                return
            }
            if alreadySignaled == nil {
                popupActionErrorMessage = "Création d'AQ impossible"
                return
            }

            aqPromptState = AQPromptState(
                topicID: topicID,
                topicTitle: topicTitle,
                postID: postID,
                postURL: postURL,
                authorName: actions.authorName ?? ""
            )
        }
    }

    private func askBookmarkPrompt(with actions: TopicPageMessageActions) {
        guard
            let topicID = actions.topicID,
            let topicCategory = actions.topicCategory,
            let postID = MessagePopupActionSupport.numericPostID(from: actions.postID)
        else {
            showSuccessToast("Données bookmark incomplètes")
            return
        }

        if MessagePopupActionSupport.hasBookmark(topicID: topicID, postID: postID) {
            showSuccessToast("Post déjà dans les bookmarks")
            return
        }

        bookmarkPromptState = BookmarkPromptState(
            topicID: topicID,
            topicCategory: topicCategory,
            postID: postID,
            authorName: actions.authorName ?? ""
        )
    }

    private func askAlertMailConfirmation(with permalinkURL: URL) {
        pendingAlertMailURL = permalinkURL
    }

    private func confirmAlertMailSending() {
        guard let permalinkURL = pendingAlertMailURL else { return }
        pendingAlertMailURL = nil

        let subject = "[HardWare.fr] Signalement d'un contenu illicite"
        let body = "Message : \(permalinkURL.absoluteString)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let mailtoURL = URL(string: "mailto:marc@hardware.fr?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }

        UIApplication.shared.open(mailtoURL, options: [:], completionHandler: nil)
    }

    private func openModerationAlertComposer(with alertURL: URL) {
        guard !isPreparingModerationAlert else { return }

        Task { @MainActor in
            isPreparingModerationAlert = true
            defer { isPreparingModerationAlert = false }

            do {
                let preparation = try await moderationAlertService.prepareAlert(from: alertURL)
                switch preparation {
                case .alreadyAlerted(let message):
                    let statusMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                    showSuccessToast(statusMessage.isEmpty ? "Alerte déjà envoyée." : statusMessage)
                case .ready(let preparedForm):
                    moderationAlertDestination = ModerationAlertDestination(preparedForm: preparedForm)
                }
            } catch let error as ReplyPostingError {
                moderationAlertErrorMessage = error.localizedDescription
            } catch {
                moderationAlertErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Alerte impossible."
            }
        }
    }

    private func askDeleteMessageConfirmation(with editURL: URL) {
        guard !isDeletingMessage else { return }
        pendingDeleteEditURL = editURL
    }

    private func confirmDeleteMessage() {
        guard let editURL = pendingDeleteEditURL, !isDeletingMessage else { return }
        pendingDeleteEditURL = nil

        Task { @MainActor in
            isDeletingMessage = true
            defer { isDeletingMessage = false }

            do {
                let result = try await messageDeletionService.deleteMessage(editURL: editURL)
                let statusMessage = result.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                let toastMessage = (statusMessage?.isEmpty == false) ? (statusMessage ?? "") : "Message supprimé"
                showSuccessToast(toastMessage)

                if let refreshURL = result.refreshURL {
                    loadDirectURL(refreshURL.absoluteString)
                    return
                }

                anchor = result.refreshAnchor
                initialScroll = .top
                loadPage(page)
            } catch let error as ReplyPostingError {
                deleteErrorMessage = error.localizedDescription
            } catch {
                deleteErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Suppression impossible."
            }
        }
    }

    private func openReplyComposer() {
        activeComposerPresentationKind = .reply
        composerNavigationTitle = ComposerPresentationKind.reply.title
        composerRequiresSubject = false
        composerRecipientName = nil
        composerSubmitURL = topicAnswerURL
        isComposerPresented = true
    }

    @ViewBuilder
    private var linkedTopicNavigationLink: some View {
        NavigationLink(
            "",
            isActive: $navigateToLinkedTopic
        ) {
            if let linkedTopic {
                MessagesView(
                    topic: linkedTopic,
                    curPage: Int(linkedTopic.curTopicPage),
                    maxPage: max(Int(linkedTopic.maxTopicPage), 1),
                    separatorNewMessages: true,
                    navigationDepth: navigationDepth + 1
                )
                .toolbar(.hidden, for: .tabBar)
            } else {
                EmptyView()
            }
        }
        .hidden()
        .allowsHitTesting(false)
    }


    private func uniqueValidPages(_ candidates: [Int], excluding excludedTargets: Set<Int> = []) -> [Int] {
        var seen = excludedTargets
        return candidates.compactMap { target in
            guard (1...currentMaxPage).contains(target), target != page else { return nil }
            guard seen.insert(target).inserted else { return nil }
            return target
        }
    }

    private var backwardFirstPages: [Int] {
        uniqueValidPages([1, 2, 3])
    }

    private var backwardLastPages: [Int] {
        uniqueValidPages([page - 3, page - 2, page - 1], excluding: Set(backwardFirstPages))
    }

    private var forwardFirstPages: [Int] {
        uniqueValidPages([page + 1, page + 2, page + 3])
    }

    private var forwardLastPages: [Int] {
        uniqueValidPages([currentMaxPage - 2, currentMaxPage - 1, currentMaxPage], excluding: Set(forwardFirstPages))
    }

    private func pageMenuLabel(_ target: Int) -> String {
        "Page \(target)"
    }

    private func openPagePicker() {
        pagePickerInput = "\(page)"
        isPagePickerPresented = true
    }

    private func navigateToPage(_ target: Int, initialScroll: WebView.InitialScroll) {
        guard (1...currentMaxPage).contains(target), target != page else { return }
        anchor = nil
        self.initialScroll = initialScroll
        loadPage(target)
    }

    private var shouldShowBottomRefreshButton: Bool {
        page >= currentMaxPage && isWebContentAtBottom
    }

    private var shouldHighlightNextPageButton: Bool {
        page < currentMaxPage && isWebContentAtBottom
    }

    @ToolbarContentBuilder
    private var navigationDepthBackButton: some ToolbarContent {
        if navigationDepth > 0 {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.backward")
                            .fontWeight(.semibold)
                        Text("\(navigationDepth)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    private func refreshCurrentPageAtBottom() {
        anchor = nil
        initialScroll = .bottom
        loadPage(page)
    }

    private func handleReplySuccess(_ result: ReplyPostingResult) {
        pendingPostedReply = result
    }

    private func showSuccessToast(_ text: String) {
        postSuccessToastText = text
        withAnimation {
            showPostSuccessToast = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation {
                showPostSuccessToast = false
            }
        }
    }

    private func handleComposerDismissalIfNeeded() {
        guard let postedReply = pendingPostedReply else { return }
        pendingPostedReply = nil

        let presentationKind = activeComposerPresentationKind
        showSuccessToast(presentationKind.successToastText)

        guard presentationKind.shouldRefreshTopicOnSuccess else { return }
        guard page >= currentMaxPage else { return }

        if let refreshURL = postedReply.refreshURL {
            loadDirectURL(refreshURL.absoluteString, initialScroll: .bottom)
            return
        }

        anchor = postedReply.refreshAnchor
        initialScroll = .bottom
        loadPage(currentMaxPage)
    }

    @ViewBuilder
    private func backwardContextMenuItems() -> some View {
        if page > 1 {
            if page > 2 {
                Button {
                    // Go to first page: start at top
                    self.anchor = nil
                    self.initialScroll = .top
                    loadPage(1)
                } label: {
                    MenuActionLabel("Première page", systemImage: "backward.end")
                }
            }
            Button {
                // Previous page: start at bottom
                self.anchor = nil
                self.initialScroll = .bottom
                loadPage(page - 1)
            } label: {
                MenuActionLabel("Page précédente", systemImage: "chevron.backward")
            }  
        }
        Divider()
        if currentMaxPage > 1 {
            Button {
                openPagePicker()
            } label: {
                MenuActionLabel("Page numéro...", systemImage: "number")
            }
        }
    }

    @ViewBuilder
    private func forwardContextMenuItems() -> some View {
        if page < currentMaxPage {
            Button {
                // Next page: start at top
                self.anchor = nil
                self.initialScroll = .top
                loadPage(page + 1)
            } label: {
                MenuActionLabel("Page suivante", systemImage: "chevron.forward")
            }
            if page + 1 < currentMaxPage {
                Button {
                    // Last page: start at top
                    self.anchor = nil
                    self.initialScroll = .top
                    loadPage(currentMaxPage)
                } label: {
                    MenuActionLabel("Dernière page", systemImage: "forward.end")
                }
            }
            Button {
                // Dernière réponse: start at top
                self.anchor = nil
                self.initialScroll = .bottom
                loadPage(currentMaxPage)
            } label: {
                MenuActionLabel("Dernière réponse", systemImage: "text.append")
            }
        }
        Divider()
        if currentMaxPage > 1 {
            Button {
                openPagePicker()
            } label: {
                MenuActionLabel("Page numéro...", systemImage: "number")
            }
        }
    }

    var body: some View {
        // Use ViewBuilder implicit grouping to avoid generic inference issues with Group
        if let errorMessage {
            Text("Erreur : \(errorMessage)").foregroundColor(.red)
                .navigationBarBackButtonHidden(navigationDepth > 0)
                .toolbar {
                    navigationDepthBackButton
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(topicDisplayTitle.isEmpty ? (topic._aTitle ?? "Messages") : topicDisplayTitle)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(page)/\(currentMaxPage)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .multilineTextAlignment(.center)
                    }
                }
                .onAppear {
                    loadPage(page)
                }
                .background(linkedTopicNavigationLink)
                .sheet(item: $safariDestination) { destination in
                    SafariInAppView(url: destination.url)
                        .ignoresSafeArea()
                }
                .sheet(item: $smileySheetState) { state in
                    MessageSmileySheetView(
                        code: state.payload.code,
                        imageURL: state.payload.imageURL,
                        initiallyFavorite: state.isFavorite,
                        onToggleFavorite: { add in
                            updateSmileyFavorite(code: state.payload.code, imageURL: state.payload.imageURL, add: add)
                        },
                        onFetchKeywords: {
                            await fetchSmileyKeywords(code: state.payload.code)
                        },
                        onShowToast: { message in
                            showSuccessToast(message)
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
                .fullScreenCover(item: $photoViewerDestination) { destination in
                    FullScreenPhotoViewer(url: destination.url, presentationID: destination.id)
                }
        } else if fileURL != nil && cacheURL != nil {
            ZStack {
                themePalette.webViewBackdropColor

                WebView(
                    fileURL: fileURL,
                    readAccessURL: cacheURL,
                    anchor: anchor,
                    initialScroll: initialScroll,
                    currentPage: page,
                    maxPage: currentMaxPage,
                    colorScheme: appTheme.effectiveColorScheme,
                    baseBackgroundColor: themePalette.webViewBackdropUIColor,
                    themeRevision: appTheme.themeRevision,
                    messageActionsByIndex: messageActionsByIndex,
                    onWebAction: handleWebAction,
                    onPopupQuoteRequest: { quoteURL in
                        openQuoteComposer(with: quoteURL)
                    },
                    onPopupEditRequest: { editURL in
                        openEditComposer(with: editURL)
                    },
                    onPopupPrivateMessageRequest: { privateMessageURL, actions in
                        openPrivateMessageComposer(with: privateMessageURL, actions: actions)
                    },
                    onPopupDeleteRequest: { editURL in
                        askDeleteMessageConfirmation(with: editURL)
                    },
                    onPopupAlertRequest: { alertURL in
                        openModerationAlertComposer(with: alertURL)
                    },
                    onPopupAlertMailRequest: { permalinkURL in
                        askAlertMailConfirmation(with: permalinkURL)
                    },
                    onPopupAvatarSheetRequest: { actions in
                        presentAvatarActionSheet(with: actions)
                    },
                    onPopupProfileRequest: { profileURL in
                        openProfile(for: profileURL)
                    },
                    onPopupAQRequest: { actions in
                        askAQPrompt(with: actions)
                    },
                    onPopupBookmarkRequest: { actions in
                        askBookmarkPrompt(with: actions)
                    },
                    onContentReady: {
                        withAnimation(.easeOut(duration: 0.14)) {
                            showWebViewLoadCover = false
                        }
                    },
                    onScrollPositionChange: { isAtBottom in
                        if isWebContentAtBottom != isAtBottom {
                            withAnimation(.easeOut(duration: 0.18)) {
                                isWebContentAtBottom = isAtBottom
                            }
                        }
                    }
                )
                    .id(page) // force a new WKWebView per page

                if showWebViewLoadCover {
                    themePalette.webViewBackdropColor
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if isLoadingQuoteTemplate {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView(activeComposerPrefillMode.loadingLabel)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }

                if isPreparingModerationAlert {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Chargement de l'alerte...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }

                if isDeletingMessage {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Suppression...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }

                if isPreparingAQPrompt {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Chargement de l'AQ...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(navigationDepth > 0)

                .simultaneousGesture(
                    DragGesture().onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        let minDistance: CGFloat = 120
                        let maxVerticalRatio: CGFloat = 0.5
                        if abs(horizontal) > minDistance && abs(vertical) < abs(horizontal) * maxVerticalRatio {
                            if horizontal < 0, page < currentMaxPage {
                                // Next page: start at top
                                self.anchor = nil
                                self.initialScroll = .top
                                loadPage(page + 1)
                            } else if horizontal > 0, page > 1 {
                                // Previous page: start at bottom
                                self.anchor = nil
                                self.initialScroll = .bottom
                                loadPage(page - 1)
                            }
                        }
                    }
                )
                .sheet(isPresented: $isComposerPresented) {
                    AnswerView(
                        topicURL: composerSubmitURL ?? topicAnswerURL,
                        title: composerNavigationTitle,
                        requiresSubject: composerRequiresSubject,
                        initialRecipient: composerRecipientName,
                        onPostSuccess: handleReplySuccess,
                        composerDraftText: $composerDraftText,
                        isComposerPresented: $isComposerPresented
                    )
                    .presentationDetents([.large])
                }
                .sheet(item: $aqPromptState) { state in
                    MessagePopupPromptSheet(
                        title: "Alerte Qualitay",
                        message: "Créer une Alerte Qualitay sur le post de \(state.authorName)",
                        placeholder: "Ajoutez un titre",
                        actionTitle: "Créer"
                    ) { draftTitle in
                        let result = await MessagePopupActionSupport.createAQ(
                            title: draftTitle,
                            topicID: state.topicID,
                            topicTitle: state.topicTitle,
                            postID: state.postID,
                            postURL: state.postURL.absoluteString,
                            author: state.authorName
                        )
                        switch result {
                        case .success:
                            return "Alerte Qualitay créée."
                        case .failure(let code):
                            throw MessagePopupSheetSubmissionError(message: "Code erreur \(code)")
                        case .networkError:
                            throw MessagePopupSheetSubmissionError(message: "Création d'AQ impossible")
                        }
                    } onSuccess: { message in
                        showSuccessToast(message)
                    }
                    .presentationDetents([.medium])
                }
                .sheet(item: $bookmarkPromptState) { state in
                    MessagePopupPromptSheet(
                        title: "Bookmark",
                        message: "Créer un bookmark sur le post de \(state.authorName) ?",
                        placeholder: "Ajoutez un titre",
                        actionTitle: "Créer"
                    ) { draftTitle in
                        let created = MessagePopupActionSupport.createBookmark(
                            topicID: state.topicID,
                            topicCategory: state.topicCategory,
                            postID: state.postID,
                            title: draftTitle,
                            author: state.authorName
                        )
                        if created {
                            return "Bookmark créé"
                        }
                        throw MessagePopupSheetSubmissionError(message: "Erreur à la création du bookmark")
                    } onSuccess: { message in
                        showSuccessToast(message)
                    }
                    .presentationDetents([.medium])
                }
                .sheet(item: $moderationAlertDestination) { destination in
                    ModerationAlertComposerView(
                        preparedForm: destination.preparedForm,
                        moderationAlertService: moderationAlertService
                    ) { statusMessage in
                        showSuccessToast(statusMessage)
                    }
                    .presentationDetents([.large])
                }
                .onChange(of: isComposerPresented) { _, isPresented in
                    if !isPresented {
                        handleComposerDismissalIfNeeded()
                    }
                }
                .alert(lastFailedComposerPrefillMode.alertTitle, isPresented: isQuoteTemplateAlertPresented) {
                    if let retryURL = lastFailedQuoteTemplateURL {
                        Button("Réessayer") {
                            prefillComposer(with: retryURL, mode: lastFailedComposerPrefillMode)
                        }
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(quoteTemplateErrorMessage ?? "Erreur inconnue.")
                }
                .alert("Supprimer ce message ?", isPresented: isDeleteConfirmationPresented) {
                    Button("Non", role: .cancel) {}
                    Button("Oui", role: .destructive) {
                        confirmDeleteMessage()
                    }
                } message: {
                    Text("Cette action est définitive.")
                }
                .alert("Suppression impossible", isPresented: isDeleteErrorAlertPresented) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage ?? "Erreur inconnue.")
                }
                .alert("Alerter les modérateurs par email ?", isPresented: isAlertMailConfirmationPresented) {
                    Button("Non", role: .cancel) {}
                    Button("Oui") {
                        confirmAlertMailSending()
                    }
                } message: {
                    Text("Un email sera préparé dans votre application Mail.")
                }
                .alert("Alerte impossible", isPresented: isModerationAlertErrorPresented) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(moderationAlertErrorMessage ?? "Erreur inconnue.")
                }
                .alert("Action impossible", isPresented: isPopupActionErrorPresented) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(popupActionErrorMessage ?? "Erreur inconnue.")
                }
                .toolbar {
                    navigationDepthBackButton
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(topicDisplayTitle.isEmpty ? (topic._aTitle ?? "Messages") : topicDisplayTitle)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(page)/\(currentMaxPage)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .multilineTextAlignment(.center)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Menu avec options
                        Menu {
                            Button {
                                openReplyComposer()
                            } label: {
                                MenuActionLabel("Répondre", systemImage: "pencil")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                    if !isComposerPresented {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button {
                                navigateToPage(page - 1, initialScroll: .bottom)
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .contextMenu {
                                backwardContextMenuItems()
                            } preview: {
                                Color.clear.frame(width: 1, height: 1)
                            }
                            .disabled(page <= 1)

                            Button {
                                navigateToPage(page + 1, initialScroll: .top)
                            } label: {
                                Image(systemName: "chevron.forward")
                            }
                            .contextMenu {
                                forwardContextMenuItems()
                            } preview: {
                                Color.clear.frame(width: 1, height: 1)
                            }
                            .topicBottomBarButtonStyle(isProminent: shouldHighlightNextPageButton)
                            .disabled(page >= currentMaxPage)
                        }

                        ToolbarSpacer(.flexible, placement: .bottomBar)

                        if shouldShowBottomRefreshButton {
                            ToolbarItem(placement: .bottomBar) {
                                Button {
                                    refreshCurrentPageAtBottom()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .buttonStyle(.glassProminent)
                                .accessibilityLabel("Actualiser")
                                .transition(.opacity.combined(with: .scale))
                            }
                            ToolbarSpacer(.fixed, placement: .bottomBar)
                        }

                        ToolbarItem(placement: .bottomBar) {
                            Button {
                                openReplyComposer()
                            } label: {
                                Label("New", systemImage: "plus")
                            }
                            .topicBottomBarButtonStyle(isProminent: false)
                        }
                    }
                }
                .sheet(isPresented: $isPagePickerPresented) {
                    TopicPagePickerSheet(
                        maxPage: currentMaxPage,
                        pageInput: $pagePickerInput
                    ) { selectedPage in
                        navigateToPage(selectedPage, initialScroll: .top)
                    }
                }
                .background(linkedTopicNavigationLink)
                .sheet(item: $safariDestination) { destination in
                    SafariInAppView(url: destination.url)
                        .ignoresSafeArea()
                }
                .sheet(item: $smileySheetState) { state in
                    MessageSmileySheetView(
                        code: state.payload.code,
                        imageURL: state.payload.imageURL,
                        initiallyFavorite: state.isFavorite,
                        onToggleFavorite: { add in
                            updateSmileyFavorite(code: state.payload.code, imageURL: state.payload.imageURL, add: add)
                        },
                        onFetchKeywords: {
                            await fetchSmileyKeywords(code: state.payload.code)
                        },
                        onShowToast: { message in
                            showSuccessToast(message)
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
                .sheet(item: $avatarActionSheetState) { state in
                    MessageAvatarActionSheetView(
                        actions: state.actions,
                        colorScheme: appTheme.effectiveColorScheme,
                        onProfile: { profileURL in
                            openAvatarProfile(profileURL)
                        },
                        onPrivateMessage: { privateMessageURL, actions in
                            openAvatarPrivateMessage(privateMessageURL, actions: actions)
                        },
                        onBlacklist: { pseudo in
                            toggleAvatarBlacklist(for: pseudo)
                        },
                        onWhitelist: { pseudo in
                            toggleAvatarWhitelist(for: pseudo)
                        }
                    )
                    .presentationDetents([.medium])
                }
                .fullScreenCover(item: $photoViewerDestination) { destination in
                    FullScreenPhotoViewer(url: destination.url, presentationID: destination.id)
                }
                .overlay(alignment: .top) {
                    if showPostSuccessToast {
                        PostSuccessToastBanner(text: postSuccessToastText)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.22), value: shouldShowBottomRefreshButton)
                .animation(.easeOut(duration: 0.18), value: shouldHighlightNextPageButton)
        } else {
            ZStack {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Chargement...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .navigationTitle("My title")
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationBarBackButtonHidden(navigationDepth > 0)
            .toolbar {
                navigationDepthBackButton
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(topicDisplayTitle.isEmpty ? (topic._aTitle ?? "Messages") : topicDisplayTitle)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(page)/\(currentMaxPage)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .multilineTextAlignment(.center)
                }
                if let pollData {
                    ToolbarItem(placement: .topBarTrailing) {
                        PollToolbarButton(isVotable: pollData.isVotable) {
                            isPollSheetPresented = true
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Menu avec options
                    Menu {
                        Button {
                            openReplyComposer()
                        } label: {
                            MenuActionLabel("Répondre", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        navigateToPage(page - 1, initialScroll: .bottom)
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .contextMenu {
                        backwardContextMenuItems()
                    } preview: {
                        EmptyView()
                    }
                    .disabled(page <= 1)

                    Button {
                        navigateToPage(page + 1, initialScroll: .top)
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .contextMenu {
                        forwardContextMenuItems()
                    } preview: {
                        EmptyView()
                    }
                    .topicBottomBarButtonStyle(isProminent: shouldHighlightNextPageButton)
                    .disabled(page >= currentMaxPage)

                    Spacer()
                    Button {
                        openReplyComposer()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .topicBottomBarButtonStyle(isProminent: false)
                }
            }
            .sheet(isPresented: $isPagePickerPresented) {
                TopicPagePickerSheet(
                    maxPage: currentMaxPage,
                    pageInput: $pagePickerInput
                ) { selectedPage in
                    navigateToPage(selectedPage, initialScroll: .top)
                }
            }
            .sheet(isPresented: $isPollSheetPresented) {
                if let pollData {
                    PollSheet(pollData: pollData, onVoteSucceeded: {
                        loadPage(page)
                    })
                }
            }
            .onAppear {
                loadPage(page)
            }
            .background(linkedTopicNavigationLink)
            .sheet(item: $safariDestination) { destination in
                SafariInAppView(url: destination.url)
                    .ignoresSafeArea()
            }
            .sheet(item: $smileySheetState) { state in
                MessageSmileySheetView(
                    code: state.payload.code,
                    imageURL: state.payload.imageURL,
                    initiallyFavorite: state.isFavorite,
                    onToggleFavorite: { add in
                        updateSmileyFavorite(code: state.payload.code, imageURL: state.payload.imageURL, add: add)
                    },
                    onFetchKeywords: {
                        await fetchSmileyKeywords(code: state.payload.code)
                    },
                    onShowToast: { message in
                        showSuccessToast(message)
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $avatarActionSheetState) { state in
                MessageAvatarActionSheetView(
                    actions: state.actions,
                    colorScheme: appTheme.effectiveColorScheme,
                    onProfile: { profileURL in
                        openAvatarProfile(profileURL)
                    },
                    onPrivateMessage: { privateMessageURL, actions in
                        openAvatarPrivateMessage(privateMessageURL, actions: actions)
                    },
                    onBlacklist: { pseudo in
                        toggleAvatarBlacklist(for: pseudo)
                    },
                    onWhitelist: { pseudo in
                        toggleAvatarWhitelist(for: pseudo)
                    }
                )
                .presentationDetents([.medium])
            }
            .fullScreenCover(item: $photoViewerDestination) { destination in
                FullScreenPhotoViewer(url: destination.url, presentationID: destination.id)
            }
        }
    }
}

private struct MessageSmileySheetView: View {
    let code: String
    let imageURL: String
    let initiallyFavorite: Bool
    let onToggleFavorite: (Bool) -> Bool
    let onFetchKeywords: () async -> Result<[String], Error>
    let onShowToast: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("MessageSmileySheetCompactImage") private var isSmileyCompactImage = false
    @State private var isFavorite: Bool
    @State private var imageLoadState: MessageAnimatedImageLoadState = .idle
    @State private var keywords: [String] = []
    @State private var isLoadingKeywords = false
    @State private var keywordsErrorMessage: String?

    init(
        code: String,
        imageURL: String,
        initiallyFavorite: Bool,
        onToggleFavorite: @escaping (Bool) -> Bool,
        onFetchKeywords: @escaping () async -> Result<[String], Error>,
        onShowToast: @escaping (String) -> Void
    ) {
        self.code = code
        self.imageURL = imageURL
        self.initiallyFavorite = initiallyFavorite
        self.onToggleFavorite = onToggleFavorite
        self.onFetchKeywords = onFetchKeywords
        self.onShowToast = onShowToast
        _isFavorite = State(initialValue: initiallyFavorite)
    }

    private var smileyScale: CGFloat {
        isSmileyCompactImage ? 0.7 : 0.95
    }

    private var smileyDisplayHeight: CGFloat {
        124
    }

    private let previewHorizontalInset: CGFloat = 34

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))

                        MessageAnimatedGIFImageView(
                            url: URL(string: imageURL),
                            loadState: $imageLoadState
                        )
                        .padding(6)
                        .scaleEffect(smileyScale)
                        .animation(.easeInOut(duration: 0.16), value: smileyScale)

                        if imageLoadState == .idle || imageLoadState == .loading {
                            ProgressView()
                        } else if imageLoadState == .failure {
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                Text("Image indisponible")
                                    .font(.footnote)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, previewHorizontalInset)
                    .frame(maxWidth: .infinity, minHeight: smileyDisplayHeight, maxHeight: smileyDisplayHeight)

                    Text(code)
                        .font(.title3.monospaced())
                        .textSelection(.enabled)

                    Button {
                        let add = !isFavorite
                        if onToggleFavorite(add) {
                            isFavorite.toggle()
                            onShowToast(add ? "Smiley ajouté aux favoris" : "Smiley retiré des favoris")
                        } else {
                            onShowToast("Erreur :/")
                        }
                    } label: {
                        Label(
                            isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                            systemImage: isFavorite ? "star.slash" : "star"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task {
                            isLoadingKeywords = true
                            keywordsErrorMessage = nil
                            switch await onFetchKeywords() {
                            case .success(let fetchedKeywords):
                                keywords = fetchedKeywords
                            case .failure(let error):
                                keywords = []
                                keywordsErrorMessage = error.localizedDescription
                            }
                            isLoadingKeywords = false
                        }
                    } label: {
                        Label("Mots clés", systemImage: "text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingKeywords)

                    if isLoadingKeywords {
                        ProgressView("Chargement des mots clés...")
                            .font(.footnote)
                    } else if let keywordsErrorMessage {
                        Text(keywordsErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if !keywords.isEmpty {
                        ScrollView {
                            Text(keywords.joined(separator: "  "))
                                .font(.footnote.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 120)
                    }

                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Smiley")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isSmileyCompactImage.toggle()
                    } label: {
                        Label(
                            isSmileyCompactImage ? "Grand" : "Petit",
                            systemImage: isSmileyCompactImage ? "plus.magnifyingglass" : "minus.magnifyingglass"
                        )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MessageAvatarActionSheetView: View {
    let actions: TopicPageMessageActions
    let colorScheme: ColorScheme
    let onProfile: (URL) -> Void
    let onPrivateMessage: (URL, TopicPageMessageActions) -> Void
    let onBlacklist: (String) -> Void
    let onWhitelist: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var authorName: String {
        let trimmed = actions.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Auteur" : trimmed
    }

    private let previewHorizontalInset: CGFloat = 34

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))

                        MessageAvatarPreviewView(
                            avatarImagePath: actions.avatarImagePath,
                            colorScheme: colorScheme
                        )
                    }
                    .padding(.horizontal, previewHorizontalInset)
                    .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124)

                    Text(authorName)
                        .font(.title3)
                        .bold()
                        .textSelection(.enabled)

                    if let profileURL = actions.profileURL {
                        Button {
                            onProfile(profileURL)
                        } label: {
                            Label("Profil", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !actions.isOwnMessage, let privateMessageURL = actions.privateMessageURL {
                        Button {
                            onPrivateMessage(privateMessageURL, actions)
                        } label: {
                            Label("MP", systemImage: "message")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !actions.isOwnMessage, let authorName = actions.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !authorName.isEmpty {
                        Button {
                            onWhitelist(authorName)
                        } label: {
                            Label("Whitelist", systemImage: "heart")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            onBlacklist(authorName)
                        } label: {
                            Label("Blacklist", systemImage: "hand.raised")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle(authorName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MessageAvatarPreviewView: View {
    let avatarImagePath: String?
    let colorScheme: ColorScheme

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 96)
    }

    private var resolvedImage: UIImage? {
        if let avatarImagePath {
            let trimmed = avatarImagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let localImage = UIImage(contentsOfFile: trimmed) {
                    return localImage
                }
                if let url = URL(string: trimmed), url.isFileURL, let localImage = UIImage(contentsOfFile: url.path) {
                    return localImage
                }
            }
        }

        let assetName = colorScheme == .dark ? "avatar_male_gray_on_dark_48x48" : "avatar_male_gray_on_light_48x48"
        return UIImage(named: assetName)
    }
}

private enum MessageAnimatedImageLoadState: Equatable {
    case idle
    case loading
    case success
    case failure
}

private struct MessageAnimatedGIFImageView: UIViewRepresentable {
    let url: URL?
    @Binding var loadState: MessageAnimatedImageLoadState
    var imageSize: Binding<CGSize?> = .constant(nil)

    func makeUIView(context: Context) -> ContainerView {
        ContainerView()
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        context.coordinator.update(uiView.imageView, with: url, loadState: $loadState, imageSize: imageSize)
    }

    static func dismantleUIView(_ uiView: ContainerView, coordinator: Coordinator) {
        coordinator.reset()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class ContainerView: UIView {
        let imageView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator {
        private static let imageCache = NSCache<NSString, UIImage>()
        private var currentURL: URL?
        private var loadTask: URLSessionDataTask?

        func update(
            _ imageView: UIImageView,
            with url: URL?,
            loadState: Binding<MessageAnimatedImageLoadState>,
            imageSize: Binding<CGSize?>
        ) {
            if currentURL == url {
                if let currentImage = imageView.image {
                    imageSize.wrappedValue = currentImage.size
                    loadState.wrappedValue = .success
                    return
                }

                if let url {
                    let cacheKey = url.absoluteString as NSString
                    if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
                        imageView.image = cachedImage
                        imageSize.wrappedValue = cachedImage.size
                        loadState.wrappedValue = .success
                        return
                    }
                }

                // A load for the same URL is already in flight; don't cancel/restart it on every SwiftUI update.
                if loadTask != nil {
                    loadState.wrappedValue = .loading
                    return
                }
            }

            currentURL = url
            loadTask?.cancel()
            loadTask = nil
            imageView.image = nil
            imageSize.wrappedValue = nil

            guard let url else {
                loadState.wrappedValue = .failure
                return
            }

            let cacheKey = url.absoluteString as NSString
            if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
                imageView.image = cachedImage
                imageSize.wrappedValue = cachedImage.size
                loadState.wrappedValue = .success
                return
            }

            loadState.wrappedValue = .loading

            let task = URLSession.shared.dataTask(with: url) { [weak self, weak imageView] data, response, _ in
                guard let self else { return }

                let isValidResponse = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
                guard
                    let data,
                    isValidResponse,
                    let decodedImage = Self.decodeAnimatedImage(from: data)
                else {
                    DispatchQueue.main.async {
                        guard self.currentURL == url else { return }
                        imageSize.wrappedValue = nil
                        loadState.wrappedValue = .failure
                    }
                    return
                }

                Self.imageCache.setObject(decodedImage, forKey: cacheKey)
                DispatchQueue.main.async {
                    guard self.currentURL == url else { return }
                    imageView?.image = decodedImage
                    imageSize.wrappedValue = decodedImage.size
                    loadState.wrappedValue = .success
                }
            }

            loadTask = task
            task.resume()
        }

        func cancelPendingWork() {
            loadTask?.cancel()
            loadTask = nil
        }

        func reset() {
            cancelPendingWork()
            currentURL = nil
        }

        private static func decodeAnimatedImage(from data: Data) -> UIImage? {
            let animatedGIFSelector = NSSelectorFromString("sd_animatedGIFWithData:")
            let imageClass: AnyObject = UIImage.self
            if imageClass.responds(to: animatedGIFSelector),
               let unmanaged = imageClass.perform(animatedGIFSelector, with: data),
               let image = unmanaged.takeUnretainedValue() as? UIImage {
                return image
            }

            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }

            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 1 else {
                return UIImage(data: data)
            }

            var frames: [UIImage] = []
            var totalDuration: Double = 0
            let scale = UIScreen.main.scale

            for index in 0..<frameCount {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    continue
                }
                totalDuration += frameDuration(at: index, in: source)
                frames.append(UIImage(cgImage: cgImage, scale: scale, orientation: .up))
            }

            guard !frames.isEmpty else {
                return UIImage(data: data)
            }

            if totalDuration <= 0 {
                totalDuration = Double(frames.count) * 0.1
            }
            return UIImage.animatedImage(with: frames, duration: totalDuration)
        }

        private static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
            guard
                let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else {
                return 0.1
            }

            let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
            let duration = unclampedDelay ?? delay ?? 0.1
            return duration < 0.011 ? 0.1 : duration
        }
    }
}

struct FullScreenPhotoViewer: View {
    let url: URL
    let presentationID: UUID

    private static let photoViewerSpring = Animation.spring(response: 0.26, dampingFraction: 0.84)

    @Environment(\.dismiss) private var dismiss
    @State private var dismissDragOffset: CGFloat = 0
    @State private var showsCloseButton = false
    @State private var imageLoadState: MessageAnimatedImageLoadState = .idle
    @State private var hasVisibleImage = false

    private var dismissBackgroundOpacity: Double {
        let progress = min(max(dismissDragOffset / 260, 0), 1)
        return max(0.65, 1 - (progress * 0.35))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .opacity(dismissBackgroundOpacity)
                .ignoresSafeArea()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dismissDragOffset = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            if value.translation.height > 140 {
                                dismiss()
                            } else {
                                withAnimation(Self.photoViewerSpring) {
                                    dismissDragOffset = 0
                                }
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsCloseButton.toggle()
                    }
                }

            ZoomableRemoteAnimatedImageView(
                url: url,
                presentationID: presentationID,
                loadState: $imageLoadState,
                hasVisibleImage: $hasVisibleImage,
                onSingleTap: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsCloseButton.toggle()
                    }
                },
                onDismissProgress: { progress in
                    if progress == 0 {
                        withAnimation(Self.photoViewerSpring) {
                            dismissDragOffset = 0
                        }
                    } else {
                        dismissDragOffset = progress
                    }
                },
                onDismissRequest: {
                    dismiss()
                }
            )
            .offset(y: dismissDragOffset)
            .ignoresSafeArea()

            if (imageLoadState == .loading || imageLoadState == .idle) && !hasVisibleImage {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if imageLoadState == .failure {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Impossible de charger la photo")
                        .font(.footnote)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if showsCloseButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                }
                .ifAvailableiOS26GlassProminent()
                .buttonBorderShape(.circle)
                .accessibilityLabel("Fermer")
                .padding(.top, 14)
                .padding(.trailing, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .statusBarHidden()
    }
}

private struct ZoomableRemoteAnimatedImageView: UIViewRepresentable {
    let url: URL
    let presentationID: UUID
    @Binding var loadState: MessageAnimatedImageLoadState
    @Binding var hasVisibleImage: Bool
    let onSingleTap: () -> Void
    let onDismissProgress: (CGFloat) -> Void
    let onDismissRequest: () -> Void

    func makeUIView(context: Context) -> ZoomingImageContainerView {
        ZoomingImageContainerView()
    }

    func updateUIView(_ uiView: ZoomingImageContainerView, context: Context) {
        context.coordinator.update(
            uiView,
            url: url,
            presentationID: presentationID,
            loadState: $loadState,
            hasVisibleImage: $hasVisibleImage,
            onSingleTap: onSingleTap,
            onDismissProgress: onDismissProgress,
            onDismissRequest: onDismissRequest
        )
    }

    static func dismantleUIView(_ uiView: ZoomingImageContainerView, coordinator: Coordinator) {
        coordinator.reset(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private static let imageCache = NSCache<NSString, UIImage>()
        private var currentURL: URL?
        private var currentPresentationID: UUID?
        private var loadTask: URLSessionDataTask?
        private var singleTapHandler: (() -> Void)?
        private var dismissProgressHandler: ((CGFloat) -> Void)?
        private var dismissRequestHandler: (() -> Void)?

        func configure(_ view: ZoomingImageContainerView) {
            view.scrollView.delegate = self
            view.scrollView.singleTapHandler = { [weak self] in
                self?.singleTapHandler?()
            }
            view.scrollView.dismissProgressHandler = { [weak self] progress in
                self?.dismissProgressHandler?(progress)
            }
            view.scrollView.dismissHandler = { [weak self] in
                self?.dismissRequestHandler?()
            }
        }

        func update(
            _ view: ZoomingImageContainerView,
            url: URL,
            presentationID: UUID,
            loadState: Binding<MessageAnimatedImageLoadState>,
            hasVisibleImage: Binding<Bool>,
            onSingleTap: @escaping () -> Void,
            onDismissProgress: @escaping (CGFloat) -> Void,
            onDismissRequest: @escaping () -> Void
        ) {
            func scheduleState(_ state: MessageAnimatedImageLoadState, visible: Bool) {
                DispatchQueue.main.async {
                    hasVisibleImage.wrappedValue = visible
                    loadState.wrappedValue = state
                }
            }

            singleTapHandler = onSingleTap
            dismissProgressHandler = onDismissProgress
            dismissRequestHandler = onDismissRequest
            configure(view)

            if currentPresentationID == presentationID, currentURL == url {
                if view.scrollView.imageView.image != nil {
                    scheduleState(.success, visible: true)
                    return
                }
                if loadTask != nil {
                    scheduleState(.loading, visible: false)
                    return
                }
            }

            currentPresentationID = presentationID
            currentURL = url
            loadTask?.cancel()
            loadTask = nil
            view.reset(suppressCallbacks: true)

            let cacheKey = url.absoluteString as NSString
            if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
                view.display(image: cachedImage, maximumZoomScale: 7.5)
                scheduleState(.success, visible: true)
                return
            }

            scheduleState(.loading, visible: false)

            let task = URLSession.shared.dataTask(with: url) { [weak self, weak view] data, response, _ in
                guard let self else { return }

                let isValidResponse = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
                guard
                    let data,
                    isValidResponse,
                    let image = Self.decodeAnimatedImage(from: data)
                else {
                    DispatchQueue.main.async {
                        guard self.currentPresentationID == presentationID, self.currentURL == url else { return }
                        self.loadTask = nil
                        hasVisibleImage.wrappedValue = false
                        loadState.wrappedValue = .failure
                    }
                    return
                }

                Self.imageCache.setObject(image, forKey: cacheKey)
                DispatchQueue.main.async {
                    guard self.currentPresentationID == presentationID, self.currentURL == url else { return }
                    view?.display(image: image, maximumZoomScale: 7.5)
                    hasVisibleImage.wrappedValue = true
                    self.loadTask = nil
                    loadState.wrappedValue = .success
                }
            }

            loadTask = task
            task.resume()
        }

        func reset(_ view: ZoomingImageContainerView) {
            loadTask?.cancel()
            loadTask = nil
            currentURL = nil
            currentPresentationID = nil
            view.scrollView.singleTapHandler = nil
            view.scrollView.dismissProgressHandler = nil
            view.scrollView.dismissHandler = nil
            view.reset(suppressCallbacks: true)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomingImageScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomingImageScrollView)?.centerImage()
        }

        private static func decodeAnimatedImage(from data: Data) -> UIImage? {
            let animatedGIFSelector = NSSelectorFromString("sd_animatedGIFWithData:")
            let imageClass: AnyObject = UIImage.self
            if imageClass.responds(to: animatedGIFSelector),
               let unmanaged = imageClass.perform(animatedGIFSelector, with: data),
               let image = unmanaged.takeUnretainedValue() as? UIImage {
                return image
            }

            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return UIImage(data: data)
            }

            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 1 else {
                return UIImage(data: data)
            }

            var frames: [UIImage] = []
            var totalDuration: Double = 0
            let scale = UIScreen.main.scale

            for index in 0..<frameCount {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    continue
                }
                totalDuration += frameDuration(at: index, in: source)
                frames.append(UIImage(cgImage: cgImage, scale: scale, orientation: .up))
            }

            guard !frames.isEmpty else {
                return UIImage(data: data)
            }

            if totalDuration <= 0 {
                totalDuration = Double(frames.count) * 0.1
            }
            return UIImage.animatedImage(with: frames, duration: totalDuration)
        }

        private static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
            guard
                let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            else {
                return 0.1
            }

            let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? Double
            let duration = unclampedDelay ?? delay ?? 0.1
            return duration < 0.011 ? 0.1 : duration
        }
    }
}

private final class ZoomingImageContainerView: UIView {
    let scrollView = ZoomingImageScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func display(image: UIImage, maximumZoomScale: CGFloat) {
        scrollView.display(image: image, maximumZoomScale: maximumZoomScale)
    }

    func reset(suppressCallbacks: Bool = false) {
        scrollView.resetImage(suppressCallbacks: suppressCallbacks)
    }
}

private final class ZoomingImageScrollView: UIScrollView, UIGestureRecognizerDelegate {
    let imageView = UIImageView()

    var singleTapHandler: (() -> Void)?
    var dismissProgressHandler: ((CGFloat) -> Void)?
    var dismissHandler: (() -> Void)?

    private var imageSize: CGSize?
    private var configuredMaximumZoomScale: CGFloat = 7.5
    private var hasConfiguredImage = false
    private var lastBoundsSize: CGSize = .zero
    private lazy var dismissPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        delegate = nil
        minimumZoomScale = 1
        maximumZoomScale = configuredMaximumZoomScale
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        delaysContentTouches = false
        canCancelContentTouches = true
        clipsToBounds = false

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        addGestureRecognizer(singleTap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        singleTap.require(toFail: doubleTap)

        addGestureRecognizer(dismissPanGesture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard hasConfiguredImage else { return }
        if bounds.size != lastBoundsSize {
            configureLayout(resetZoom: false)
        } else {
            centerImage()
        }
    }

    func display(image: UIImage, maximumZoomScale: CGFloat) {
        configuredMaximumZoomScale = maximumZoomScale
        imageSize = image.size
        hasConfiguredImage = true
        imageView.image = image
        if image.images != nil {
            imageView.startAnimating()
        } else {
            imageView.stopAnimating()
        }
        configureLayout(resetZoom: true)
    }

    func resetImage(suppressCallbacks: Bool = false) {
        setZoomScale(1, animated: false)
        contentOffset = .zero
        contentSize = .zero
        imageView.stopAnimating()
        imageView.image = nil
        imageView.frame = .zero
        imageSize = nil
        hasConfiguredImage = false
        lastBoundsSize = .zero
        if !suppressCallbacks {
            dismissProgressHandler?(0)
        }
    }

    func centerImage() {
        let boundsSize = bounds.size
        var frameToCenter = imageView.frame

        frameToCenter.origin.x = frameToCenter.width < boundsSize.width
            ? (boundsSize.width - frameToCenter.width) / 2
            : 0
        frameToCenter.origin.y = frameToCenter.height < boundsSize.height
            ? (boundsSize.height - frameToCenter.height) / 2
            : 0

        imageView.frame = frameToCenter
    }

    private func configureLayout(resetZoom: Bool) {
        guard
            hasConfiguredImage,
            let imageSize,
            imageSize.width > 0,
            imageSize.height > 0,
            bounds.width > 0,
            bounds.height > 0
        else {
            return
        }

        lastBoundsSize = bounds.size
        let fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)

        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        contentSize = fittedSize
        minimumZoomScale = 1
        maximumZoomScale = configuredMaximumZoomScale

        if resetZoom || zoomScale < minimumZoomScale {
            zoomScale = 1
            contentOffset = .zero
        }

        centerImage()
    }

    @objc
    private func handleSingleTap() {
        singleTapHandler?()
    }

    @objc
    private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard hasConfiguredImage else { return }

        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(maximumZoomScale, 2.5)
        let tapPoint = gesture.location(in: imageView)
        let zoomRect = zoomRect(for: targetScale, centeredAt: tapPoint)
        zoom(to: zoomRect, animated: true)
    }

    @objc
    private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .changed:
            dismissProgressHandler?(max(0, translation.y))
        case .ended:
            let verticalTravel = max(0, translation.y)
            let velocity = gesture.velocity(in: self).y
            if verticalTravel > 140 || velocity > 900 {
                dismissHandler?()
            } else {
                dismissProgressHandler?(0)
            }
        case .cancelled, .failed:
            dismissProgressHandler?(0)
        default:
            break
        }
    }

    private func zoomRect(for scale: CGFloat, centeredAt point: CGPoint) -> CGRect {
        let size = CGSize(
            width: bounds.size.width / scale,
            height: bounds.size.height / scale
        )
        let origin = CGPoint(
            x: point.x - (size.width / 2),
            y: point.y - (size.height / 2)
        )
        return CGRect(origin: origin, size: size)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPanGesture else { return true }
        guard zoomScale <= minimumZoomScale + 0.01 else { return false }
        let velocity = dismissPanGesture.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === dismissPanGesture && otherGestureRecognizer === panGestureRecognizer) ||
        (gestureRecognizer === panGestureRecognizer && otherGestureRecognizer === dismissPanGesture)
    }
}

private extension View {
    @ViewBuilder
    func topicBottomBarButtonStyle(isProminent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if isProminent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.automatic)
            }
        } else {
            if isProminent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.automatic)
            }
        }
    }

    @ViewBuilder
    func ifAvailableiOS26GlassProminent() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.55))
        }
    }
}

private struct ModerationAlertComposerView: View {
    let preparedForm: ModerationAlertPreparedForm
    let moderationAlertService: any ModerationAlertService
    let onSubmitSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemePalette) private var themePalette

    @State private var reasonText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private static let warningText =
        "Attention : le message que vous écrivez ici sera envoyé directement aux modérateurs via message privé ou e-mail."

    private var canSend: Bool {
        !reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.warningText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $reasonText)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(themePalette.editorBackgroundColor)
                        .clipShape(.rect(cornerRadius: 10))

                    if reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Décrivez le problème...")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

                if isSending {
                    ProgressView("Envoi de l'alerte...")
                        .font(.footnote)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Alerte Modération")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        submitAlert()
                    }
                    .disabled(!canSend)
                }
            }
        }
        .alert("Alerte impossible", isPresented: isErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Erreur inconnue.")
        }
    }

    private func submitAlert() {
        guard canSend else { return }

        Task { @MainActor in
            isSending = true
            defer { isSending = false }

            do {
                let statusMessage = try await moderationAlertService.submitAlert(
                    reason: reasonText,
                    with: preparedForm
                )
                let trimmedStatus = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                onSubmitSuccess(trimmedStatus.isEmpty ? "Alerte envoyée." : trimmedStatus)
                dismiss()
            } catch let error as ReplyPostingError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Alerte impossible."
            }
        }
    }
}

private struct PostSuccessToastBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
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

private enum MessagesPreviewFactory {
    final class PreviewTopicPageLoader: TopicPageLoading {
        enum Result {
            case success(TopicPageContent)
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Swift.Result<TopicPageContent, Error>) -> Void) {
            let work = {
                switch self.result {
                case .success(let content):
                    completion(.success(content))
                case .failure(let error):
                    completion(.failure(error))
                }
            }

            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            } else {
                work()
            }
        }
    }

    struct PreviewTopicPageRenderer: TopicPageRendering {
        func render(html: String) throws -> TopicPageRenderOutput {
            let baseURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("hfrswift-preview", isDirectory: true)
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

            let fileURL = baseURL
                .appendingPathComponent("topic-\(UUID().uuidString)")
                .appendingPathExtension("htm")
            try html.write(to: fileURL, atomically: false, encoding: .utf8)
            return TopicPageRenderOutput(fileURL: fileURL, readAccessURL: baseURL)
        }
    }

    enum PreviewError: Error, LocalizedError {
        case network

        var errorDescription: String? {
            switch self {
            case .network:
                return "Connexion indisponible"
            }
        }
    }

    static var sampleHTML: String {
        """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>Topic preview</title>
            <style>
              body { font-family: -apple-system; margin: 16px; background: #f7f7f7; color: #111; }
              .post { background: white; border-radius: 10px; padding: 12px; margin-bottom: 10px; }
              .meta { font-size: 12px; color: #6b7280; margin-bottom: 4px; }
            </style>
          </head>
          <body>
            <article class="post">
              <div class="meta">alice - il y a 2 min</div>
              <p>Premiere reponse de preview.</p>
            </article>
            <article class="post">
              <div class="meta">bob - il y a 1 min</div>
              <p>Deuxieme reponse de preview.</p>
            </article>
          </body>
        </html>
        """
    }

    static func sampleTopic(page: Int = 55, maxPage: Int = 120) -> Topic {
        let topic = Topic()
        topic._aTitle = "Topic SwiftUI preview"
        topic.curTopicPage = Int32(page)
        topic.maxTopicPage = Int32(maxPage)
        topic.aURL = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=\(page)"
        topic.aURLOfLastPage = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=42&page=\(maxPage)"
        return topic
    }
}

#Preview("Messages - happy path") {
    NavigationStack {
        MessagesView(
            topic: MessagesPreviewFactory.sampleTopic(),
            curPage: 55,
            maxPage: 120,
            separatorNewMessages: true,
            topicPageLoader: MessagesPreviewFactory.PreviewTopicPageLoader(
                result: .success(
                    TopicPageContent(
                        html: MessagesPreviewFactory.sampleHTML,
                        topicAnswerURL: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42")
                    )
                )
            ),
            topicPageRenderer: MessagesPreviewFactory.PreviewTopicPageRenderer()
        )
    }
}

#Preview("Messages - loading") {
    NavigationStack {
        MessagesView(
            topic: MessagesPreviewFactory.sampleTopic(page: 12, maxPage: 48),
            curPage: 12,
            maxPage: 48,
            separatorNewMessages: true,
            topicPageLoader: MessagesPreviewFactory.PreviewTopicPageLoader(
                result: .success(
                    TopicPageContent(
                        html: MessagesPreviewFactory.sampleHTML,
                        topicAnswerURL: nil
                    )
                ),
                delay: 3
            ),
            topicPageRenderer: MessagesPreviewFactory.PreviewTopicPageRenderer()
        )
    }
}

#Preview("Messages - error") {
    NavigationStack {
        MessagesView(
            topic: MessagesPreviewFactory.sampleTopic(page: 1, maxPage: 5),
            curPage: 1,
            maxPage: 5,
            separatorNewMessages: true,
            topicPageLoader: MessagesPreviewFactory.PreviewTopicPageLoader(
                result: .failure(MessagesPreviewFactory.PreviewError.network)
            ),
            topicPageRenderer: MessagesPreviewFactory.PreviewTopicPageRenderer()
        )
    }
}
