import Foundation
import HFRModels

// Port of Classes/ObjCTopicMessageContentBuilder.m and SuperHFRplus/Assets/HTML/templatev2.htm @ 2440d79. Differences: built from the
// typed MessageContent (ADR 0006); a one-line header instead of the grey band with "+" (GAP-051, UXD).
/// Escapes untrusted text for the two HTML contexts the builder writes: element content and double-quoted attributes.
enum HTMLEscaping {
    /// `&`, `<`, `>`, `"` and `'` replaced by entities: safe as element content and inside a double-quoted attribute.
    static func text(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.utf8.count)
        for character in value.unicodeScalars {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.unicodeScalars.append(character)
            }
        }
        return escaped
    }
}

/// Display choices applied by the builder from the typed lists (ADR 0006), never by re-parsing.
struct ReaderRenderOptions: Equatable, Sendable {
    /// Append each message's `signatureHTML` (`display_sig`, off by default as in legacy).
    var showsSignatures = false
    /// Give each message a `⋯` button (LOT-087). Off until a message-menu handler is registered.
    var showsMessageMenus = false
    /// Make each author tappable (legacy avatar popup). Off until an author-menu handler is registered.
    var showsAuthorMenus = false
    /// Message layout (`theme_style`): the legacy default is modern (`AppSettingsView.swift:98` @ 2440d79 reads 1).
    var style = ThemeStyle.modern
    /// Who is highlighted, collapsed or allowlisted (LOT-117); nothing by default.
    var visibility = VisibilityPolicy.none
}

/// Builds the reader's HTML document from a `ReaderPage` (LOT-083, audit C12).
///
/// Context contract of LOT-034: `MessageContent.html` and `signatureHTML` are inserted as **element content of the body**
/// only, never into a script, an attribute, a raw-text element or an XML document. Every other value (pseudo, date, edit
/// note, title, URLs) is escaped here. The document loads nothing remote: the Content Security Policy only allows the
/// reader's own scheme, and `reader.js` (injected by the web view, not referenced by the page) routes each image through
/// the policy C.
enum TopicHTMLBuilder {
    /// Scheme of the reader's own resources: the page, its stylesheet and every image (through the cookie-less client).
    static let scheme = "hfrreader"

    /// The policy delivered with the page, as a header and as a `<meta>`: nothing remote, no script from the page, no
    /// frame, no form, no base URL. Style attributes stay allowed (`style-src-attr`) because LOT-034 keeps the sanitized
    /// `color:` of user colours and code highlighting there; `<style>` elements are refused (`style-src-elem`), and any
    /// CSS `url()` falls under `img-src`, i.e. the app's scheme and its policy. `style-src` is the fallback for engines
    /// without the CSP 3 split.
    static let contentSecurityPolicy = [
        "default-src 'none'", "img-src \(scheme):", "style-src \(scheme): 'unsafe-inline'", "style-src-elem \(scheme):",
        "style-src-attr 'unsafe-inline'", "script-src 'none'",
        "frame-src 'none'", "child-src 'none'", "connect-src 'none'", "font-src 'none'", "media-src 'none'",
        "object-src 'none'", "manifest-src 'none'", "worker-src 'none'", "form-action 'none'", "base-uri 'none'"
    ].joined(separator: "; ")

    /// The full document for `page`. `token` identifies this document so a late event of an older one is ignored.
    /// `separatorAfter` is the flag message: legacy draws a dashed line after it (not after the last message), so the
    /// unread messages start below it (`ObjCTopicMessageContentBuilder.m:25-33` @ 2440d79).
    static func document(
        for page: ReaderPage, token: Int, options: ReaderRenderOptions = ReaderRenderOptions(), separatorAfter: Int? = nil
    ) -> String {
        var options = options
        // "Ego" highlights are not applied on private messages (legacy comment, `MessagesTableViewController.m:1401`).
        if page.topicID?.category == .privateMessages { options.visibility = options.visibility.withoutOwnHighlights() }
        var html = """
        <!DOCTYPE html>
        <html lang="fr" data-token="\(token)">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="referrer" content="no-referrer">
        <meta http-equiv="x-dns-prefetch-control" content="off">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <link rel="stylesheet" href="\(scheme)://resource/reader.css">
        <title>\(HTMLEscaping.text(page.title))</title>
        </head>
        <body class="\(options.showsSignatures ? "signatures" : "nosig") \(options.style == .classic ? "style-classic" : "style-modern")">
        <main>

        """
        for (index, message) in page.messages.enumerated() {
            html += article(for: message, options: options)
            if !message.isContinuation, message.numreponse == separatorAfter, index < page.messages.count - 1 {
                html += "<div class=\"separator1\"></div>\n"
            }
        }
        html += "</main>\n</body>\n</html>\n"
        return html
    }

