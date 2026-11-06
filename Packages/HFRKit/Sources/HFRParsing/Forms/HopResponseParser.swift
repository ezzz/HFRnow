import Foundation
import HFRModels
import SwiftSoup

/// Classifies the page HFR answers after a write (reply, edit, delete, new topic, MP, flag, alert, poll
/// vote): LOT-037.
///
/// HFR answers HTTP 200 whether the write worked or not; only the page tells. Every page is a `div.hop` message,
/// optionally with a `<meta http-equiv="Refresh">`. A page is `success` only when HFR confirmed it: a refresh to the
/// forum, a `.hop` with no link and no input, **and** a sentence saying "avec succès" (every captured write success has
/// it; login pages, empty lists and the search waiting page also refresh but never say it); anything else that is not clearly a refusal is
/// `unrecognized`, so callers never report a success they did not see. A poll vote and a moderator alert are confirmed by
/// their own sentences instead, each in its own context only (`Context.pollVote`, `W42`; `Context.alertSubmit`, `W46`).
public enum HopResponseParser {
    /// What the request was, which decides how the same `.hop` shape is read.
    public enum Context: Sendable {
        /// The answer to a submitted write: a `.hop` with a link or input is a refusal.
        case write
        /// The page that precedes the moderator alert form: a `.hop` with a link or input means "already alerted"
        /// (`ReplyService.swift:1564-1572`, `AlerteModoViewController.m:154-163`, `R88`), the form itself has no `.hop`.
        /// HFR's alert-page sentence for a missing session (`R89`) is `loggedOut`.
        case alertPrepare
        /// The answer to a submitted moderator alert (LOT-050): HFR confirms it with its own sentence, **with** the back
        /// link and no refresh (`W46`), and that sentence is a confirmation in this context only. Any other `.hop` with a
        /// link or input is a refusal; HFR's alert sentence for a missing session (`W47`) is `loggedOut`.
        case alertSubmit
        /// The answer to a poll vote (LOT-054): HFR confirms it with its own sentence, without "avec succès" (`W42`), and
        /// that sentence is a confirmation in this context only. A `.hop` with a link or input is a refusal (`W43`, `W44`).
        case pollVote
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
            if isLoggedOutMessage(message, in: context) { return HopResponse(kind: .loggedOut, message: message) }
            switch context {
            case .alertPrepare: return HopResponse(kind: .alreadyAlerted, message: message)
            // `W46` has no refresh: nothing to follow, `refreshURL` stays nil.
            case .alertSubmit where message == alertConfirmation: return HopResponse(kind: .success, message: message)
            case .write, .pollVote, .alertSubmit: return HopResponse(kind: .rejected, message: message)
            }
        }
        guard isConfirmation(message, in: context), let target = refreshTarget(in: document, requestURL: requestURL) else {
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
    /// The whole `.hop` text of an accepted poll vote (`W42`), whitespace collapsed.
    static let pollVoteConfirmation = "Votre vote a bien été pris en compte !"
    /// The whole `.hop` text of a submitted moderator alert (`W46`), whitespace collapsed, link text excluded.
    static let alertConfirmation = "Un message a été envoyé avec succès aux modérateurs"
    /// Part of the `.hop` text of a write sent without a session (`W17c`).
    private static let loggedOutMarker = "vous devez être enregistré"
    /// The whole `.hop` text of the alert page and of an alert sent without a session (`R89`, `W47`).
    static let alertLoggedOut = "Vous devez être identifié pour prévenir les modérateurs"

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

    /// The link-less sentence that confirms a write of `context`: an affirmative "avec succès" one for `.write` except
    /// the alert's (it says "avec succès" but confirms an alert only), exactly the vote sentence for `.pollVote` (a write
    /// confirmation is not a vote's, nor the reverse), none before the alert form nor after it (its confirmation has a
    /// link, `W46`).
    private static func isConfirmation(_ message: String?, in context: Context) -> Bool {
        switch context {
        case .write: message != alertConfirmation && isSuccessSentence(message)
        case .pollVote: message == pollVoteConfirmation
        case .alertPrepare, .alertSubmit: false
        }
    }

    /// Positive confirmation: a refresh plus a `.hop` sentence is not enough (`W01` refusal, `R08-1`, `R50a` have both).
    /// The sentence must also be affirmative: "n'a pas été posté avec succès" is a refusal that contains the marker.
    private static func isSuccessSentence(_ message: String?) -> Bool {
        guard let lowered = message?.lowercased(), lowered.contains(successMarker) else { return false }
        let words = lowered.split { !$0.isLetter }
        return !words.contains { negations.contains(String($0)) }
    }

    /// HFR's sentence for a missing session: `W17c`'s in every context, the alert pages' (`R89`, `W47`) in the alert
    /// contexts only, where it was captured.
    private static func isLoggedOutMessage(_ message: String?, in context: Context) -> Bool {
        guard let message else { return false }
        if message.lowercased().contains(loggedOutMarker) { return true }
        switch context {
        case .alertPrepare, .alertSubmit: return message == alertLoggedOut
        case .write, .pollVote: return false
        }
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
