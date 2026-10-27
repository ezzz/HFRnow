import Foundation
import HFRModels
import SwiftSoup

/// Classifies the page HFR answers after a write (reply, edit, delete, new topic, MP, flag, alert): LOT-037.
///
/// HFR answers HTTP 200 whether the write worked or not; only the page tells. Every page is a `div.hop` message,
/// optionally with a `<meta http-equiv="Refresh">`. A page is `success` only when HFR confirmed it: a refresh to the
/// forum, a `.hop` with no link and no input, **and** a sentence saying "avec succès" (every captured write success has
/// it; login pages, empty lists and the search waiting page also refresh but never say it); anything else that is not clearly a refusal is
/// `unrecognized`, so callers never report a success they did not see.
public enum HopResponseParser {
    /// What the request was, which decides how the same `.hop` shape is read.
    public enum Context: Sendable {
        /// The answer to a submitted write: a `.hop` with a link or input is a refusal.
        case write
        /// The page that precedes the moderator alert form: a `.hop` with a link or input means "already alerted"
        /// (`ReplyService.swift:1564-1572`, `AlerteModoViewController.m:154-163`), the form itself has no `.hop`.
        case alertPrepare
    }

    /// Classifies `html`; `requestURL` resolves a relative refresh target (the forum root by default).
    ///
    /// `.alertPrepare` on the alert form page (`R46`, no `.hop`) is `unrecognized`: that is **not** a go-ahead. The alert
    /// flow proceeds only when the form parser (LOT-036) finds the alert form; this result only says "not already alerted".
    ///
    /// The status code is not read here: callers treat a non-2xx answer as a transport failure before parsing.
    /// - Throws: `malformedDocument` when the HTML backend cannot read the page.
    public static func classify(
        html: String,
        context: Context = .write,
        requestURL: URL = HFRURL.base
    ) throws(ParsingError) -> HopResponse {
        let document = try HTMLDocumentLoader.document(from: html)
        guard let hop = document.firstDescendant(matching: .exact("hop")) else {
            return plainTextRefusal(in: document) ?? HopResponse(kind: .unrecognized)
        }
        let message = text(ofHop: hop)
        if hasLinkOrInput(hop) {
            if isLoggedOutMessage(message) { return HopResponse(kind: .loggedOut, message: message) }
            return HopResponse(kind: context == .alertPrepare ? .alreadyAlerted : .rejected, message: message)
        }
        guard context == .write, isSuccessSentence(message), let target = refreshTarget(in: document, requestURL: requestURL) else {
            return HopResponse(kind: .unrecognized, message: message)
        }
        return HopResponse(kind: .success, message: message, refreshURL: target, refreshAnchor: anchor(of: target))
    }

    // MARK: - Implementation

    /// Start of the body HFR sends, without any HTML, when `hash_check` is wrong (`W17b`: 99 bytes of plain text).
    private static let invalidTokenPrefix = "Une erreur est survenue lors de l'envoi des données"
    /// Part of the `.hop` text of every captured write success (`W10`-`W16b`, `W18`, `W19`, `P03a`, `P03b`, `P03d`).
    private static let successMarker = "avec succès"
    /// Words that turn a sentence negative; none occurs in a captured confirmation (`non lu` of `W18` is not one).
    /// Apostrophes split words, so `n'a` yields `n`.
    private static let negations: Set<String> = ["ne", "n", "pas", "aucun", "aucune", "impossible", "erreur", "échec", "jamais"]
    /// Part of the `.hop` text of a write sent without a session (`W17c`).
    private static let loggedOutMarker = "vous devez être enregistré"

    /// A body that is HFR's known plain-text refusal; legacy found no `.hop` and reported success (`W17b`).
    private static func plainTextRefusal(in document: Document) -> HopResponse? {
        guard let body = document.body(), let raw = try? body.text() else { return nil }
        let text = collapsed(raw)
        guard text.hasPrefix(invalidTokenPrefix) else { return nil }
        return HopResponse(kind: .rejected, message: text)
    }

    /// Text of the `.hop` block outside links, buttons and inputs: the sentence, not "Retour à la page précédente",
    /// and still the whole sentence when part of it sits in a nested element such as `<b>`. Nil when empty.
    private static func text(ofHop hop: Element) -> String? {
        var text = ""
        appendSentence(of: hop, to: &text)
        text = collapsed(text)
        return text.isEmpty ? nil : text
    }

    private static func appendSentence(of element: Element, to text: inout String) {
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                text += textNode.getWholeText()
            } else if let child = node as? Element, !skippedTags.contains(child.tagName()) {
                // Inline markup keeps a split word whole (`enre<b>gistré</b>`); breaks and blocks separate words.
                let separator = child.isBlock() || child.tagName() == "br" ? " " : ""
                text += separator
                appendSentence(of: child, to: &text)
                text += separator
            }
        }
    }

    private static let skippedTags: Set<String> = ["a", "button", "input", "script", "style"]

    private static func hasLinkOrInput(_ hop: Element) -> Bool {
        guard let found = try? hop.select("a, input") else { return false }
        return !found.isEmpty()
    }

    /// Positive confirmation: a refresh plus a `.hop` sentence is not enough (`W01` refusal, `R08-1`, `R50a` have both).
    /// The sentence must also be affirmative: "n'a pas été posté avec succès" is a refusal that contains the marker.
    private static func isSuccessSentence(_ message: String?) -> Bool {
        guard let lowered = message?.lowercased(), lowered.contains(successMarker) else { return false }
        let words = lowered.split { !$0.isLetter }
        return !words.contains { negations.contains(String($0)) }
    }

    private static func isLoggedOutMessage(_ message: String?) -> Bool {
        message?.lowercased().contains(loggedOutMarker) ?? false
    }

    /// Target of the first refresh meta, only when it is an `https` forum URL: it is the page the app will request
    /// with the session (LESSONS 37, 43).
    private static func refreshTarget(in document: Document, requestURL: URL) -> URL? {
        guard let metas = try? document.getElementsByTag("meta") else { return nil }
        for meta in metas.array() {
            guard
                let equivalent = try? meta.attr("http-equiv"),
                equivalent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "refresh",
                let content = try? meta.attr("content"),
                let raw = SearchRedirectParser.target(inRefreshContent: content)
            else { continue }
            guard
                let url = HFRURL.absolute(raw, relativeTo: requestURL),
                url.scheme == "https",
                url.host(percentEncoded: false) == HFRURL.forumHost,
                url.port == nil || url.port == 443
            else { return nil }
            return url
        }
        return nil
    }

    private static func anchor(of url: URL) -> String? {
        guard let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty else { return nil }
        return fragment
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