    /// One message. The anchor id `t<numreponse>` is set on the original message only: the continuation block repeats the
    /// number, and the content keeps no `id` of its own (LOT-034 drops them), so ids cannot collide.
    static func article(for message: ReaderMessage, options: ReaderRenderOptions) -> String {
        let author = HTMLEscaping.text(message.author)
        let date = HTMLEscaping.text(message.dateText)
        var classes = ["message"]
        if message.isContinuation { classes.append("continuation") }
        if message.isDeleted { classes.append("deleted") }
        let visibility = options.visibility.post(by: message.author)
        if let visibilityClass = Self.cssClass(of: visibility) { classes.append(visibilityClass) }
        let hidesAuthor = visibility == .blocked && options.visibility.hidesBlockedPseudo
        let anchor = message.isContinuation ? "" : " id=\"t\(message.numreponse)\""
        var label = message.dateText.isEmpty ? "Message de \(author)" : "Message de \(author), \(date)"
        if hidesAuthor { label = "Message masqué" }
        var html = "<article class=\"\(classes.joined(separator: " "))\"\(anchor) data-post=\"\(message.numreponse)\""
        html += " aria-label=\"\(label)\">\n"
        if visibility == .blocked { html += Self.blockedSummary(author: author, hidesAuthor: hidesAuthor) }
        html += header(of: message, author: author, date: date, options: options)
        if message.isContinuation { html += "<p class=\"continuation-note\">Reprise du message précédent</p>\n" }
        if message.isDeleted { html += "<p class=\"deleted-note\">Message supprimé</p>\n" }
        // Body markup context only (LOT-034 contract).
        let content = QuoteMarkup.annotate(message.content.html, quotes: message.quotes, policy: options.visibility)
        html += "<div class=\"content\">\(content)</div>\n"
        html += videos(of: message)
        if options.showsSignatures, let signature = message.content.signatureHTML {
            html += "<div class=\"signature\">\(signature)</div>\n"
        }
        html += trailer(of: message)
        if visibility == .blocked { html += "</details>\n" }
        html += "</article>\n"
        return html
    }

    /// The message header: avatar, author (a button when the author menu is on), date and the `⋯` button.
    private static func header(of message: ReaderMessage, author: String, date: String, options: ReaderRenderOptions) -> String {
        var html = ""
        html += "<header class=\"header\">"
        let showsMessageMenu = options.showsMessageMenus && !message.isContinuation
        let opensAuthorMenu = options.showsAuthorMenus && !message.isContinuation
        html += avatar(of: message, opensMenu: opensAuthorMenu)
        // The author is the message's heading (LOT-163): the web rotor's "Titres" steps from message to message.
        html += "<span class=\"byline\" role=\"heading\" aria-level=\"2\">"
        if opensAuthorMenu {
            // The author opens the author's menu (legacy: the avatar and the pseudo both did); the numbers are ours, never page text.
            html += "<button type=\"button\" class=\"author menu-author\" data-menu=\"avatar\" data-post=\"\(message.numreponse)\""
            html += " aria-haspopup=\"menu\" aria-label=\"Menu de \(author)\">\(author)</button>"
        } else {
            html += "<span class=\"author\">\(author)</span>"
        }
        html += "</span>"
        if !message.dateText.isEmpty { html += "<span class=\"date\">\(date)</span>" }
        if showsMessageMenu {
            html += "<button type=\"button\" class=\"menu-button\" data-menu=\"message\" data-post=\"\(message.numreponse)\""
            html += " aria-haspopup=\"menu\" aria-label=\"Actions du message de \(author)\">⋯</button>"
        }
        html += "</header>\n"
        return html
    }

