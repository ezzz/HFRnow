import Foundation
import HFRModels

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
    static func document(for page: ReaderPage, token: Int, options: ReaderRenderOptions = ReaderRenderOptions()) -> String {
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
        <body class="\(options.showsSignatures ? "signatures" : "nosig")">
        <main>

        """
        for message in page.messages {
            html += article(for: message, options: options)
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
        let anchor = message.isContinuation ? "" : " id=\"t\(message.numreponse)\""
        let label = message.dateText.isEmpty ? "Message de \(author)" : "Message de \(author), \(date)"
        var html = "<article class=\"\(classes.joined(separator: " "))\"\(anchor) data-post=\"\(message.numreponse)\""
        html += " aria-label=\"\(label)\">\n"
        html += "<header class=\"header\">"
        if let avatar = message.avatarURL {
            html += "<img class=\"avatar\" src=\"\(HTMLEscaping.text(avatar.absoluteString))\" alt=\"\">"
        }
        html += "<span class=\"author\">\(author)</span>"
        if !message.dateText.isEmpty { html += "<span class=\"date\">\(date)</span>" }
        html += "</header>\n"
        if message.isContinuation { html += "<p class=\"continuation-note\">Reprise du message précédent</p>\n" }
        if message.isDeleted { html += "<p class=\"deleted-note\">Message supprimé</p>\n" }
        // Body markup context only (LOT-034 contract).
        html += "<div class=\"content\">\(message.content.html)</div>\n"
        html += videos(of: message)
        if options.showsSignatures, let signature = message.content.signatureHTML {
            html += "<div class=\"signature\">\(signature)</div>\n"
        }
        html += trailer(of: message)
        html += "</article>\n"
        return html
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
