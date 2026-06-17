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
import Photos

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

enum ReplyQuoteSelectionFormatter {
    static func format(quoteTemplate: String, selectedText: String, boldSelection: Bool) -> String {
        let selection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else {
            return quoteTemplate
        }

        let matches = quoteMessageMatches(in: quoteTemplate)
        guard !matches.isEmpty else {
            return quoteTemplate
        }

        if matches.count > 1,
           let matchingQuote = matches.first(where: { $0.fullText.range(of: selection, options: .caseInsensitive) != nil }) {
            return boldSelection
                ? boldedQuoteText(matchingQuote.fullText, selection: selection)
                : selectedOnlyQuote(from: matchingQuote, selection: selection)
        }

        guard matches.count == 1, let match = matches.first else {
            return quoteTemplate
        }

        return boldSelection
            ? boldedQuoteText(quoteTemplate, selection: selection)
            : selectedOnlyQuote(from: match, selection: selection)
    }

    private struct QuoteMessageMatch {
        let postID: String
        let categoryID: String
        let messageID: String
        let fullText: String
    }

    private static func quoteMessageMatches(in text: String) -> [QuoteMessageMatch] {
        let pattern = "\\[quotemsg=([0-9]+),([0-9]+),([0-9]+)\\][\\s\\S]*?\\[/quotemsg\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            guard
                let fullRange = Range(result.range(at: 0), in: text),
                let postRange = Range(result.range(at: 1), in: text),
                let categoryRange = Range(result.range(at: 2), in: text),
                let messageRange = Range(result.range(at: 3), in: text)
            else {
                return nil
            }

            return QuoteMessageMatch(
                postID: String(text[postRange]),
                categoryID: String(text[categoryRange]),
                messageID: String(text[messageRange]),
                fullText: String(text[fullRange])
            )
        }
    }

    private static func selectedOnlyQuote(from match: QuoteMessageMatch, selection: String) -> String {
        "[quotemsg=\(match.postID),\(match.categoryID),\(match.messageID)]\(selection)[/quotemsg]\n"
    }

    private static func boldedQuoteText(_ text: String, selection: String) -> String {
        guard let range = text.range(of: selection, options: .caseInsensitive) else {
            return text
        }
        var result = text
        result.replaceSubrange(range, with: "[b]\(String(text[range]))[/b]")
        return result.hasSuffix("\n") ? result : result + "\n"
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
        ObjCMPStorageBridge.shared.bookmark(topicID: topicID, postID: postID) != nil
    }

    static func createBookmark(
        topicID: String,
        topicCategory: String,
        postID: String,
        title: String,
        author: String
    ) -> Bool {
        ObjCMPStorageBridge.shared.addBookmark(
            topicID: topicID,
            topicCategory: topicCategory,
            postID: postID,
            title: title,
            author: author
        )
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
        ObjCLegacyAccountsManager.shared.currentAccountIdentity()?.displayNameLowercased ?? ""
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
    let onSubmit: (String, @escaping (Result<String, Error>) -> Void) -> Void
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
                            .hfrLoadingPanel(in: .rect(cornerRadius: 12))
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

        isSubmitting = true
        onSubmit(trimmedValue) { result in
            Task { @MainActor in
                isSubmitting = false
                switch result {
                case .success(let successMessage):
                    dismiss()
                    onSuccess(successMessage)
                case .failure(let error):
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}

final class MessageWebView: WKWebView {
    var messageActionsByIndex: [Int: TopicPageMessageActions] = [:]
    var onTextQuoteRequest: ((URL, String, Bool) -> Void)?

    private static let textQuoteSelector = #selector(MessageWebView.textQuote(_:))
    private static let textQuoteBoldSelector = #selector(MessageWebView.textQuoteBold(_:))

    static func installTextQuoteMenuItems() {
        let menu = UIMenuController.shared
        menu.menuItems = [
            UIMenuItem(title: "Citer extrait", action: textQuoteSelector),
            UIMenuItem(title: "Citer gras", action: textQuoteBoldSelector)
        ]
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == Self.textQuoteSelector || action == Self.textQuoteBoldSelector {
            return onTextQuoteRequest != nil
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard onTextQuoteRequest != nil else { return }
        let menu = UIMenu(
            title: "",
            options: .displayInline,
            children: [
                UICommand(title: "Citer extrait", image: UIImage(systemName: "quote.bubble"), action: Self.textQuoteSelector),
                UICommand(title: "Citer gras", image: UIImage(systemName: "bold"), action: Self.textQuoteBoldSelector)
            ]
        )
        builder.insertSibling(menu, afterMenu: .standardEdit)
    }

    @objc private func textQuote(_ sender: Any?) {
        requestTextQuote(boldSelection: false)
    }

    @objc private func textQuoteBold(_ sender: Any?) {
        requestTextQuote(boldSelection: true)
    }

    private func requestTextQuote(boldSelection: Bool) {
        let script = """
        (function() {
          var selection = window.getSelection && window.getSelection();
          if (!selection || selection.rangeCount === 0) { return null; }
          var selectedText = selection.toString();
          if (!selectedText || selectedText.trim().length === 0) { return null; }

          var node = selection.anchorNode;
          if (node && node.nodeType === Node.TEXT_NODE) {
            node = node.parentElement;
          }
          while (node && node !== document.body && node !== document.documentElement) {
            if (node.classList && node.classList.contains('message')) {
              var rawID = node.getAttribute('id') || '';
              var messageIndex = parseInt(rawID, 10);
              if (!isNaN(messageIndex)) {
                return { selectedText: selectedText, messageIndex: messageIndex };
              }
            }
            node = node.parentElement;
          }
          return null;
        })();
        """

        evaluateJavaScript(script) { [weak self] result, error in
            guard
                error == nil,
                let self,
                let payload = result as? [String: Any],
                let selectedText = payload["selectedText"] as? String,
                let messageIndex = Self.messageIndex(from: payload["messageIndex"]),
                messageIndex < 100,
                let quoteURL = self.messageActionsByIndex[messageIndex]?.quoteURL
            else {
                return
            }

            self.onTextQuoteRequest?(quoteURL, selectedText, boldSelection)
        }
    }

    private static func messageIndex(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }
}

struct WebView: UIViewRepresentable {
    struct ScrollPosition: Equatable {
        let y: CGFloat
        let viewportHeight: CGFloat
        let contentHeight: CGFloat
        let visibleAnchor: String?

        var distanceToBottom: CGFloat {
            max(contentHeight - (y + viewportHeight), 0)
        }
    }

    enum InitialScroll: Equatable {
        case top
        case bottom
        case position(ScrollPosition)
    }

    struct ScrollRequest: Equatable {
        let id: UUID
        let position: InitialScroll
    }

    let fileURL: URL?
    let readAccessURL: URL?
    var anchor: String?
    var initialScroll: InitialScroll?
    var scrollRequest: ScrollRequest?
    var currentPage: Int
    var maxPage: Int
    var colorScheme: ColorScheme
    var baseBackgroundColor: UIColor
    var themeRevision: Int
    var messageBodyFontSize: CGFloat
    var messageDisplayStyleRawValue: Int
    var messageMeBaseBackgroundColor: String
    var messageMeContentBackgroundColor: String
    var messageMeClassicHeaderBackgroundColor: String
    var messageLoveBaseBackgroundColor: String
    var messageLoveContentBackgroundColor: String
    var messageLoveModernHeaderBackgroundColor: String
    var messageClassicHeaderBackgroundColor: String
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
    var onToastRequest: ((String) -> Void)?
    var onTextQuoteRequest: ((URL, String, Bool) -> Void)?
    var onContentReady: (() -> Void)?
    var onScrollPositionChange: ((Bool) -> Void)?
    var onScrollPositionSnapshotChange: ((ScrollPosition) -> Void)?
    var onTextInteractionStateChange: ((Bool) -> Void)?

    init(
        fileURL: URL? = nil,
        readAccessURL: URL? = nil,
        anchor: String? = nil,
        initialScroll: InitialScroll? = nil,
        scrollRequest: ScrollRequest? = nil,
        currentPage: Int = 1,
        maxPage: Int = 1,
        colorScheme: ColorScheme = .light,
        baseBackgroundColor: UIColor = .systemGray6,
        themeRevision: Int = 0,
        messageBodyFontSize: CGFloat = 15,
        messageDisplayStyleRawValue: Int,
        messageMeBaseBackgroundColor: String,
        messageMeContentBackgroundColor: String,
        messageMeClassicHeaderBackgroundColor: String,
        messageLoveBaseBackgroundColor: String,
        messageLoveContentBackgroundColor: String,
        messageLoveModernHeaderBackgroundColor: String,
        messageClassicHeaderBackgroundColor: String,
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
        onToastRequest: ((String) -> Void)? = nil,
        onTextQuoteRequest: ((URL, String, Bool) -> Void)? = nil,
        onContentReady: (() -> Void)? = nil,
        onScrollPositionChange: ((Bool) -> Void)? = nil,
        onScrollPositionSnapshotChange: ((ScrollPosition) -> Void)? = nil,
        onTextInteractionStateChange: ((Bool) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.readAccessURL = readAccessURL
        self.anchor = anchor
        self.initialScroll = initialScroll
        self.scrollRequest = scrollRequest
        self.currentPage = currentPage
        self.maxPage = maxPage
        self.colorScheme = colorScheme
        self.baseBackgroundColor = baseBackgroundColor
        self.themeRevision = themeRevision
        self.messageBodyFontSize = messageBodyFontSize
        self.messageDisplayStyleRawValue = messageDisplayStyleRawValue
        self.messageMeBaseBackgroundColor = messageMeBaseBackgroundColor
        self.messageMeContentBackgroundColor = messageMeContentBackgroundColor
        self.messageMeClassicHeaderBackgroundColor = messageMeClassicHeaderBackgroundColor
        self.messageLoveBaseBackgroundColor = messageLoveBaseBackgroundColor
        self.messageLoveContentBackgroundColor = messageLoveContentBackgroundColor
        self.messageLoveModernHeaderBackgroundColor = messageLoveModernHeaderBackgroundColor
        self.messageClassicHeaderBackgroundColor = messageClassicHeaderBackgroundColor
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
        self.onToastRequest = onToastRequest
        self.onTextQuoteRequest = onTextQuoteRequest
        self.onContentReady = onContentReady
        self.onScrollPositionChange = onScrollPositionChange
        self.onScrollPositionSnapshotChange = onScrollPositionSnapshotChange
        self.onTextInteractionStateChange = onTextInteractionStateChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let bootstrapTheme = colorScheme == .dark ? "dark" : "light"
        let bootstrapVariables = MessageWebLegacyThemeVariables.variables(
            for: colorScheme,
            messageDisplayStyleRawValue: messageDisplayStyleRawValue
        )
        let bootstrapVariablesLiteral = MessageWebLegacyThemeVariables.javascriptObjectLiteral(for: bootstrapVariables)
        let bootstrapThemeScriptSource = """
        (function() {
          var root = document.documentElement;
          if (!root) { return; }
          root.setAttribute('data-theme', '\(bootstrapTheme)');
          var targetVars = \(bootstrapVariablesLiteral);
          Object.keys(targetVars).forEach(function(key) {
            root.style.setProperty(key, targetVars[key]);
          });
        })();
        """

        let contentController = WKUserContentController()
        let bootstrapThemeScript = WKUserScript(
            source: bootstrapThemeScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        contentController.addUserScript(bootstrapThemeScript)
        contentController.add(context.coordinator, name: "scrollState")
        contentController.add(context.coordinator, name: "textInteractionState")

        let scrollTrackingScript = WKUserScript(
            source: """
            (function() {
              function postAnchorForMessage(message) {
                if (!message) { return null; }
                var anchor = message.querySelector('a.anchorlink[name], a.anchorlink[id], a[name^="t"], a[id^="t"]');
                if (!anchor) { return null; }
                var value = anchor.getAttribute('name') || anchor.getAttribute('id') || '';
                return /^t\\d+$/i.test(value) ? value : null;
              }

              function visiblePostAnchor(viewport) {
                var messages = Array.prototype.slice.call(document.querySelectorAll('.message'));
                var bestAnchor = null;
                var bestScore = Number.MAX_VALUE;
                for (var i = 0; i < messages.length; i++) {
                  var message = messages[i];
                  var rect = message.getBoundingClientRect();
                  if (rect.bottom <= 0 || rect.top >= viewport) { continue; }
                  var anchor = postAnchorForMessage(message);
                  if (!anchor) { continue; }
                  var score = Math.abs(rect.top - 8);
                  if (rect.top < 0) { score += Math.abs(rect.top) * 0.25; }
                  if (score < bestScore) {
                    bestScore = score;
                    bestAnchor = anchor;
                  }
                }
                return bestAnchor;
              }

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
                try {
                  window.webkit.messageHandlers.scrollState.postMessage({
                    atBottom: atBottom,
                    y: scrollY,
                    viewportHeight: viewport,
                    contentHeight: contentHeight,
                    visibleAnchor: visiblePostAnchor(viewport)
                  });
                } catch (e) {}
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

        let textInteractionTrackingScript = WKUserScript(
            source: """
            (function() {
              if (window.__hfrTextInteractionTrackingInstalled) { return; }
              window.__hfrTextInteractionTrackingInstalled = true;

              var lastActive = null;
              var contextMenuTimer = null;

              function hasTextSelection() {
                var selection = window.getSelection && window.getSelection();
                return !!selection && selection.rangeCount > 0 && selection.toString().trim().length > 0;
              }

              function notify(active) {
                if (active === lastActive) { return; }
                lastActive = active;
                try { window.webkit.messageHandlers.textInteractionState.postMessage(active); } catch (e) {}
              }

              function refresh() {
                notify(hasTextSelection());
              }

              document.addEventListener('selectionchange', function() {
                setTimeout(refresh, 0);
              }, false);

              document.addEventListener('contextmenu', function() {
                notify(true);
                if (contextMenuTimer) {
                  clearTimeout(contextMenuTimer);
                }
                contextMenuTimer = setTimeout(refresh, 1500);
              }, true);

              document.addEventListener('touchstart', function() {
                if (!hasTextSelection()) {
                  notify(false);
                }
              }, { passive: true });

              window.addEventListener('blur', refresh, false);
              setTimeout(refresh, 0);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(textInteractionTrackingScript)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        MessageWebView.installTextQuoteMenuItems()

        let webView = MessageWebView(frame: .zero, configuration: configuration)
        webView.messageActionsByIndex = messageActionsByIndex
        webView.onTextQuoteRequest = onTextQuoteRequest
        webView.isOpaque = false
        webView.backgroundColor = baseBackgroundColor
        webView.scrollView.backgroundColor = baseBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = baseBackgroundColor
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
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
        context.coordinator.messageBodyFontSize = messageBodyFontSize
        context.coordinator.messageDisplayStyleRawValue = messageDisplayStyleRawValue
        context.coordinator.messageMeBaseBackgroundColor = messageMeBaseBackgroundColor
        context.coordinator.messageMeContentBackgroundColor = messageMeContentBackgroundColor
        context.coordinator.messageMeClassicHeaderBackgroundColor = messageMeClassicHeaderBackgroundColor
        context.coordinator.messageLoveBaseBackgroundColor = messageLoveBaseBackgroundColor
        context.coordinator.messageLoveContentBackgroundColor = messageLoveContentBackgroundColor
        context.coordinator.messageLoveModernHeaderBackgroundColor = messageLoveModernHeaderBackgroundColor
        context.coordinator.messageClassicHeaderBackgroundColor = messageClassicHeaderBackgroundColor
        if let messageWebView = webView as? MessageWebView {
            messageWebView.messageActionsByIndex = messageActionsByIndex
            messageWebView.onTextQuoteRequest = onTextQuoteRequest
        }
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
                context.coordinator.lastAppliedMessageBodyFontSize = nil
                context.coordinator.lastAppliedMessageStyleSignature = nil
                context.coordinator.isWaitingForThemeApplication = true
                context.coordinator.didNotifyContentReadyForCurrentLoad = false
                webView.isHidden = true
                webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
            } else {
                if let scrollRequest,
                   context.coordinator.lastHandledScrollRequestID != scrollRequest.id {
                    context.coordinator.lastHandledScrollRequestID = scrollRequest.id
                    context.coordinator.applyScrollRequest(scrollRequest, in: webView)
                }
                context.coordinator.applyThemeIfNeeded(in: webView, force: shouldForceThemeApplication) {
                    context.coordinator.applyMessageStyleIfNeeded(in: webView, force: shouldForceThemeApplication) {
                        context.coordinator.applyTextSizeIfNeeded(in: webView) {
                            if !context.coordinator.isWaitingForThemeApplication {
                                webView.isHidden = false
                            }
                        }
                    }
                }
            }
        }

    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIEditMenuInteractionDelegate, WKUIDelegate {
        var parent: WebView
        var anchor: String?
        var initialScroll: WebView.InitialScroll?
        var colorScheme: ColorScheme
        var themeRevision: Int
        var messageBodyFontSize: CGFloat
        var messageDisplayStyleRawValue: Int
        var messageMeBaseBackgroundColor: String
        var messageMeContentBackgroundColor: String
        var messageMeClassicHeaderBackgroundColor: String
        var messageLoveBaseBackgroundColor: String
        var messageLoveContentBackgroundColor: String
        var messageLoveModernHeaderBackgroundColor: String
        var messageClassicHeaderBackgroundColor: String
        var loadedFileURL: URL?
        var loadedReadAccessURL: URL?
        var lastAppliedTheme: String?
        var lastAppliedThemeRevision: Int = -1
        var lastAppliedMessageBodyFontSize: CGFloat?
        var lastAppliedMessageStyleSignature: String?
        var isWaitingForThemeApplication = false
        var didNotifyContentReadyForCurrentLoad = false
        var lastHandledScrollRequestID: UUID?
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
            self.messageBodyFontSize = parent.messageBodyFontSize
            self.messageDisplayStyleRawValue = parent.messageDisplayStyleRawValue
            self.messageMeBaseBackgroundColor = parent.messageMeBaseBackgroundColor
            self.messageMeContentBackgroundColor = parent.messageMeContentBackgroundColor
            self.messageMeClassicHeaderBackgroundColor = parent.messageMeClassicHeaderBackgroundColor
            self.messageLoveBaseBackgroundColor = parent.messageLoveBaseBackgroundColor
            self.messageLoveContentBackgroundColor = parent.messageLoveContentBackgroundColor
            self.messageLoveModernHeaderBackgroundColor = parent.messageLoveModernHeaderBackgroundColor
            self.messageClassicHeaderBackgroundColor = parent.messageClassicHeaderBackgroundColor
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WKWebView didFinish. anchor =", anchor as Any, "initialScroll =", String(describing: initialScroll), "url:", webView.url?.absoluteString ?? "nil")
            applyThemeIfNeeded(in: webView, force: true) {
                self.applyMessageStyleIfNeeded(in: webView, force: true) {
                    self.applyTextSizeIfNeeded(in: webView, force: true) {
                        self.isWaitingForThemeApplication = false
                        webView.isHidden = false
                        self.notifyContentReadyIfNeeded()
                    }
                }
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
            case .position(let position):
                restoreScrollPosition(position, in: webView)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    self.restoreScrollPosition(position, in: webView)
                }
                print("Initial scroll restored at y=\(position.y)")
            }
        }

        func applyScrollRequest(_ request: WebView.ScrollRequest, in webView: WKWebView) {
            switch request.position {
            case .top:
                let js = "try { window.scrollTo(0, 0); } catch(e) {}"
                webView.evaluateJavaScript(js) { _, error in
                    if let error {
                        print("Scroll-to-top JS error:", error.localizedDescription)
                    }
                    DispatchQueue.main.async {
                        let scrollView = webView.scrollView
                        let targetOffset = CGPoint(
                            x: -scrollView.adjustedContentInset.left,
                            y: -scrollView.adjustedContentInset.top
                        )
                        scrollView.setContentOffset(targetOffset, animated: false)
                    }
                }
            case .bottom:
                scrollToBottom(in: webView)
            case .position(let position):
                restoreScrollPosition(position, in: webView)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "scrollState":
                let isAtBottom: Bool
                let scrollPosition: WebView.ScrollPosition?
                if let payload = message.body as? [String: Any] {
                    if let boolValue = payload["atBottom"] as? Bool {
                        isAtBottom = boolValue
                    } else if let numberValue = payload["atBottom"] as? NSNumber {
                        isAtBottom = numberValue.boolValue
                    } else {
                        return
                    }

                    let y = Self.cgFloatValue(from: payload["y"]) ?? 0
                    let viewportHeight = Self.cgFloatValue(from: payload["viewportHeight"]) ?? 0
                    let contentHeight = Self.cgFloatValue(from: payload["contentHeight"]) ?? 0
                    let visibleAnchor = (payload["visibleAnchor"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    scrollPosition = WebView.ScrollPosition(
                        y: max(y, 0),
                        viewportHeight: max(viewportHeight, 0),
                        contentHeight: max(contentHeight, 0),
                        visibleAnchor: visibleAnchor?.isEmpty == false ? visibleAnchor : nil
                    )
                } else if let boolValue = message.body as? Bool {
                    isAtBottom = boolValue
                    scrollPosition = nil
                } else if let numberValue = message.body as? NSNumber {
                    isAtBottom = numberValue.boolValue
                    scrollPosition = nil
                } else {
                    return
                }

                DispatchQueue.main.async {
                    self.parent.onScrollPositionChange?(isAtBottom)
                    if let scrollPosition {
                        self.parent.onScrollPositionSnapshotChange?(scrollPosition)
                    }
                }
            case "textInteractionState":
                let isActive: Bool
                if let boolValue = message.body as? Bool {
                    isActive = boolValue
                } else if let numberValue = message.body as? NSNumber {
                    isActive = numberValue.boolValue
                } else {
                    return
                }

                DispatchQueue.main.async {
                    self.parent.onTextInteractionStateChange?(isActive)
                }
            default:
                return
            }
        }

        private static func cgFloatValue(from value: Any?) -> CGFloat? {
            if let doubleValue = value as? Double {
                return CGFloat(doubleValue)
            }
            if let intValue = value as? Int {
                return CGFloat(intValue)
            }
            if let numberValue = value as? NSNumber {
                return CGFloat(numberValue.doubleValue)
            }
            if let stringValue = value as? String, let doubleValue = Double(stringValue) {
                return CGFloat(doubleValue)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
            completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
        ) {
            guard let imageURL = imageURLForContextMenuElementInfo(elementInfo) else {
                completionHandler(nil)
                return
            }

            let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }

                let openAction = UIAction(
                    title: "Ouvrir l'image",
                    image: UIImage(systemName: "photo")
                ) { _ in
                    self.parent.onWebAction?(.presentImageViewer(imageURL))
                }

                let saveAction = UIAction(
                    title: "Save to Photos",
                    image: UIImage(systemName: "square.and.arrow.down")
                ) { _ in
                    self.saveImageToPhotoLibrary(from: imageURL)
                }

                let copyAction = UIAction(
                    title: "Copier le lien",
                    image: UIImage(systemName: "doc.on.doc")
                ) { _ in
                    UIPasteboard.general.url = imageURL
                }

                return UIMenu(title: "", children: [openAction, saveAction, copyAction])
            }

            completionHandler(configuration)
        }

        private func notifyContentReadyIfNeeded() {
            guard !didNotifyContentReadyForCurrentLoad else { return }
            didNotifyContentReadyForCurrentLoad = true
            DispatchQueue.main.async {
                self.parent.onContentReady?()
            }
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

            let targetVariables = MessageWebLegacyThemeVariables.variables(
                for: colorScheme,
                messageDisplayStyleRawValue: messageDisplayStyleRawValue
            )
            let targetVariablesLiteral = MessageWebLegacyThemeVariables.javascriptObjectLiteral(for: targetVariables)
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

              var targetVars = \(targetVariablesLiteral);
              Object.keys(targetVars).forEach(function(key) {
                root.style.setProperty(key, targetVars[key]);
              });
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

        func applyMessageStyleIfNeeded(
            in webView: WKWebView,
            force: Bool = false,
            completion: (() -> Void)? = nil
        ) {
            let styleSignature = [
                String(messageDisplayStyleRawValue),
                String(describing: colorScheme),
                messageMeBaseBackgroundColor,
                messageMeContentBackgroundColor,
                messageMeClassicHeaderBackgroundColor,
                messageLoveBaseBackgroundColor,
                messageLoveContentBackgroundColor,
                messageLoveModernHeaderBackgroundColor,
                messageClassicHeaderBackgroundColor
            ].joined(separator: "|")

            guard force || lastAppliedMessageStyleSignature != styleSignature else {
                completion?()
                return
            }

            let isModernStyle = messageDisplayStyleRawValue == 1
            let messageHeaderBackground = isModernStyle ? "var(--color-message-background)" : messageClassicHeaderBackgroundColor
            let messageHeaderMeBackground = isModernStyle ? "var(--color-message-mequoted-background)" : messageMeClassicHeaderBackgroundColor
            let messageHeaderLoveBackground = isModernStyle ? messageLoveModernHeaderBackgroundColor : messageLoveBaseBackgroundColor
            let messageContentPaddingTop = isModernStyle ? "0px" : "8px"
            let messageContentRightWidth = isModernStyle ? "calc(100% - 52px)" : "calc(100% - 10px)"
            let messageHeaderLeftMarginTop = isModernStyle ? "6px" : "8px"
            let variables: [(String, String)] = [
                ("--color-message-header-me-background-base", messageMeBaseBackgroundColor),
                ("--color-message-header-love-background-base", messageLoveBaseBackgroundColor),
                ("--message-content-padding-top", messageContentPaddingTop),
                ("--message-content-right-width", messageContentRightWidth),
                ("--message-header-left-margin-top", messageHeaderLeftMarginTop),
                ("--color-message-header-background", messageHeaderBackground),
                ("--color-message-header-me-background", messageHeaderMeBackground),
                ("--color-message-header-love-background", messageHeaderLoveBackground)
            ]
            let variableAssignments = variables
                .map { "root.style.setProperty(\($0.0.debugDescription), \($0.1.debugDescription));" }
                .joined(separator: "\n              ")
            let css: String
            if isModernStyle {
                css = """
                :root {
                  --color-message-header-me-background-base: \(messageMeBaseBackgroundColor);
                  --color-message-header-love-background-base: \(messageLoveBaseBackgroundColor);
                  --message-content-padding-top: \(messageContentPaddingTop);
                  --message-content-right-width: \(messageContentRightWidth);
                  --message-header-left-margin-top: \(messageHeaderLeftMarginTop);
                  --color-message-header-background: \(messageHeaderBackground);
                  --color-message-header-me-background: \(messageHeaderMeBackground);
                  --color-message-header-love-background: \(messageHeaderLoveBackground);
                }
                """
            } else {
                css = """
                :root {
                  --color-message-header-me-background-base: \(messageMeBaseBackgroundColor);
                  --color-message-header-love-background-base: \(messageLoveBaseBackgroundColor);
                  --message-content-padding-top: \(messageContentPaddingTop);
                  --message-content-right-width: \(messageContentRightWidth);
                  --message-header-left-margin-top: \(messageHeaderLeftMarginTop);
                  --color-message-header-background: \(messageHeaderBackground);
                  --color-message-header-me-background: \(messageHeaderMeBackground);
                  --color-message-header-love-background: \(messageHeaderLoveBackground);
                }
                """
            }

            let encodedCSS = css.debugDescription
            let script = """
            (function() {
              var root = document.documentElement;
              if (!root) { return; }

              var cssLink = document.getElementById('light-styles');
              if (cssLink) {
                cssLink.setAttribute('href', 'style-liste-light.css');
              }

              \(variableAssignments)

              var style = document.getElementById('hfrswift-message-style');
              if (!style && document.head) {
                style = document.createElement('style');
                style.id = 'hfrswift-message-style';
                document.head.appendChild(style);
              }
              if (style) {
                style.textContent = \(encodedCSS);
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error = error {
                    print("Message style JS error:", error.localizedDescription)
                } else {
                    self?.lastAppliedMessageStyleSignature = styleSignature
                }
                completion?()
            }
        }

        func applyTextSizeIfNeeded(
            in webView: WKWebView,
            force: Bool = false,
            completion: (() -> Void)? = nil
        ) {
            guard force || lastAppliedMessageBodyFontSize != messageBodyFontSize else {
                completion?()
                return
            }

            let fontSize = max(messageBodyFontSize, 1)
            let script = """
            (function() {
              var css = ".message .content .right { font-size: \(fontSize)px !important; }";
              var style = document.getElementById('hfrswift-text-size');
              if (!style && document.head) {
                style = document.createElement('style');
                style.id = 'hfrswift-text-size';
                document.head.appendChild(style);
              }
              if (style) {
                style.textContent = css;
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error = error {
                    print("Text size JS error:", error.localizedDescription)
                } else {
                    self?.lastAppliedMessageBodyFontSize = fontSize
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
                                let message = ObjCProfileFilterListManager.shared.toggleBlacklist(pseudo: authorName)
                                if let message {
                                    showToast(message)
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
                                let message = ObjCProfileFilterListManager.shared.toggleWhitelist(pseudo: authorName)
                                if let message {
                                    showToast(message)
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
                            handler: { [weak self] in
                                self?.performFavoriteAction(favoriteURL)
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

        private func performFavoriteAction(_ url: URL) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            URLSession.shared.dataTask(with: request) { data, _, error in
                if error != nil {
                    DispatchQueue.main.async {
                        self.parent.onToastRequest?("Erreur réseau")
                    }
                    return
                }

                let response = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let message = MessagePopupActionSupport.favoriteResponseMessage(from: response) ?? "Favori mis à jour"
                DispatchQueue.main.async {
                    self.parent.onToastRequest?(message)
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
                showToast("Données AQ incomplètes")
                return
            }

            Task { @MainActor in
                let alreadySignaled = await MessagePopupActionSupport.isAQAlreadySignaled(topicID: topicID, postID: postID)
                if alreadySignaled == true {
                    showToast("Post déjà signalé")
                    return
                }
                if alreadySignaled == nil {
                    showToast("Création d'AQ impossible")
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
                                self.showToast("Alerte Qualitay créée.")
                            case .failure(let code):
                                self.showToast("Code erreur \(code)")
                            case .networkError:
                                self.showToast("Création d'AQ impossible")
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
                showToast("Données bookmark incomplètes")
                return
            }

            if MessagePopupActionSupport.hasBookmark(topicID: topicID, postID: postID) {
                showToast("Post déjà dans les bookmarks")
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
                        self.showToast("Bookmark créé")
                    } else {
                        self.showToast("Erreur à la création du bookmark")
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

            let isFavorite = ReplySmileyCacheBridge.isFavoriteFromApp(code: payload.code)
            let actionTitle = isFavorite ? "Retirer des favoris" : "Ajouter aux favoris"

            let alert = UIAlertController(
                title: payload.code,
                message: nil,
                preferredStyle: .actionSheet
            )

            alert.addAction(
                UIAlertAction(title: actionTitle, style: .default) { _ in
                    _ = ReplySmileyCacheBridge.updateAppFavorite(
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

        private func imageURLForContextMenuElementInfo(_ elementInfo: WKContextMenuElementInfo) -> URL? {
            guard let linkURL = elementInfo.linkURL else {
                return nil
            }

            let normalizedURL = normalizeContextMenuImageURL(linkURL)
            return isImageURL(normalizedURL) ? normalizedURL : nil
        }

        private func isImageURL(_ url: URL) -> Bool {
            let imageExtensions: Set<String> = [
                "jpg",
                "jpeg",
                "png",
                "gif",
                "webp",
                "bmp",
                "tif",
                "tiff",
                "heic",
                "heif"
            ]
            let pathExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if imageExtensions.contains(pathExtension) {
                return true
            }

            if let host = url.host?.lowercased(),
               host == "reho.st" || host.hasSuffix(".reho.st") || host == "img3.super-h.fr" || host == "rehost.diberie.com" {
                return true
            }

            return false
        }

        private func saveImageToPhotoLibrary(from url: URL) {
            Task {
                let result = await MessageImagePhotoLibrarySaver.saveImage(from: url)
                await MainActor.run {
                    switch result {
                    case .success:
                        showToast("Photo enregistrée")
                    case .failure(.permissionDenied):
                        showToast("Autorise l'accès aux Photos pour enregistrer l'image.")
                    case .failure(.invalidImageData):
                        showToast("Impossible d'enregistrer cette image.")
                    case .failure(.network):
                        showToast("Erreur réseau")
                    case .failure(.system):
                        showToast("L'enregistrement dans Photos a échoué.")
                    }
                }
            }
        }

        private func normalizeContextMenuImageURL(_ url: URL) -> URL {
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

        private func showToast(_ message: String) {
            parent.onToastRequest?(message)
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

        private func restoreScrollPosition(_ position: WebView.ScrollPosition, in webView: WKWebView) {
            let y = Double(max(position.y, 0))
            let script = """
            (function(targetY) {
              function restore() {
                var root = document.documentElement || {};
                var body = document.body || {};
                var viewport = window.innerHeight || root.clientHeight || 0;
                var contentHeight = Math.max(
                  body.scrollHeight || 0,
                  root.scrollHeight || 0,
                  body.offsetHeight || 0,
                  root.offsetHeight || 0
                );
                var maxY = Math.max(0, contentHeight - viewport);
                var y = Math.min(Math.max(0, targetY), maxY);
                try { window.scrollTo(0, y); } catch(e) {}
                return y;
              }

              setTimeout(restore, 50);
              return restore();
            })(\(y));
            """

            webView.evaluateJavaScript(script) { _, error in
                guard error != nil else { return }

                let scrollView = webView.scrollView
                let minOffsetY = -scrollView.adjustedContentInset.top
                let maxOffsetY = max(
                    minOffsetY,
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
                )
                let targetOffsetY = min(max(minOffsetY + position.y, minOffsetY), maxOffsetY)
                let targetOffset = CGPoint(
                    x: -scrollView.adjustedContentInset.left,
                    y: targetOffsetY
                )
                scrollView.setContentOffset(targetOffset, animated: false)
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

private enum MessageWebLegacyThemeVariables {
    static func variables(for colorScheme: ColorScheme, messageDisplayStyleRawValue: Int) -> [String: String] {
        let theme = colorScheme == .dark ? ThemeDark : ThemeLight
        let isModernStyle = messageDisplayStyleRawValue == 1
        let tintColor = ThemeColors.tintColor(theme)
        let loveColor = ThemeColors.loveColor(theme)
        let textColor = ThemeColors.textColor(theme)
        let textFieldBackgroundColor = ThemeColors.textFieldBackgroundColor(theme)
        let textColorPseudo = ThemeColors.textColorPseudo(theme)

        return [
            "--color-action": ThemeColors.hex(from: tintColor),
            "--color-action-disabled": ThemeColors.hex(from: ThemeColors.tintColorDisabled(theme)),
            "--color-message-background": ThemeColors.hex(from: ThemeColors.messageBackgroundColor(theme)),
            "--color-message-modo-background": ThemeColors.hex(from: ThemeColors.messageModoBackgroundColor(theme)),
            "--color-message-header-me-background": ThemeColors.rgba(from: tintColor, withAlpha: isModernStyle ? 0.03 : 0.15),
            "--color-message-mequoted-background": ThemeColors.rgba(from: tintColor, withAlpha: 0.03),
            "--color-message-mequoted-borderleft": ThemeColors.rgba(from: tintColor, withAlpha: 1.0),
            "--color-message-mequoted-borderother": ThemeColors.rgba(from: ThemeColors.tintLightColorNoAlpha()),
            "--color-message-header-love-background": ThemeColors.rgba(from: loveColor, withAlpha: isModernStyle ? 0.4 : 1.0),
            "--color-message-quoted-love-background": ThemeColors.rgba(from: loveColor, withAlpha: 0.3),
            "--color-message-quoted-love-borderleft": ThemeColors.rgba(from: loveColor, withAlpha: 1.0, addSaturation: 1.0, addBrightness: 1.0),
            "--color-message-quoted-love-borderother": ThemeColors.rgba(from: ThemeColors.loveLightColorNoAlpha()),
            "--color-message-quoted-bl-background": ThemeColors.rgba(from: textColor, withAlpha: 0.05),
            "--color-message-header-bl-background": ThemeColors.rgba(from: textFieldBackgroundColor, withAlpha: 0.7),
            "--color-separator-new-message": ThemeColors.rgba(from: textColorPseudo, withAlpha: 0.5),
            "--color-text": ThemeColors.hex(from: textColor),
            "--color-text2": ThemeColors.hex(from: ThemeColors.textColor2(theme)),
            "--color-background-bars": ThemeColors.hex(from: textFieldBackgroundColor),
            "--color-searchintra-nextresults": ThemeColors.rgba(from: textFieldBackgroundColor, withAlpha: 0.9),
            "--imagefile-avatar": colorScheme == .dark ? "url(avatar_male_gray_on_dark_48x48.png)" : "url(avatar_male_gray_on_light_48x48.png)",
            "--imagefile-loadinfo": colorScheme == .dark ? "url(loadinfo.net.gif)" : "url(loadinfo.gif)",
            "--color-border-quotation": ThemeColors.getColorBorderQuotation(theme),
            "--color-border-avatar": ThemeColors.hex(from: ThemeColors.getColorBorderAvatar(theme)),
            "--color-text-pseudo": ThemeColors.hex(from: textColorPseudo),
            "--color-text-pseudo-bl": ThemeColors.rgba(from: textColorPseudo, withAlpha: 0.5),
            "--border-header": "none"
        ]
    }

    static func javascriptObjectLiteral(for variables: [String: String]) -> String {
        let pairs = variables
            .sorted { $0.key < $1.key }
            .map { "\($0.key.debugDescription): \($0.value.debugDescription)" }
            .joined(separator: ",\n                ")
        return "{\n                \(pairs)\n              }"
    }
}

enum MessageImagePhotoLibrarySaver {
    enum SaveError: Error {
        case permissionDenied
        case invalidImageData
        case network
        case system
    }

    static func saveImage(from url: URL) async -> Result<Void, SaveError> {
        let authorizationStatus = await requestPhotoLibraryAccess()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return .failure(.permissionDenied)
        }

        let request = PhotoViewerNetworkRequestFactory.makeRequest(for: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let isValidResponse = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            guard isValidResponse, UIImage(data: data) != nil else {
                return .failure(.invalidImageData)
            }

            try await writeImageDataToPhotoLibrary(data)
            return .success(())
        } catch let error as SaveError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    @MainActor
    private static func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if currentStatus == .notDetermined {
            return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return currentStatus
    }

    private static func writeImageDataToPhotoLibrary(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SaveError.system)
                }
            }
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

    private struct UserProfileDestination: Identifiable {
        let id = UUID()
        let url: URL
        let avatarActions: TopicPageMessageActions?
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

    private struct TopicSearchSheetState: Identifiable {
        let id = UUID()
        let initialParams: TopicSearchParams
        let isFromResultsPage: Bool
    }

    private struct TopicPageLoadRestoration {
        let fetchAnchor: String?
        let scrollAnchor: String?
        let fallbackInitialScroll: WebView.InitialScroll?
        let previousLastAnchor: String?
        let scrollToBottomWhenNoNewerPost: Bool
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
    let topicSearchService: any TopicSearchServicing
    let initialSearchContext: TopicSearchContext?
    let favoritePostFilterService: any FavoritePostFilteringServicing
    let initialFavoritePostFilterResult: FavoritePostFilterResult?
    private let resetMessagesStackToRootAction: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject private var appTheme = AppThemeStore.shared
    @AppStorage(AppTextSizeScale.key) private var textSizeScaleRawValue = AppTextSizeScale.standard.rawValue
    @AppStorage("theme_style") private var messageDisplayStyleRawValue = 1
    @State private var page: Int
    @State private var availableMaxPage: Int
    @State private var topicDisplayTitle: String
    @State private var fileURL: URL?
    @State private var cacheURL: URL?
    @State private var errorMessage: String?
    @State private var shouldTriggerRefreshCompletionHaptic = false
    @State private var anchor: String?
    @State private var initialScroll: WebView.InitialScroll?
    @State private var topicAnswerURL: URL?
    @State private var composerSubmitURL: URL?
    @State private var messageActionsByIndex: [Int: TopicPageMessageActions] = [:]
    @AppStorage("composerDraftText") private var composerDraftText: String = ""
    @State private var isComposerPresented = false
    @State private var composerInitialMessage = ""
    @State private var composerPersistsDraft = false
    @State private var isPresentingComposer = false  // This will be removed now
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var isComposerMinimized = false
    @State private var animateLoadingSpinner = false
    @State private var isPagePickerPresented = false
    @State private var pagePickerInput: String = ""
    @State private var webViewScrollRequest: WebView.ScrollRequest?
    @State private var lastWebViewScrollPosition: WebView.ScrollPosition?
    @State private var linkedTopicDestination: AnyView?
    @State private var navigateToLinkedTopic = false
    @State private var safariDestination: SafariDestination?
    @State private var userProfileDestination: UserProfileDestination?
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
    @State private var hasPoll = false
    @State private var pollIsNewVote = false
    @State private var pollData: PollData?
    @State private var presentedPollData: PollData?
    @State private var showWebViewLoadCover = true
    @State private var isWebContentAtBottom = false
    @State private var isMessageTextInteractionActive = false
    @State private var pendingPostedReply: ReplyPostingResult?
    @State private var showPostSuccessToast = false
    @State private var postSuccessToastText = "Hooray"
    @State private var activeTopicLoadToken: UUID?
    @State private var topicLoadTimeoutWorkItem: DispatchWorkItem?
    @State private var searchContext: TopicSearchContext?
    @State private var topicSearchSheetState: TopicSearchSheetState?
    @State private var lastSearchFormSnapshot: [String: String] = [:]
    @State private var searchResultDestination: AnyView?
    @State private var navigateToSearchResult = false
    @State private var hasConsumedInitialSearchURL = false
    @State private var isAdvancingSearchResults = false
    @State private var searchErrorMessage: String?
    @State private var favoritePostFilterResult: FavoritePostFilterResult?
    @State private var hasConsumedInitialFavoritePostFilterResult = false
    @State private var isAdvancingFavoritePostFilterResults = false
    @State private var favoritePostFilterErrorMessage: String?
    // Remove the unused
    // @State private var isPresentingAddMessage = false

    private var themePalette: AppThemePalette {
        appTheme.palette
    }

    private var linkedTopicNavigationBinding: Binding<Bool> {
        Binding(
            get: { navigateToLinkedTopic },
            set: { isActive in
                navigateToLinkedTopic = isActive
                if !isActive {
                    linkedTopicDestination = nil
                }
            }
        )
    }

    private var searchResultNavigationBinding: Binding<Bool> {
        Binding(
            get: { navigateToSearchResult },
            set: { isActive in
                navigateToSearchResult = isActive
                if !isActive {
                    searchResultDestination = nil
                }
            }
        )
    }

    private var shouldHideReplyComposerButton: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact
    }

    private var loadingTopicView: some View {
        ZStack {
            themePalette.webViewBackdropColor
                .ignoresSafeArea()
            VStack(spacing: 8) {
                ProgressView()
                    .neutralLoadingSpinner()
                Text("Chargement...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var messageBodyFontSize: CGFloat {
        AppTextSizeScale.scaledUIFont(
            textStyle: .body,
            basePointSize: 15,
            rawValue: textSizeScaleRawValue
        ).pointSize
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
        moderationAlertService: any ModerationAlertService = ForumModerationAlertService(),
        topicSearchService: any TopicSearchServicing = ObjCTopicSearchService(),
        initialSearchContext: TopicSearchContext? = nil,
        favoritePostFilterService: any FavoritePostFilteringServicing = ObjCFavoritePostFilterService(),
        initialFavoritePostFilterResult: FavoritePostFilterResult? = nil,
        resetMessagesStackToRootAction: (() -> Void)? = nil
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
        self.topicSearchService = topicSearchService
        self.initialSearchContext = initialSearchContext
        self.favoritePostFilterService = favoritePostFilterService
        self.initialFavoritePostFilterResult = initialFavoritePostFilterResult
        self.resetMessagesStackToRootAction = resetMessagesStackToRootAction
        self._page = State(initialValue: curPage)
        self._availableMaxPage = State(initialValue: max(max(maxPage, curPage), 1))
        self._topicDisplayTitle = State(initialValue: topic._aTitle ?? "")
        self._initialScroll = State(initialValue: initialLoadScroll)
        self._searchContext = State(initialValue: initialSearchContext)
        self._favoritePostFilterResult = State(initialValue: initialFavoritePostFilterResult)

        // extraire l’ancre (#xxxx) si présente
        if let url = URL(string: topic.aURL), let fragment = url.fragment {
            self._anchor = State(initialValue: fragment)
            print("INIT extracted anchor:", fragment)
        }
        print("[TopicPageTrace][MessagesView.init] title=\(topic._aTitle ?? "") initCurPage=\(curPage) initMaxPage=\(maxPage) topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage) topicURL=\(topic.aURL ?? "nil") flagURL=\(topic.aURLOfFlag ?? "nil") lastPostURL=\(topic.aURLOfLastPost ?? "nil") lastPageURL=\(topic.aURLOfLastPage ?? "nil") initialScroll=\(String(describing: initialLoadScroll))")
    }

    private func urlForPage(_ page: Int) -> String {
        if isFilteredSearchMode, let searchContext {
            print("[TopicPageTrace][MessagesView.urlForPage] source=filteredSearch requestedPage=\(page) resultURL=\(searchContext.resultURL.absoluteString) statePage=\(self.page) stateMax=\(currentMaxPage)")
            return searchContext.resultURL.absoluteString
        }
        let baseURL = topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfFirstPage ?? ""
        let resolvedURL = TopicPageURLRouting.replacingPage(in: baseURL, page: page)
        print("[TopicPageTrace][MessagesView.urlForPage] source=topic requestedPage=\(page) baseURL=\(baseURL) resolvedURL=\(resolvedURL) statePage=\(self.page) stateMax=\(currentMaxPage) topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage)")
        return resolvedURL
    }

    private var isInSearchMode: Bool {
        searchContext != nil
    }

    private var isFilteredSearchMode: Bool {
        searchContext?.params.filterEnabled == true
    }

    private var isFavoritePostFilterMode: Bool {
        favoritePostFilterResult != nil
    }

    private var toolbarSubtitleText: String {
        if let favoritePostFilterResult {
            return favoritePostFilterResult.subtitle
        }
        if isFilteredSearchMode {
            return "Recherche filtrée"
        }
        if isInSearchMode {
            return "Recherche | \(page) / \(currentMaxPage)"
        }
        return "\(page) / \(currentMaxPage)"
    }

    @ViewBuilder
    private var toolbarStackIndicatorView: some View {
        if navigationDepth > 0 {
            HStack(spacing: 2) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 7, weight: .bold))
                Text("\(navigationDepth)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minHeight: 14)
            .background(themePalette.actionTintColor, in: Capsule())
            .accessibilityLabel("\(navigationDepth) affichage de messages empilé")
        }
    }

    private var toolbarTitleText: String {
        topicDisplayTitle.isEmpty ? (topic._aTitle ?? "Messages") : topicDisplayTitle
    }

    private var toolbarTitleView: some View {
        HStack(spacing: 4) {
            toolbarStackIndicatorView
            Text(toolbarTitleText)
                .font(.caption2)
                .fontWeight(.bold)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var toolbarSubtitleView: some View {
        HStack(spacing: 4) {
            Text(toolbarSubtitleText)
        }
        .font(.caption2)
        .foregroundStyle(.primary.opacity(0.72))
        .lineLimit(1)
    }

    private var currentMaxPage: Int {
        max(max(availableMaxPage, page), 1)
    }

    private var effectiveResetMessagesStackToRootAction: () -> Void {
        resetMessagesStackToRootAction ?? resetMessagesStackToRoot
    }

    private func resetMessagesStackToRoot() {
        navigateToLinkedTopic = false
        navigateToSearchResult = false
        linkedTopicDestination = nil
        searchResultDestination = nil
    }

    private func synchronizeTopicPagination(currentPage resolvedPage: Int, maxPage resolvedMaxPage: Int) {
        let previousCurPage = topic.curTopicPage
        let previousMaxPage = topic.maxTopicPage
        let baseURL = topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfFirstPage ?? ""
        print("[TopicPageTrace][MessagesView.syncPagination.before] resolvedPage=\(resolvedPage) resolvedMax=\(resolvedMaxPage) previousTopicCur=\(previousCurPage) previousTopicMax=\(previousMaxPage) baseURL=\(baseURL) statePage=\(page) stateMax=\(currentMaxPage)")
        topic.curTopicPage = Int32(resolvedPage)
        topic.maxTopicPage = Int32(resolvedMaxPage)

        guard !baseURL.isEmpty else {
            print("[TopicPageTrace][MessagesView.syncPagination.after] skippedEmptyBaseURL topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage)")
            return
        }

        let currentPageURL = TopicPageURLRouting.replacingPage(in: baseURL, page: resolvedPage)
        let lastPageURL = TopicPageURLRouting.replacingPage(in: baseURL, page: resolvedMaxPage)

        topic.aURL = currentPageURL
        topic.aURLOfLastPage = lastPageURL
        if topic.aURLOfFirstPage == nil || topic.aURLOfFirstPage.isEmpty {
            topic.aURLOfFirstPage = TopicPageURLRouting.replacingPage(in: baseURL, page: 1)
        }
        print("[TopicPageTrace][MessagesView.syncPagination.after] topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage) topicURL=\(topic.aURL ?? "nil") firstPageURL=\(topic.aURLOfFirstPage ?? "nil") lastPageURL=\(topic.aURLOfLastPage ?? "nil")")
    }

    private func applyLoadedPagination(from content: TopicPageContent, requestedPage: Int) {
        lastSearchFormSnapshot = content.searchInputData
        if isFilteredSearchMode {
            print("[TopicPageTrace][MessagesView.applyLoadedPagination] skippedFilteredSearch requestedPage=\(requestedPage) contentCurrent=\(String(describing: content.currentPage)) contentMax=\(String(describing: content.maxPage)) statePage=\(page) stateMax=\(currentMaxPage)")
            return
        }
        let resolvedPage = max(content.currentPage ?? requestedPage, 1)
        let parsedMaxPage = content.maxPage ?? currentMaxPage
        let resolvedMaxPage = max(max(parsedMaxPage, resolvedPage), 1)
        print("[TopicPageTrace][MessagesView.applyLoadedPagination] requestedPage=\(requestedPage) contentCurrent=\(String(describing: content.currentPage)) contentMax=\(String(describing: content.maxPage)) resolvedPage=\(resolvedPage) parsedMax=\(parsedMaxPage) resolvedMax=\(resolvedMaxPage) statePageBefore=\(page) stateMaxBefore=\(currentMaxPage)")

        if page != resolvedPage {
            page = resolvedPage
        }
        if availableMaxPage != resolvedMaxPage {
            availableMaxPage = resolvedMaxPage
        }
        synchronizeTopicPagination(currentPage: resolvedPage, maxPage: resolvedMaxPage)
    }

    private func updateMPStorageFlagIfNeeded(content: TopicPageContent, loadedPage: Int) {
        guard UserDefaults.standard.bool(forKey: "mpstorage_active") else { return }
        guard !isInSearchMode, !isFavoritePostFilterMode else { return }
        guard content.searchInputData["cat"] == "prive" else { return }
        guard topic.aAuthorOrInter?.localizedCaseInsensitiveContains("multiples") == true else { return }
        guard let topicID = intValue(from: content.searchInputData["post"]) else { return }
        guard let lastPostAnchor = lastMessageAnchor(from: content.messageActionsByIndex) else { return }

        let pageToSave = max(content.currentPage ?? loadedPage, 1)
        let currentStoredPage = ObjCMPStorageBridge.shared.mpFlagPage(topicID: topicID) ?? -1
        guard pageToSave >= currentStoredPage else { return }

        let pValue = nonEmptyString(content.searchInputData["p"]) ?? "1"
        let uri = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=\(topicID)&page=\(pageToSave)&p=\(pValue)&sondage=0&owntopic=0&trash=0&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#\(lastPostAnchor)"

        ObjCMPStorageBridge.shared.updateMPFlag(
            topicID: topicID,
            page: pageToSave,
            p: pValue,
            href: lastPostAnchor,
            uri: uri
        )
    }

    private func lastMessageAnchor(from actionsByIndex: [Int: TopicPageMessageActions]) -> String? {
        actionsByIndex
            .sorted { $0.key < $1.key }
            .compactMap { normalizedMessageAnchor($0.value.postID) }
            .last
    }

    private func normalizedMessageAnchor(_ value: String?) -> String? {
        guard let trimmed = nonEmptyString(value) else { return nil }
        let hashless = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if hashless.lowercased().hasPrefix("t") {
            return hashless
        }
        if hashless.allSatisfy(\.isNumber) {
            return "t\(hashless)"
        }
        return hashless
    }

    private func anchorNumericValue(_ anchor: String?) -> Int? {
        guard let anchor = normalizedMessageAnchor(anchor) else { return nil }
        let digits = anchor.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
        return Int(digits)
    }

    private func isNewerLastAnchor(_ newAnchor: String?, than oldAnchor: String?) -> Bool {
        guard let oldAnchor = normalizedMessageAnchor(oldAnchor),
              let newAnchor = normalizedMessageAnchor(newAnchor) else {
            return false
        }
        if let oldValue = anchorNumericValue(oldAnchor),
           let newValue = anchorNumericValue(newAnchor) {
            return newValue > oldValue
        }
        return newAnchor != oldAnchor
    }

    private var visibleMessageAnchor: String? {
        normalizedMessageAnchor(lastWebViewScrollPosition?.visibleAnchor)
    }

    private var isNearBottomForPostReload: Bool {
        guard let position = lastWebViewScrollPosition else {
            return isWebContentAtBottom
        }
        return isWebContentAtBottom || position.distanceToBottom <= max(position.viewportHeight, 1)
    }

    private func intValue(from value: String?) -> Int? {
        guard let trimmed = nonEmptyString(value), let intValue = Int(trimmed), intValue > 0 else {
            return nil
        }
        return intValue
    }

    private func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func beginTopicLoad(initialScroll overrideInitialScroll: WebView.InitialScroll? = nil) -> UUID {
        let token = UUID()

        topicLoadTimeoutWorkItem?.cancel()
        activeTopicLoadToken = token
        topicPageLoader.cancelTopicPageFetch()

        if let overrideInitialScroll {
            initialScroll = overrideInitialScroll
        }

        showWebViewLoadCover = true
        isWebContentAtBottom = false
        errorMessage = nil
        messageActionsByIndex = [:]

        let timeoutWorkItem = DispatchWorkItem {
            guard self.completeTopicLoad(token) else { return }
            self.topicPageLoader.cancelTopicPageFetch()
            self.errorMessage = "Le chargement du topic a expiré. Réessaie."
            self.showWebViewLoadCover = false
        }
        topicLoadTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 65, execute: timeoutWorkItem)

        return token
    }

    private func completeTopicLoad(_ token: UUID) -> Bool {
        guard activeTopicLoadToken == token else { return false }
        activeTopicLoadToken = nil
        topicLoadTimeoutWorkItem?.cancel()
        topicLoadTimeoutWorkItem = nil
        return true
    }

    private func isBottomInitialScroll(_ initialScroll: WebView.InitialScroll?) -> Bool {
        if case .bottom? = initialScroll {
            return true
        }
        return false
    }

    private func resolvedRestoration(
        _ restoration: TopicPageLoadRestoration?,
        content: TopicPageContent,
        fetchAnchor: String?,
        requestedInitialScroll: WebView.InitialScroll?
    ) -> (anchor: String?, initialScroll: WebView.InitialScroll?) {
        guard let restoration else {
            return (normalizedMessageAnchor(fetchAnchor), requestedInitialScroll)
        }

        let newLastAnchor = lastMessageAnchor(from: content.messageActionsByIndex)
        let hasNewerPost = isNewerLastAnchor(newLastAnchor, than: restoration.previousLastAnchor)
        if restoration.scrollToBottomWhenNoNewerPost && !hasNewerPost {
            return (nil, .bottom)
        }

        if let scrollAnchor = normalizedMessageAnchor(restoration.scrollAnchor) {
            return (scrollAnchor, nil)
        }

        return (nil, restoration.fallbackInitialScroll)
    }

    private func maybeProbeNextPageAfterRefresh(
        previousPage: Int,
        previousMaxPage: Int,
        loadedPage: Int,
        loadedMaxPage: Int,
        initialScroll: WebView.InitialScroll?
    ) {
        if isFilteredSearchMode { return }
        let policy = TopicPageRefreshProbePolicy(
            previousPage: previousPage,
            previousMaxPage: previousMaxPage,
            loadedPage: loadedPage,
            loadedMaxPage: loadedMaxPage,
            initialScrollToBottom: isBottomInitialScroll(initialScroll)
        )
        guard let probePage = policy.nextPageToProbe else { return }

        let expectedDisplayedPage = page
        let probeURL = urlForPage(probePage)
        topicPageLoader.fetchTopicPage(url: probeURL, anchor: nil) { result in
            DispatchQueue.main.async {
                guard self.activeTopicLoadToken == nil else { return }
                guard self.page == expectedDisplayedPage else { return }

                switch result {
                case .failure:
                    break
                case .success(let content):
                    let mergedMaxPage = TopicPageRefreshProbePolicy.mergedMaxPage(
                        currentMaxPage: self.currentMaxPage,
                        probeCurrentPage: content.currentPage,
                        probeMaxPage: content.maxPage
                    )
                    guard mergedMaxPage > self.currentMaxPage else { return }
                    self.availableMaxPage = mergedMaxPage
                    self.synchronizeTopicPagination(currentPage: self.page, maxPage: mergedMaxPage)
                }
            }
        }
    }

    private func loadPage(_ page: Int, restoration: TopicPageLoadRestoration? = nil) {
        let url = urlForPage(page)
        let fetchAnchor = restoration?.fetchAnchor ?? self.anchor
        print("[TopicPageTrace][MessagesView.loadPage.start] requestedPage=\(page) url=\(url) anchor=\(String(describing: fetchAnchor)) statePage=\(self.page) stateMax=\(currentMaxPage) topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage)")
        let previousPage = self.page
        let previousMaxPage = currentMaxPage
        let requestedInitialScroll = restoration?.fallbackInitialScroll ?? initialScroll
        let loadToken = beginTopicLoad(initialScroll: requestedInitialScroll)
        topicPageLoader.fetchTopicPage(url: url, anchor: fetchAnchor) { result in
            DispatchQueue.main.async {
                guard self.completeTopicLoad(loadToken) else { return }

                switch result {
                case .failure(let error):
                    self.finishRefreshHapticIfNeeded()
                    if self.isInSearchMode {
                        self.showWebViewLoadCover = false
                        self.lastSearchFormSnapshot = [:]
                        self.showSuccessToast("Aucune réponse trouvée")
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.showWebViewLoadCover = false
                case .success(let content):
                    if self.isInSearchMode, self.isEmptySearchResultContent(content) {
                        self.finishRefreshHapticIfNeeded()
                        self.showWebViewLoadCover = false
                        self.lastSearchFormSnapshot = [:]
                        self.showSuccessToast("Aucune réponse trouvée")
                        return
                    }
                    let requestedPage = page
                    let resolvedPage = max(content.currentPage ?? requestedPage, 1)
                    let parsedMaxPage = content.maxPage ?? previousMaxPage
                    let resolvedMaxPage = max(max(parsedMaxPage, resolvedPage), 1)
                    print("[TopicPageTrace][MessagesView.loadPage.success] requestedPage=\(requestedPage) contentCurrent=\(String(describing: content.currentPage)) contentMax=\(String(describing: content.maxPage)) resolvedPage=\(resolvedPage) parsedMax=\(parsedMaxPage) resolvedMax=\(resolvedMaxPage) previousPage=\(previousPage) previousMax=\(previousMaxPage) url=\(url)")
                    let resolvedRestoration = self.resolvedRestoration(
                        restoration,
                        content: content,
                        fetchAnchor: fetchAnchor,
                        requestedInitialScroll: requestedInitialScroll
                    )
                    self.anchor = resolvedRestoration.anchor
                    self.initialScroll = resolvedRestoration.initialScroll
                    do {
                        let rendered = try topicPageRenderer.render(html: content.html)
                        self.fileURL = rendered.fileURL
                        self.cacheURL = rendered.readAccessURL
                        if self.fileURL == nil || self.cacheURL == nil {
                            self.errorMessage = "Failed to render topic page to local file."
                            self.showWebViewLoadCover = false
                        }
                    } catch {
                        self.fileURL = nil
                        self.cacheURL = nil
                        self.errorMessage = error.localizedDescription
                        self.showWebViewLoadCover = false
                    }
                    applyLoadedPagination(from: content, requestedPage: page)
                    updateMPStorageFlagIfNeeded(content: content, loadedPage: resolvedPage)
                    self.topicAnswerURL = content.topicAnswerURL
                    self.messageActionsByIndex = content.messageActionsByIndex
                    self.hasPoll = content.hasPoll
                    self.pollIsNewVote = content.pollIsNewVote
                    self.pollData = content.pollData
                    if let newTitle = content.topicTitle, !newTitle.isEmpty {
                        self.topicDisplayTitle = newTitle
                    }
                    self.finishRefreshHapticIfNeeded()
                    maybeProbeNextPageAfterRefresh(
                        previousPage: previousPage,
                        previousMaxPage: previousMaxPage,
                        loadedPage: resolvedPage,
                        loadedMaxPage: resolvedMaxPage,
                        initialScroll: requestedInitialScroll
                    )
                }
            }
        }
    }

    private func loadDirectURL(_ topicURL: String, initialScroll: WebView.InitialScroll? = nil) {
        guard !topicURL.isEmpty else { return }
        let topicURLToLoad: String
        if let url = URL(string: topicURL),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            topicURLToLoad = normalizedForumTopicURLString(from: url)
        } else {
            topicURLToLoad = topicURL
        }

        self.anchor = URL(string: topicURLToLoad)?.fragment ?? URL(string: topicURL)?.fragment
        let previousPage = page
        let previousMaxPage = currentMaxPage
        print("[TopicPageTrace][MessagesView.loadDirectURL.start] topicURL=\(topicURLToLoad) anchor=\(String(describing: self.anchor)) statePage=\(page) stateMax=\(currentMaxPage) topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage) initialScroll=\(String(describing: initialScroll))")
        let loadToken = beginTopicLoad(initialScroll: initialScroll)

        topicPageLoader.fetchTopicPage(url: topicURLToLoad, anchor: self.anchor) { result in
            DispatchQueue.main.async {
                guard self.completeTopicLoad(loadToken) else { return }

                switch result {
                case .failure(let error):
                    if self.isInSearchMode {
                        self.showWebViewLoadCover = false
                        self.lastSearchFormSnapshot = [:]
                        self.showSuccessToast("Aucune réponse trouvée")
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.showWebViewLoadCover = false
                case .success(let content):
                    if self.isInSearchMode, self.isEmptySearchResultContent(content) {
                        self.showWebViewLoadCover = false
                        self.lastSearchFormSnapshot = [:]
                        self.showSuccessToast("Aucune réponse trouvée")
                        return
                    }
                    let requestedPage = content.currentPage
                        ?? TopicPageURLRouting.pageNumber(from: topicURLToLoad)
                        ?? self.page
                    let resolvedPage = max(content.currentPage ?? requestedPage, 1)
                    let parsedMaxPage = content.maxPage ?? previousMaxPage
                    let resolvedMaxPage = max(max(parsedMaxPage, resolvedPage), 1)
                    print("[TopicPageTrace][MessagesView.loadDirectURL.success] topicURL=\(topicURLToLoad) requestedPage=\(requestedPage) contentCurrent=\(String(describing: content.currentPage)) contentMax=\(String(describing: content.maxPage)) resolvedPage=\(resolvedPage) parsedMax=\(parsedMaxPage) resolvedMax=\(resolvedMaxPage) previousPage=\(previousPage) previousMax=\(previousMaxPage)")
                    let renderHTML: String = {
                        if self.isInSearchMode, !self.isFilteredSearchMode, let anchor = self.anchor {
                            return self.rewriteSeparatorBeforeAnchor(in: content.html, anchor: anchor)
                        }
                        return content.html
                    }()
                    do {
                        let rendered = try topicPageRenderer.render(html: renderHTML)
                        self.fileURL = rendered.fileURL
                        self.cacheURL = rendered.readAccessURL
                    } catch {
                        self.fileURL = nil
                        self.cacheURL = nil
                        self.errorMessage = error.localizedDescription
                        self.showWebViewLoadCover = false
                    }
                    applyLoadedPagination(from: content, requestedPage: requestedPage)
                    updateMPStorageFlagIfNeeded(content: content, loadedPage: resolvedPage)
                    self.topicAnswerURL = content.topicAnswerURL
                    self.messageActionsByIndex = content.messageActionsByIndex
                    self.hasPoll = content.hasPoll
                    self.pollIsNewVote = content.pollIsNewVote
                    self.pollData = content.pollData
                    if let newTitle = content.topicTitle, !newTitle.isEmpty {
                        self.topicDisplayTitle = newTitle
                    }
                    maybeProbeNextPageAfterRefresh(
                        previousPage: previousPage,
                        previousMaxPage: previousMaxPage,
                        loadedPage: resolvedPage,
                        loadedMaxPage: resolvedMaxPage,
                        initialScroll: initialScroll
                    )
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

        let pageFromURL =
            TopicPageURLRouting.pageNumber(from: topicURLString)
            ?? TopicPageURLRouting.pageNumber(from: url.absoluteString)
            ?? 1
        let boundedPage = max(pageFromURL, 1)
        let provisionalMaxPage = boundedPage
        print("[TopicPageTrace][MessagesView.openInternalTopic] sourceURL=\(url.absoluteString) normalizedURL=\(topicURLString) pageFromURL=\(pageFromURL) boundedPage=\(boundedPage) provisionalMax=\(provisionalMaxPage) currentStatePage=\(page) currentStateMax=\(currentMaxPage)")

        let topicForNavigation = Topic()
        topicForNavigation._aTitle = topic._aTitle
        topicForNavigation.aURL = topicURLString
        topicForNavigation.aURLOfLastPage = topicURLString
        topicForNavigation.curTopicPage = Int32(boundedPage)
        topicForNavigation.maxTopicPage = Int32(provisionalMaxPage)

        linkedTopicDestination = AnyView(
            MessagesView(
                topic: topicForNavigation,
                curPage: boundedPage,
                maxPage: max(provisionalMaxPage, 1),
                separatorNewMessages: true,
                navigationDepth: navigationDepth + 1,
                resetMessagesStackToRootAction: effectiveResetMessagesStackToRootAction
            )
            .toolbar(.hidden, for: .tabBar)
        )
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
            refreshCurrentPagePreservingScroll()
        case .showPopupMenu:
            break
        case .manageSmileyFavorite(let payload):
            let isFavorite = ReplySmileyCacheBridge.isFavoriteFromApp(code: payload.code)
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
        ReplySmileyCacheBridge.updateAppFavorite(code: code, imageURL: imageURL, add: add)
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

    private var isSearchErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { searchErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    searchErrorMessage = nil
                }
            }
        )
    }

    private var isFavoritePostFilterErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { favoritePostFilterErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    favoritePostFilterErrorMessage = nil
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

    private func openTextQuoteComposer(with url: URL, selectedText: String, boldSelection: Bool) {
        guard !isLoadingQuoteTemplate else { return }

        Task { @MainActor in
            isLoadingQuoteTemplate = true
            activeComposerPrefillMode = .quote
            defer { isLoadingQuoteTemplate = false }

            do {
                let template = try await replyQuoteTemplateLoader.fetchQuoteTemplate(from: url)
                let quoteTemplate = ReplyQuoteSelectionFormatter.format(
                    quoteTemplate: template,
                    selectedText: selectedText,
                    boldSelection: boldSelection
                )
                let mergedDraft = ReplyQuoteDraftMerger.merge(
                    quoteTemplate: quoteTemplate,
                    into: composerDraftText
                )
                composerDraftText = mergedDraft
                composerInitialMessage = mergedDraft
                activeComposerPresentationKind = .reply
                composerNavigationTitle = ComposerPresentationKind.reply.title
                composerRequiresSubject = false
                composerRecipientName = nil
                composerPersistsDraft = true
                composerSubmitURL = topicAnswerURL ?? url
                lastFailedQuoteTemplateURL = nil
                quoteTemplateErrorMessage = nil
                isComposerPresented = true
            } catch {
                lastFailedQuoteTemplateURL = url
                lastFailedComposerPrefillMode = .quote
                quoteTemplateErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
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
        composerInitialMessage = ""
        composerPersistsDraft = false
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
                    let mergedDraft = ReplyQuoteDraftMerger.merge(
                        quoteTemplate: template,
                        into: composerDraftText
                    )
                    composerDraftText = mergedDraft
                    composerInitialMessage = mergedDraft
                    composerPersistsDraft = true
                    composerSubmitURL = topicAnswerURL ?? url
                case .edit:
                    composerInitialMessage = template
                    composerPersistsDraft = false
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

    private func openProfile(for url: URL, avatarActions: TopicPageMessageActions? = nil) {
        userProfileDestination = UserProfileDestination(url: url, avatarActions: avatarActions)
    }

    private func userProfileQuickActions(for actions: TopicPageMessageActions?) -> UserProfileQuickActions? {
        guard let actions else { return nil }
        let authorName = actions.authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableAuthorName = authorName?.isEmpty == false ? authorName : nil
        let privateMessageURL = actions.isOwnMessage ? nil : actions.privateMessageURL
        let canToggleLists = !actions.isOwnMessage && usableAuthorName != nil

        guard privateMessageURL != nil || canToggleLists else {
            return nil
        }

        return UserProfileQuickActions(
            privateMessageURL: privateMessageURL,
            authorName: usableAuthorName,
            isBlacklisted: usableAuthorName.map { ObjCProfileFilterListManager.shared.isBlacklisted($0) } ?? false,
            isWhitelisted: usableAuthorName.map { ObjCProfileFilterListManager.shared.isWhitelisted($0) } ?? false,
            onPrivateMessage: { privateMessageURL in
                openProfilePrivateMessage(privateMessageURL, actions: actions)
            },
            onBlacklist: { pseudo in
                toggleProfileBlacklist(for: pseudo)
            },
            onWhitelist: { pseudo in
                toggleProfileWhitelist(for: pseudo)
            }
        )
    }

    private func presentAvatarActionSheet(with actions: TopicPageMessageActions) {
        if let profileURL = actions.profileURL {
            openProfile(for: profileURL, avatarActions: actions)
            return
        }
        avatarActionSheetState = AvatarActionSheetState(actions: actions)
    }

    private func dismissUserProfile(then action: @escaping @MainActor () -> Void) {
        userProfileDestination = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            action()
        }
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

    private func openProfilePrivateMessage(_ url: URL, actions: TopicPageMessageActions) {
        dismissUserProfile {
            openPrivateMessageComposer(with: url, actions: actions)
        }
    }

    private func toggleAvatarBlacklist(for pseudo: String) {
        dismissAvatarActionSheet {
            let message = ObjCProfileFilterListManager.shared.toggleBlacklist(pseudo: pseudo)
            if let message {
                showSuccessToast(message)
            } else {
                popupActionErrorMessage = "Blacklist impossible"
            }
            loadPage(page)
        }
    }

    private func toggleProfileBlacklist(for pseudo: String) {
        dismissUserProfile {
            let message = ObjCProfileFilterListManager.shared.toggleBlacklist(pseudo: pseudo)
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
            let message = ObjCProfileFilterListManager.shared.toggleWhitelist(pseudo: pseudo)
            if let message {
                showSuccessToast(message)
            } else {
                popupActionErrorMessage = "Whitelist impossible"
            }
            loadPage(page)
        }
    }

    private func toggleProfileWhitelist(for pseudo: String) {
        dismissUserProfile {
            let message = ObjCProfileFilterListManager.shared.toggleWhitelist(pseudo: pseudo)
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
        composerInitialMessage = composerDraftText
        composerPersistsDraft = true
        composerSubmitURL = topicAnswerURL
        isComposerPresented = true
    }

    private func openTopicSearchSheet() {
        let initialParams: TopicSearchParams
        let isFromResultsPage: Bool

        if let searchContext {
            if !lastSearchFormSnapshot.isEmpty {
                var parsed = TopicSearchParams.fromLegacyDictionary(lastSearchFormSnapshot)
                parsed.word = searchContext.params.word
                parsed.spseudo = searchContext.params.spseudo
                parsed.filterEnabled = searchContext.params.filterEnabled
                initialParams = parsed
            } else {
                initialParams = searchContext.params
            }
            isFromResultsPage = true
        } else if !lastSearchFormSnapshot.isEmpty {
            var parsed = TopicSearchParams.fromLegacyDictionary(lastSearchFormSnapshot)
            parsed.word = ""
            parsed.spseudo = ""
            parsed.filterEnabled = false
            parsed.fromFirstPost = true
            initialParams = parsed
            isFromResultsPage = false
        } else {
            initialParams = .empty
            isFromResultsPage = false
        }

        topicSearchSheetState = TopicSearchSheetState(
            initialParams: initialParams,
            isFromResultsPage: isFromResultsPage
        )
    }

    private func handleSearchResult(url: URL, params: TopicSearchParams) {
        let newContext = TopicSearchContext(params: params, resultURL: url)
        if isInSearchMode {
            // Already viewing search results — replace in place.
            searchContext = newContext
            hasConsumedInitialSearchURL = true
            loadSearchResultURL(url)
        } else {
            // Normal topic → push a new MessagesView in search mode.
            searchResultDestination = AnyView(
                MessagesView(
                    topic: topic,
                    curPage: page,
                    maxPage: currentMaxPage,
                    separatorNewMessages: false,
                    navigationDepth: navigationDepth + 1,
                    topicPageLoader: topicPageLoader,
                    topicPageRenderer: topicPageRenderer,
                    replyQuoteTemplateLoader: replyQuoteTemplateLoader,
                    messageDeletionService: messageDeletionService,
                    moderationAlertService: moderationAlertService,
                    topicSearchService: topicSearchService,
                    initialSearchContext: newContext,
                    resetMessagesStackToRootAction: effectiveResetMessagesStackToRootAction
                )
                .toolbar(.hidden, for: .tabBar)
            )
            navigateToSearchResult = true
        }
    }

    private func advanceToNextSearchResults() {
        guard let searchContext, !lastSearchFormSnapshot.isEmpty else { return }
        guard !isAdvancingSearchResults else { return }
        var params = TopicSearchParams.fromLegacyDictionary(lastSearchFormSnapshot)
        params.word = searchContext.params.word
        params.spseudo = searchContext.params.spseudo
        params.filterEnabled = searchContext.params.filterEnabled
        params.fromFirstPost = false

        isAdvancingSearchResults = true
        searchErrorMessage = nil

        Task { @MainActor in
            let result = await topicSearchService.performSearch(params: params)
            isAdvancingSearchResults = false
            switch result {
            case .success(let url):
                self.searchContext = TopicSearchContext(params: params, resultURL: url)
                self.hasConsumedInitialSearchURL = true
                loadSearchResultURL(url)
            case .failure(let error):
                if isNoMoreResultsError(error) {
                    self.lastSearchFormSnapshot = [:]
                    self.showSuccessToast("Aucune réponse trouvée")
                } else {
                    searchErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func renderFavoritePostFilterResult(_ result: FavoritePostFilterResult) {
        do {
            showWebViewLoadCover = true
            let rendered = try topicPageRenderer.render(html: result.html)
            fileURL = rendered.fileURL
            cacheURL = rendered.readAccessURL
            messageActionsByIndex = result.messageActionsByIndex
            page = max(result.endPage, 1)
            availableMaxPage = max(result.maxPage, page)
            topicAnswerURL = nil
            hasPoll = false
            pollIsNewVote = false
            pollData = nil
            favoritePostFilterResult = result
            initialScroll = .top
            anchor = nil
        } catch {
            fileURL = nil
            cacheURL = nil
            errorMessage = error.localizedDescription
            showWebViewLoadCover = false
        }
    }

    private func advanceToNextFavoritePostFilterResults() {
        guard let currentResult = favoritePostFilterResult, !currentResult.isFinished else { return }
        guard !isAdvancingFavoritePostFilterResults else { return }

        isAdvancingFavoritePostFilterResults = true
        favoritePostFilterErrorMessage = nil

        Task { @MainActor in
            let result = await favoritePostFilterService.filterPosts(
                topic: topic,
                startPage: currentResult.endPage + 1
            ) { _ in }

            isAdvancingFavoritePostFilterResults = false
            switch result {
            case .success(let nextResult):
                renderFavoritePostFilterResult(nextResult)
            case .failure(.noResult):
                favoritePostFilterResult = currentResult.markingFinished()
                showSuccessToast("Aucun autre post trouvé")
            case .failure(let error):
                favoritePostFilterErrorMessage = error.localizedDescription
            }
        }
    }

    /// Load a URL returned by /transsearch.php, honoring a possible `#tXXXX`
    /// fragment so the web view scrolls to the matched message (as if opening
    /// a favorite). When there is no fragment we explicitly scroll to top to
    /// avoid inheriting a stale `initialScroll`.
    private func loadSearchResultURL(_ url: URL) {
        if let fragment = url.fragment, !fragment.isEmpty {
            self.anchor = fragment
            self.initialScroll = nil
            loadDirectURL(url.absoluteString)
        } else {
            self.anchor = nil
            loadDirectURL(url.absoluteString, initialScroll: .top)
        }
    }

    /// onAppear entry point. In non-filtered search mode the forum returns a
    /// classic topic URL with a `#tXXXX` fragment — we must follow that URL
    /// directly so the anchor scroll lands on the matched message.
    private func performInitialLoad() {
        if let initialFavoritePostFilterResult, !hasConsumedInitialFavoritePostFilterResult {
            hasConsumedInitialFavoritePostFilterResult = true
            renderFavoritePostFilterResult(initialFavoritePostFilterResult)
            return
        }
        if let searchContext, !hasConsumedInitialSearchURL, !isFilteredSearchMode {
            hasConsumedInitialSearchURL = true
            loadSearchResultURL(searchContext.resultURL)
            return
        }
        loadPage(page)
    }

    /// Identifies the forum's "no match" response (the `<div class="hop">Désolé
    /// aucune réponse…` page). We rely on a structural signal: the legacy
    /// controller never parses any message rows from that response, so
    /// `messageActionsByIndex` is empty. An HTML-text check is kept as a
    /// belt-and-suspenders fallback for defensive cases.
    /// The ObjC search controller signals a dry query by either returning
    /// `.noResultURL` from the Swift service, or wrapping an `NSError` whose
    /// domain is `MessagesTableViewController.search` with code -11 (no
    /// Location header). Both must trigger the same "no more results" toast
    /// instead of the modal error alert used for real failures.
    private func isNoMoreResultsError(_ error: TopicSearchError) -> Bool {
        switch error {
        case .noResultURL:
            return true
        case .underlying(let underlying):
            let nsError = underlying as NSError
            return nsError.domain == "MessagesTableViewController.search" && nsError.code == -11
        default:
            return false
        }
    }

    private func isEmptySearchResultContent(_ content: TopicPageContent) -> Bool {
        if content.messageActionsByIndex.isEmpty {
            return true
        }
        let lower = content.html.lowercased()
        return lower.contains("aucune réponse")
            || lower.contains("aucune r&eacute;ponse")
            || lower.contains("aucune reponse")
    }

    /// For non-filtered search results the forum returns a classic topic page
    /// with a `#tXXXX` fragment, and the legacy controller inserts
    /// `<div class="separator1"></div>` *after* the matched post (favorite-like
    /// semantics). In the search-result context it makes more sense to mark the
    /// boundary *before* the match, so we swap the separator's position.
    private func rewriteSeparatorBeforeAnchor(in html: String, anchor: String) -> String {
        let separator = "<div class=\"separator1\"></div>"
        guard let separatorRange = html.range(of: separator) else { return html }
        let anchorAttribute = "name=\"\(anchor)\""
        guard let anchorRange = html.range(of: anchorAttribute) else { return html }
        let upToAnchor = html[..<anchorRange.lowerBound]
        guard let messageOpen = upToAnchor.range(of: "<div class=\"message", options: .backwards) else {
            return html
        }
        let messageStart = messageOpen.lowerBound
        guard separatorRange.lowerBound > messageStart else { return html }

        let messageBlock = html[messageStart..<separatorRange.lowerBound]
        var result = html
        result.replaceSubrange(messageStart..<separatorRange.upperBound, with: separator + messageBlock)
        return result
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

    private func requestWebViewScroll(_ position: WebView.InitialScroll) {
        webViewScrollRequest = WebView.ScrollRequest(id: UUID(), position: position)
    }

    private func navigateToPage(_ target: Int, initialScroll: WebView.InitialScroll, source: String = "unspecified") {
        print("[TopicPageTrace][MessagesView.navigateToPage.requested] source=\(source) current=\(page) target=\(target) max=\(currentMaxPage) initialScroll=\(String(describing: initialScroll)) topicCur=\(topic.curTopicPage) topicMax=\(topic.maxTopicPage)")
        guard (1...currentMaxPage).contains(target) else {
            print("[TopicPageTrace][MessagesView.navigateToPage.ignored] source=\(source) current=\(page) target=\(target) max=\(currentMaxPage)")
            return
        }
        if target == page {
            requestWebViewScroll(initialScroll)
            return
        }
        anchor = nil
        self.initialScroll = initialScroll
        loadPage(target)
    }

    private func navigateToPreviousPageFromBottomButton() {
        let target = page - 1
        print("[MessagesView] bottom previous tap current=\(page) target=\(target) max=\(currentMaxPage) atBottom=\(isWebContentAtBottom) showCover=\(showWebViewLoadCover)")
        navigateToPage(target, initialScroll: .bottom, source: "bottom previous button")
    }

    private func navigateToNextPageFromBottomButton() {
        let target = page + 1
        print("[MessagesView] bottom next tap current=\(page) target=\(target) max=\(currentMaxPage) atBottom=\(isWebContentAtBottom) showCover=\(showWebViewLoadCover)")
        navigateToPage(target, initialScroll: .top, source: "bottom next button")
    }

    private var shouldShowBottomRefreshButton: Bool {
        page >= currentMaxPage && isWebContentAtBottom
    }

    private var bottomPreviousPageButton: some View {
        Button {
            navigateToPreviousPageFromBottomButton()
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 14, weight: .semibold))
        }
        .disabled(page <= 1)
        .legacyPageButtonSpacing(edge: .trailing)
        .bottomBarStableHitTarget()
    }

    private var bottomNextPageButton: some View {
        Button {
            navigateToNextPageFromBottomButton()
        } label: {
            Image(systemName: "chevron.forward")
                .font(.system(size: 14, weight: .semibold))
        }
        .disabled(page >= currentMaxPage)
        .legacyPageButtonSpacing(edge: .leading)
        .bottomBarStableHitTarget()
    }

    private var pageChoiceMenuFinalTargets: [Int] {
        guard currentMaxPage > 1 else { return [] }
        var seen = Set([1])
        return [currentMaxPage - 2, currentMaxPage - 1, currentMaxPage].compactMap { target in
            guard (2...currentMaxPage).contains(target), seen.insert(target).inserted else { return nil }
            return target
        }
    }

    @ViewBuilder
    private func pageChoiceMenuItems() -> some View {
        if currentMaxPage > 1 {
            Button("Page 1") {
                navigateToPage(1, initialScroll: .top, source: "top page menu first")
            }

            Button("Page ...") {
                openPagePicker()
            }

            ForEach(pageChoiceMenuFinalTargets, id: \.self) { target in
                Button("Page \(target)") {
                    navigateToPage(target, initialScroll: .top, source: "top page menu final")
                }
            }

            Button("Dernier post") {
                navigateToPage(currentMaxPage, initialScroll: .bottom, source: "top page menu last post")
            }
        }
    }

    private func refreshCurrentPagePreservingScroll() {
        AppHaptics.refreshStarted()
        shouldTriggerRefreshCompletionHaptic = true
        let restoration = refreshCurrentPageRestoration()
        anchor = nil
        initialScroll = restoration.fallbackInitialScroll
        loadPage(page, restoration: restoration)
    }

    private func currentScrollRestoration() -> WebView.InitialScroll? {
        if let lastWebViewScrollPosition {
            return .position(lastWebViewScrollPosition)
        }
        return isWebContentAtBottom ? .bottom : nil
    }

    private func refreshCurrentPageRestoration() -> TopicPageLoadRestoration {
        let previousLastAnchor = lastMessageAnchor(from: messageActionsByIndex)
        let fallbackInitialScroll = currentScrollRestoration()

        guard !isInSearchMode, !isFavoritePostFilterMode else {
            return TopicPageLoadRestoration(
                fetchAnchor: nil,
                scrollAnchor: nil,
                fallbackInitialScroll: fallbackInitialScroll,
                previousLastAnchor: nil,
                scrollToBottomWhenNoNewerPost: false
            )
        }

        if page >= currentMaxPage,
           isWebContentAtBottom,
           let previousLastAnchor {
            return TopicPageLoadRestoration(
                fetchAnchor: previousLastAnchor,
                scrollAnchor: previousLastAnchor,
                fallbackInitialScroll: .bottom,
                previousLastAnchor: previousLastAnchor,
                scrollToBottomWhenNoNewerPost: true
            )
        }

        return TopicPageLoadRestoration(
            fetchAnchor: nil,
            scrollAnchor: visibleMessageAnchor,
            fallbackInitialScroll: fallbackInitialScroll,
            previousLastAnchor: nil,
            scrollToBottomWhenNoNewerPost: false
        )
    }

    private func reloadAfterEditedMessage(_ result: ReplyPostingResult) {
        let refreshURLString = result.refreshURL.map { normalizedForumTopicURLString(from: $0) }
        let refreshAnchor = normalizedMessageAnchor(result.refreshAnchor ?? result.refreshURL?.fragment)
        let targetPage = TopicPageURLRouting.pageNumber(from: refreshURLString) ?? page
        let fallbackInitialScroll: WebView.InitialScroll? = refreshAnchor == nil ? currentScrollRestoration() : .top
        let restoration = TopicPageLoadRestoration(
            fetchAnchor: nil,
            scrollAnchor: refreshAnchor,
            fallbackInitialScroll: fallbackInitialScroll,
            previousLastAnchor: nil,
            scrollToBottomWhenNoNewerPost: false
        )

        anchor = nil
        initialScroll = fallbackInitialScroll
        loadPage(targetPage, restoration: restoration)
    }

    private func reloadAfterPostedReply() {
        guard page >= currentMaxPage else { return }

        let previousLastAnchor = lastMessageAnchor(from: messageActionsByIndex)
        let fallbackInitialScroll = currentScrollRestoration()

        if isNearBottomForPostReload, let previousLastAnchor {
            let restoration = TopicPageLoadRestoration(
                fetchAnchor: previousLastAnchor,
                scrollAnchor: previousLastAnchor,
                fallbackInitialScroll: .bottom,
                previousLastAnchor: previousLastAnchor,
                scrollToBottomWhenNoNewerPost: true
            )
            anchor = nil
            initialScroll = .bottom
            loadPage(page, restoration: restoration)
            return
        }

        let restoration = TopicPageLoadRestoration(
            fetchAnchor: previousLastAnchor,
            scrollAnchor: visibleMessageAnchor,
            fallbackInitialScroll: fallbackInitialScroll,
            previousLastAnchor: previousLastAnchor,
            scrollToBottomWhenNoNewerPost: false
        )
        anchor = nil
        initialScroll = fallbackInitialScroll
        loadPage(page, restoration: restoration)
    }

    private func finishRefreshHapticIfNeeded() {
        guard shouldTriggerRefreshCompletionHaptic else { return }
        shouldTriggerRefreshCompletionHaptic = false
        AppHaptics.refreshCompleted()
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

        switch presentationKind {
        case .edit:
            reloadAfterEditedMessage(postedReply)
        case .reply:
            reloadAfterPostedReply()
        case .privateMessage:
            break
        }
    }

    var body: some View {
        let content: AnyView

        if let errorMessage {
            content = AnyView(
                Text("Erreur : \(errorMessage)").foregroundColor(.red)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            toolbarTitleView
                            toolbarSubtitleView
                        }
                        .multilineTextAlignment(.center)
                    }
                }
                .onAppear {
                    performInitialLoad()
                }
                .sheet(item: $safariDestination) { destination in
                    SafariInAppView(url: destination.url)
                        .ignoresSafeArea()
                }
                .sheet(item: $userProfileDestination) { destination in
                    UserProfileView(
                        profileURL: destination.url,
                        quickActions: userProfileQuickActions(for: destination.avatarActions)
                    )
                        .presentationGlassBackground()
                }
                .sheet(item: $smileySheetState) { state in
                    MessageSmileySheetView(
                        code: state.payload.code,
                        imageURL: state.payload.imageURL,
                        initiallyFavorite: state.isFavorite,
                        onToggleFavorite: { add in
                            updateSmileyFavorite(code: state.payload.code, imageURL: state.payload.imageURL, add: add)
                        },
                        onFetchKeywords: { completion in
                            Task {
                                completion(await fetchSmileyKeywords(code: state.payload.code))
                            }
                        },
                        onShowToast: { message in
                            showSuccessToast(message)
                        }
                    )
                    .presentationDetents([.medium])
                }
                .fullScreenCover(item: $photoViewerDestination) { destination in
                    FullScreenPhotoViewer(url: destination.url, presentationID: destination.id)
                }
            )
        } else if fileURL != nil && cacheURL != nil {
            content = AnyView(
                ZStack {
                themePalette.webViewBackdropColor

                WebView(
                    fileURL: fileURL,
                    readAccessURL: cacheURL,
                    anchor: anchor,
                    initialScroll: initialScroll,
                    scrollRequest: webViewScrollRequest,
                    currentPage: page,
                    maxPage: currentMaxPage,
                    colorScheme: appTheme.effectiveColorScheme,
                    baseBackgroundColor: themePalette.webViewBackdropUIColor,
                    themeRevision: appTheme.themeRevision,
                    messageBodyFontSize: messageBodyFontSize,
                    messageDisplayStyleRawValue: messageDisplayStyleRawValue,
                    messageMeBaseBackgroundColor: themePalette.messageActionTintCSS(alpha: 1.0),
                    messageMeContentBackgroundColor: themePalette.messageActionTintCSS(alpha: 0.03),
                    messageMeClassicHeaderBackgroundColor: themePalette.messageActionTintCSS(alpha: 0.15),
                    messageLoveBaseBackgroundColor: themePalette.messageLoveCSS(alpha: 1.0),
                    messageLoveContentBackgroundColor: themePalette.messageLoveCSS(alpha: 0.4),
                    messageLoveModernHeaderBackgroundColor: themePalette.messageLoveCSS(alpha: 0.4),
                    messageClassicHeaderBackgroundColor: themePalette.messageClassicHeaderBackgroundCSS,
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
                    onToastRequest: { message in
                        showSuccessToast(message)
                    },
                    onTextQuoteRequest: { quoteURL, selectedText, boldSelection in
                        openTextQuoteComposer(
                            with: quoteURL,
                            selectedText: selectedText,
                            boldSelection: boldSelection
                        )
                    },
                    onContentReady: {
                        withAnimation(.easeOut(duration: 0.14)) {
                            showWebViewLoadCover = false
                        }
                    },
                    onScrollPositionChange: { isAtBottom in
                        if isWebContentAtBottom != isAtBottom {
                            isWebContentAtBottom = isAtBottom
                        }
                    },
                    onScrollPositionSnapshotChange: { position in
                        lastWebViewScrollPosition = position
                    },
                    onTextInteractionStateChange: { isActive in
                        isMessageTextInteractionActive = isActive
                    }
                )
                    .id(page) // force a new WKWebView per page

                if showWebViewLoadCover {
                    loadingTopicView
                        .transition(.opacity)
                }

                if isLoadingQuoteTemplate {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView(activeComposerPrefillMode.loadingLabel)
                        .neutralLoadingSpinner()
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .hfrLoadingPanel(in: .rect(cornerRadius: 12))
                }

                if isPreparingModerationAlert {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Chargement de l'alerte...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .hfrLoadingPanel(in: .rect(cornerRadius: 12))
                }

                if isDeletingMessage {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Suppression...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .hfrLoadingPanel(in: .rect(cornerRadius: 12))
                }

                if isPreparingAQPrompt {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Chargement de l'AQ...")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .hfrLoadingPanel(in: .rect(cornerRadius: 12))
                }
            }
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)

                .simultaneousGesture(
                    DragGesture().onEnded { value in
                        guard !isFavoritePostFilterMode else { return }
                        guard !isMessageTextInteractionActive else { return }
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        let minDistance: CGFloat = 120
                        let minHorizontalImpulse: CGFloat = 70
                        let maxVerticalRatio: CGFloat = 0.5
                        let horizontalImpulse = value.predictedEndTranslation.width - horizontal
                        if abs(horizontal) > minDistance &&
                            abs(horizontalImpulse) > minHorizontalImpulse &&
                            horizontal.sign == horizontalImpulse.sign &&
                            abs(vertical) < abs(horizontal) * maxVerticalRatio {
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
                .coverVerticalFullScreen(isPresented: $isComposerPresented) {
                    AnswerView(
                        topicURL: composerSubmitURL ?? topicAnswerURL,
                        title: composerNavigationTitle,
                        requiresSubject: composerRequiresSubject,
                        initialRecipient: composerRecipientName,
                        initialMessage: composerInitialMessage,
                        persistsComposerDraft: composerPersistsDraft,
                        onPostSuccess: handleReplySuccess,
                        composerDraftText: $composerDraftText,
                        isComposerPresented: $isComposerPresented
                    )
                }
                .sheet(item: $aqPromptState) { state in
                    MessagePopupPromptSheet(
                        title: "Alerte Qualitay",
                        message: "Créer une Alerte Qualitay sur le post de \(state.authorName)",
                        placeholder: "Ajoutez un titre",
                        actionTitle: "Créer"
                    ) { draftTitle, completion in
                        Task {
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
                                completion(.success("Alerte Qualitay créée."))
                            case .failure(let code):
                                completion(.failure(MessagePopupSheetSubmissionError(message: "Code erreur \(code)")))
                            case .networkError:
                                completion(.failure(MessagePopupSheetSubmissionError(message: "Création d'AQ impossible")))
                            }
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
                    ) { draftTitle, completion in
                        let created = MessagePopupActionSupport.createBookmark(
                            topicID: state.topicID,
                            topicCategory: state.topicCategory,
                            postID: state.postID,
                            title: draftTitle,
                            author: state.authorName
                        )
                        completion(created
                            ? .success("Bookmark créé")
                            : .failure(MessagePopupSheetSubmissionError(message: "Erreur à la création du bookmark")))
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
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            toolbarTitleView
                            toolbarSubtitleView
                        }
                        .multilineTextAlignment(.center)
                    }
                    if hasPoll && pollIsNewVote && !isInSearchMode {
                        ToolbarItem(placement: .topBarTrailing) {
                            PollToolbarButton(isVotable: true) {
                                Task { @MainActor in presentedPollData = pollData }
                            }
                        }
                    }
                    if isInSearchMode {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                openTopicSearchSheet()
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .accessibilityLabel("Rechercher")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Menu avec options
                        Menu {
                            if hasPoll && pollData != nil {
                                Button {
                                    Task { @MainActor in presentedPollData = pollData }
                                } label: {
                                    MenuActionLabel(
                                        "Sondage",
                                        systemImage: "chart.bar.doc.horizontal",
                                        tintColor: themePalette.actionTintColor,
                                        iconTintUIColor: themePalette.actionTintUIColor
                                    )
                                }
                            }
                            Button {
                                openTopicSearchSheet()
                            } label: {
                                MenuActionLabel(
                                    "Rechercher",
                                    systemImage: "magnifyingglass",
                                    tintColor: themePalette.actionTintColor,
                                    iconTintUIColor: themePalette.actionTintUIColor
                                )
                            }
                            if currentMaxPage > 1 {
                                Divider()
                                pageChoiceMenuItems()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(hasPoll ? themePalette.actionTintColor : .primary)
                        }
                    }
                    if !isComposerPresented {
                        if isFavoritePostFilterMode {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Spacer()
                                Button {
                                    advanceToNextFavoritePostFilterResults()
                                } label: {
                                    if isAdvancingFavoritePostFilterResults {
                                        Label("Filtrage...", systemImage: "hourglass")
                                    } else {
                                        Label("Résultats suivants", systemImage: "arrow.forward")
                                    }
                                }
                                .topicBottomBarButtonStyle(isProminent: true)
                                .disabled(isAdvancingFavoritePostFilterResults || favoritePostFilterResult?.isFinished == true)
                                Spacer()
                            }
                        } else if isFilteredSearchMode {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Spacer()
                                Button {
                                    advanceToNextSearchResults()
                                } label: {
                                    Label("Résultats suivants", systemImage: "arrow.forward")
                                }
                                .topicBottomBarButtonStyle(isProminent: true)
                                .disabled(isAdvancingSearchResults || lastSearchFormSnapshot.isEmpty)
                                Spacer()
                            }
                        } else {
                            ToolbarItemGroup(placement: .bottomBar) {
                                bottomPreviousPageButton
                                bottomNextPageButton
                            }

                            if isInSearchMode {
                                ToolbarItem(placement: .bottomBar) {
                                    Button {
                                        advanceToNextSearchResults()
                                    } label: {
                                        Image(systemName: "arrow.forward")
                                    }
                                    .topicBottomBarButtonStyle(isProminent: true)
                                    .disabled(isAdvancingSearchResults || lastSearchFormSnapshot.isEmpty)
                                    .accessibilityLabel("Résultat suivant")
                                }
                            }

                            ToolbarItem(placement: .bottomBar) {
                                Spacer()
                            }

                            if shouldShowBottomRefreshButton {
                                ToolbarItem(placement: .bottomBar) {
                                    Button {
                                        refreshCurrentPagePreservingScroll()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .topicBottomBarCircularIconButtonStyle(isProminent: true)
                                    .bottomBarStableHitTarget()
                                    .accessibilityLabel("Actualiser")
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }

                            if !shouldHideReplyComposerButton {
                                ToolbarItem(placement: .bottomBar) {
                                    Button {
                                        openReplyComposer()
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .topicBottomBarButtonStyle(isProminent: false)
                                    .bottomBarStableHitTarget()
                                    .accessibilityLabel("Répondre")
                                }
                            }
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
                .sheet(item: $presentedPollData) { data in
                    PollSheet(pollData: data, onVoteSucceeded: {
                        loadPage(page)
                    })
                }
                .sheet(item: $topicSearchSheetState) { state in
                    TopicSearchSheetView(
                        initialParams: state.initialParams,
                        isFromResultsPage: state.isFromResultsPage,
                        searchService: topicSearchService,
                        onResultReady: { url, params in
                            handleSearchResult(url: url, params: params)
                        }
                    )
                }
                .alert("Recherche impossible", isPresented: isSearchErrorAlertPresented) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(searchErrorMessage ?? "Erreur inconnue.")
                }
                .alert("Filtre impossible", isPresented: isFavoritePostFilterErrorAlertPresented) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(favoritePostFilterErrorMessage ?? "Erreur inconnue.")
                }
                .sheet(item: $safariDestination) { destination in
                    SafariInAppView(url: destination.url)
                        .ignoresSafeArea()
                }
                .sheet(item: $userProfileDestination) { destination in
                    UserProfileView(
                        profileURL: destination.url,
                        quickActions: userProfileQuickActions(for: destination.avatarActions)
                    )
                        .presentationGlassBackground()
                }
                .sheet(item: $smileySheetState) { state in
                    MessageSmileySheetView(
                        code: state.payload.code,
                        imageURL: state.payload.imageURL,
                        initiallyFavorite: state.isFavorite,
                        onToggleFavorite: { add in
                            updateSmileyFavorite(code: state.payload.code, imageURL: state.payload.imageURL, add: add)
                        },
                        onFetchKeywords: { completion in
                            Task {
                                completion(await fetchSmileyKeywords(code: state.payload.code))
                            }
                        },
                        onShowToast: { message in
                            showSuccessToast(message)
                        }
                    )
                    .presentationDetents([.medium])
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
            )
        } else {
            content = AnyView(
                loadingTopicView
                .navigationTitle("My title")
                .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        toolbarTitleView
                        toolbarSubtitleView
                    }
                    .multilineTextAlignment(.center)
                }
                if hasPoll && pollIsNewVote && !isInSearchMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        PollToolbarButton(isVotable: true) {
                            Task { @MainActor in presentedPollData = pollData }
                        }
                    }
                }
                if isInSearchMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openTopicSearchSheet()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Rechercher")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Menu avec options
                    Menu {
                        if hasPoll && pollData != nil {
                            Button {
                                Task { @MainActor in presentedPollData = pollData }
                            } label: {
                                MenuActionLabel(
                                    "Sondage",
                                    systemImage: "chart.bar.doc.horizontal",
                                    tintColor: themePalette.actionTintColor,
                                    iconTintUIColor: themePalette.actionTintUIColor
                                )
                            }
                        }
                        Button {
                            openTopicSearchSheet()
                        } label: {
                            MenuActionLabel(
                                "Rechercher",
                                systemImage: "magnifyingglass",
                                tintColor: themePalette.actionTintColor,
                                iconTintUIColor: themePalette.actionTintUIColor
                            )
                        }
                        if currentMaxPage > 1 {
                            Divider()
                            pageChoiceMenuItems()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(hasPoll ? themePalette.actionTintColor : .primary)
                    }
                }
                if isFilteredSearchMode {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        Button {
                            advanceToNextSearchResults()
                        } label: {
                            Label("Résultats suivants", systemImage: "arrow.forward")
                        }
                        .topicBottomBarButtonStyle(isProminent: true)
                        .disabled(isAdvancingSearchResults || lastSearchFormSnapshot.isEmpty)
                        Spacer()
                    }
                } else {
                    ToolbarItemGroup(placement: .bottomBar) {
                        bottomPreviousPageButton
                        bottomNextPageButton

                        if isInSearchMode {
                            Button {
                                advanceToNextSearchResults()
                            } label: {
                                Image(systemName: "arrow.forward")
                            }
                            .topicBottomBarButtonStyle(isProminent: true)
                            .disabled(isAdvancingSearchResults || lastSearchFormSnapshot.isEmpty)
                            .accessibilityLabel("Résultat suivant")
                        }

                        Spacer()
                        if !shouldHideReplyComposerButton {
                            Button {
                                openReplyComposer()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .topicBottomBarButtonStyle(isProminent: false)
                            .bottomBarStableHitTarget()
                            .accessibilityLabel("Répondre")
                        }
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
            .sheet(item: $presentedPollData) { data in
                PollSheet(pollData: data, onVoteSucceeded: {
                    loadPage(page)
                })
            }
            .onAppear {
                performInitialLoad()
            }
            .sheet(item: $topicSearchSheetState) { state in
                TopicSearchSheetView(
                    initialParams: state.initialParams,
                    isFromResultsPage: state.isFromResultsPage,
                    searchService: topicSearchService,
                    onResultReady: { url, params in
                        handleSearchResult(url: url, params: params)
                    }
                )
            }
            .alert("Recherche impossible", isPresented: isSearchErrorAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(searchErrorMessage ?? "Erreur inconnue.")
            }
            .alert("Filtre impossible", isPresented: isFavoritePostFilterErrorAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(favoritePostFilterErrorMessage ?? "Erreur inconnue.")
            }
            .sheet(item: $safariDestination) { destination in
                SafariInAppView(url: destination.url)
                    .ignoresSafeArea()
            }
            .sheet(item: $userProfileDestination) { destination in
                UserProfileView(
                    profileURL: destination.url,
                    quickActions: userProfileQuickActions(for: destination.avatarActions)
                )
                    .presentationGlassBackground()
            }
            .sheet(item: $smileySheetState) { state in
                MessageSmileySheetView(
                    code: state.payload.code,
                    imageURL: state.payload.imageURL,
                    initiallyFavorite: state.isFavorite,
                    onToggleFavorite: { add in
                        updateSmileyFavorite(code: state.payload.code, imageURL: state.payload.imageURL, add: add)
                    },
                    onFetchKeywords: { completion in
                        Task {
                            completion(await fetchSmileyKeywords(code: state.payload.code))
                        }
                    },
                    onShowToast: { message in
                        showSuccessToast(message)
                    }
                )
                .presentationDetents([.medium])
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
            )
        }

        return content
            .navigationDestination(isPresented: linkedTopicNavigationBinding) {
                if let linkedTopicDestination {
                    linkedTopicDestination
                } else {
                    EmptyView()
                }
            }
            .navigationDestination(isPresented: searchResultNavigationBinding) {
                if let searchResultDestination {
                    searchResultDestination
                } else {
                    EmptyView()
                }
            }
    }
}

private extension View {
    func coverVerticalFullScreen<PresentedContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> PresentedContent
    ) -> some View {
        background(
            CoverVerticalFullScreenPresenter(
                isPresented: isPresented,
                content: { AnyView(content()) }
            )
        )
    }
}

private struct CoverVerticalFullScreenPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let content: () -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> PresentationAnchorViewController {
        let viewController = PresentationAnchorViewController()
        viewController.view.backgroundColor = .clear
        viewController.onDidAppear = { [weak coordinator = context.coordinator, weak viewController] in
            guard let viewController else { return }
            coordinator?.updatePresentation(from: viewController)
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: PresentationAnchorViewController, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.content = content
        context.coordinator.updatePresentation(from: uiViewController)
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isPresented: Binding<Bool>
        var content: (() -> AnyView)?
        private weak var hostingController: UIHostingController<AnyView>?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func updatePresentation(from presenter: UIViewController) {
            guard presenter.view.window != nil else { return }

            if isPresented.wrappedValue {
                presentIfNeeded(from: presenter)
            } else {
                dismissIfNeeded()
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            hostingController = nil
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
        }

        private func presentIfNeeded(from presenter: UIViewController) {
            if let hostingController {
                hostingController.rootView = content?() ?? AnyView(EmptyView())
                return
            }

            guard presenter.presentedViewController == nil else { return }

            let hostingController = UIHostingController(rootView: content?() ?? AnyView(EmptyView()))
            hostingController.modalPresentationStyle = .fullScreen
            hostingController.modalTransitionStyle = .coverVertical
            hostingController.presentationController?.delegate = self
            self.hostingController = hostingController

            presenter.present(hostingController, animated: true)
        }

        private func dismissIfNeeded() {
            guard let hostingController else { return }
            self.hostingController = nil

            if hostingController.presentingViewController != nil {
                hostingController.dismiss(animated: true)
            }
        }
    }

    final class PresentationAnchorViewController: UIViewController {
        var onDidAppear: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onDidAppear?()
        }
    }
}

private struct MessageSmileySheetView: View {
    let code: String
    let imageURL: String
    let initiallyFavorite: Bool
    let onToggleFavorite: (Bool) -> Bool
    let onFetchKeywords: (@escaping (Result<[String], Error>) -> Void) -> Void
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
        onFetchKeywords: @escaping (@escaping (Result<[String], Error>) -> Void) -> Void,
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

    private func toggleFavorite() {
        let add = !isFavorite
        if onToggleFavorite(add) {
            isFavorite.toggle()
            onShowToast(add ? "Smiley ajouté aux favoris" : "Smiley retiré des favoris")
        } else {
            onShowToast("Erreur :/")
        }
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if isFavorite {
            favoriteButtonBase
                .hfrGlassButton()
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            favoriteButtonBase
                .hfrGlassButton(prominent: true)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var favoriteButtonBase: some View {
        Button {
            toggleFavorite()
        } label: {
            Label(
                isFavorite ? "Retirer des favoris" : "Ajouter aux favoris",
                systemImage: isFavorite ? "star.slash" : "star"
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

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
                        .frame(maxWidth: .infinity, alignment: .center)

                    favoriteButton

                    if isLoadingKeywords || !keywords.isEmpty || keywordsErrorMessage != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if isLoadingKeywords {
                                ProgressView("Chargement des mots clés...")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                            } else if let keywordsErrorMessage {
                                Text(keywordsErrorMessage)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.red)
                            } else if !keywords.isEmpty {
                                ScrollView {
                                    Text(keywords.joined(separator: "  "))
                                        .font(.footnote.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(maxHeight: 100)
                            }
                        }
                        .padding()
                        .background(.background, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        }
                    }

                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Smiley")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isLoadingKeywords = true
                keywordsErrorMessage = nil
                onFetchKeywords { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let fetchedKeywords):
                            keywords = fetchedKeywords
                        case .failure(let error):
                            keywords = []
                            keywordsErrorMessage = error.localizedDescription
                        }
                        isLoadingKeywords = false
                    }
                }
            }
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.bold())
                    }
                    .buttonBorderShape(.circle)
                    .hfrGlassButton()
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

                    if let profileURL = actions.profileURL {
                        Button {
                            onProfile(profileURL)
                        } label: {
                            Label("Profil", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .hfrGlassButton(prominent: true)
                    }

                    if !actions.isOwnMessage, let privateMessageURL = actions.privateMessageURL {
                        Button {
                            onPrivateMessage(privateMessageURL, actions)
                        } label: {
                            Label("MP", systemImage: "message")
                                .frame(maxWidth: .infinity)
                        }
                        .hfrGlassButton()
                    }

                    if !actions.isOwnMessage, let authorName = actions.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !authorName.isEmpty {
                        Button {
                            onWhitelist(authorName)
                        } label: {
                            Label("Whitelist", systemImage: "heart")
                                .frame(maxWidth: .infinity)
                        }
                        .hfrGlassButton()

                        Button(role: .destructive) {
                            onBlacklist(authorName)
                        } label: {
                            Label("Blacklist", systemImage: "hand.raised")
                                .frame(maxWidth: .infinity)
                        }
                        .hfrGlassButton()
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

enum PhotoViewerNetworkRequestFactory {
    static let forumReferer = "https://forum.hardware.fr"

    static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if requiresForumReferer(url) {
            request.setValue(forumReferer, forHTTPHeaderField: "Referer")
        }
        return request
    }

    static func requiresForumReferer(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "reho.st" || host.hasSuffix(".reho.st")
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

            let request = PhotoViewerNetworkRequestFactory.makeRequest(for: url)
            let task = URLSession.shared.dataTask(with: request) { [weak self, weak view] data, response, _ in
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
    func neutralLoadingSpinner() -> some View {
        self.tint(Color(uiColor: .secondaryLabel))
    }

    @ViewBuilder
    func legacyPageButtonSpacing(edge: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.padding(edge, 6)
        }
    }

    func bottomBarStableHitTarget() -> some View {
        self
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

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
    func topicBottomBarCircularIconButtonStyle(isProminent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if isProminent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.automatic)
            }
        } else {
            if isProminent {
                self.buttonBorderShape(.circle).buttonStyle(.borderedProminent)
            } else {
                self.buttonBorderShape(.circle).buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    func ifAvailableiOS26GlassProminent() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
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

    private var isError: Bool {
        let lowercasedText = text.lowercased()
        return lowercasedText.contains("erreur") || lowercasedText.contains("impossible")
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundStyle(isError ? Color.orange : Color.primary)
                .font(.headline)
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hfrToastSurface()
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

    @MainActor
    static func messagesPreview(
        page: Int = 55,
        maxPage: Int = 120,
        result: PreviewTopicPageLoader.Result,
        delay: TimeInterval = 0
    ) -> some View {
        let topic = sampleTopic(page: page, maxPage: maxPage)
        let loader = PreviewTopicPageLoader(result: result, delay: delay)
        let renderer = PreviewTopicPageRenderer()

        return NavigationStack {
            MessagesView(
                topic: topic,
                curPage: page,
                maxPage: maxPage,
                separatorNewMessages: true,
                topicPageLoader: loader,
                topicPageRenderer: renderer
            )
        }
    }
}

#Preview("Messages - happy path") {
    MessagesPreviewFactory.messagesPreview(
        result: .success(
            TopicPageContent(
                html: MessagesPreviewFactory.sampleHTML,
                topicAnswerURL: URL(string: "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=42")
            )
        )
    )
}

#Preview("Messages - loading") {
    MessagesPreviewFactory.messagesPreview(
        page: 12,
        maxPage: 48,
        result: .success(
            TopicPageContent(
                html: MessagesPreviewFactory.sampleHTML,
                topicAnswerURL: nil
            )
        ),
        delay: 3
    )
}

#Preview("Messages - toolbar compact") {
    NavigationStack {
        VStack(spacing: 24) {
            Text("Aperçu pagination")
                .font(.headline)
            HStack(spacing: 12) {
                Button {} label: {
                    Image(systemName: "chevron.backward")
                }

                Button {} label: {
                    Text("55")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 34)
                }

                Button {} label: {
                    Image(systemName: "chevron.forward")
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Le rendu complet reste disponible dans l'aperçu happy path.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Messages")
    }
}

#Preview("Messages - error") {
    MessagesPreviewFactory.messagesPreview(
        page: 1,
        maxPage: 5,
        result: .failure(MessagesPreviewFactory.PreviewError.network)
    )
}