    /// The avatar: the member's picture over a monogram (initials on a disc coloured from the pseudo, as the MP list's, #578).
    /// The monogram is local markup, no request and no script, so the CSP needs nothing; `reader.js` removes the picture
    /// when it is refused or fails (`has-image` off) and the monogram shows. A button when it opens the author menu: it repeats
    /// the author button next to it, so assistive technologies skip it (LOT-163) while a finger still reaches it.
    static func avatar(of message: ReaderMessage, opensMenu: Bool) -> String {
        let mark = Monogram(pseudo: message.author)
        let light = Monogram.hex(mark.background(dark: false)), dark = Monogram.hex(mark.background(dark: true))
        let hasImage = message.avatarURL != nil
        let classes = "avatar-wrap" + (hasImage ? " has-image" : "")
        var html = opensMenu
            ? "<button type=\"button\" class=\"\(classes) menu-avatar\" data-menu=\"avatar\" data-post=\"\(message.numreponse)\""
                + " aria-hidden=\"true\" tabindex=\"-1\">"
            : "<span class=\"\(classes)\">"
        html += "<span class=\"avatar avatar-default\" style=\"--mono-light:\(light);--mono-dark:\(dark)\" aria-hidden=\"true\">"
        html += "\(HTMLEscaping.text(mark.initials))</span>"
        if let url = message.avatarURL {
            html += "<img class=\"avatar\" src=\"\(HTMLEscaping.text(url.absoluteString))\" alt=\"\">"
        }
        return html + (opensMenu ? "</button>" : "</span>")
    }

    private static func cssClass(of visibility: VisibilityPolicy.Post) -> String? {
        switch visibility {
        case .moderation: "mode"
        case .own: "me"
        case .allowlisted: "whitelist"
        case .blocked: "blocked"
        case .normal: nil
        }
    }

    /// A native disclosure: no script is needed to read it, and the message menu (alert included) stays in the body.
    private static func blockedSummary(author: String, hidesAuthor: Bool) -> String {
        var html = "<details class=\"blocked-post\"><summary class=\"blocked-summary\">"
        if !hidesAuthor { html += "<span class=\"blocked-author\">\(author)</span>" }
        return html + "<span class=\"blocked-note\">Message masqué</span></summary>\n"
    }

    /// A placeholder per video (LOT-071 D-071-2): nothing of the provider loads before a tap, which opens the player.
    private static func videos(of message: ReaderMessage) -> String {
        guard !message.content.embeds.isEmpty else { return "" }
        var html = "<div class=\"videos\">"
        for (index, embed) in message.content.embeds.enumerated() {
            let name = providerName(embed.provider)
            html += "<button type=\"button\" class=\"video\" data-post=\"\(message.numreponse)\" data-video=\"\(index)\""
            html += " aria-label=\"Lire la vidéo \(name)\">Vidéo \(name) · toucher pour lire</button>"
        }
        return html + "</div>\n"
    }

    private static func trailer(of message: ReaderMessage) -> String {
        var lines: [String] = []
        if let note = message.editNote, !note.isEmpty { lines.append("Message édité par \(HTMLEscaping.text(note))") }
        if let count = message.quotedByCount, count > 0 { lines.append("Message cité \(count) fois") }
        guard !lines.isEmpty else { return "" }
        return "<footer class=\"trailer\">" + lines.map { "<p>\($0)</p>" }.joined() + "</footer>\n"
    }

    /// Display name of a video provider.
    static func providerName(_ provider: EmbedProvider) -> String {
        switch provider {
        case .youtube: "YouTube"
        case .vimeo: "Vimeo"
        case .streamable: "Streamable"
        }
    }
}
