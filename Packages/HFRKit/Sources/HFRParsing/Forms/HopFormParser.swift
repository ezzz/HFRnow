import Foundation
import HFRModels
import SwiftSoup

/// Reads the write forms of HFR pages into a `ForumForm` (HFR-PROTOCOL §3.1, captures `R40a`–`R47u1`).
///
/// The parser only reports what the page contains: which fields to send, how an unchecked box is encoded and how the
/// `action` is resolved are decisions of the posting flow (LOT-048). It does not tell whether the visitor is logged in:
/// `hash_check` is present on anonymous pages too (header search form), so only its value says anything (`R40b`).
public enum HopFormParser {
    /// The `<form name="hop">` of a reply, quote, edit, new-topic or private-message composer.
    ///
    /// Inputs and selects come in page order, every named one (legacy kept only those with a `value` attribute and sent a
    /// checkbox as `"1"`/`"0"`, `QuoteMessageViewController.m:209-290`). The `content_form` textarea gives
    /// `textareaContent` (quote or edit prefill, `[quotemsg=…]` blocks included), entity-decoded with line breaks as `\n`;
    /// `nil` when the textarea is empty or absent. `#dynamic_smilies` gives the favourite smileys of the account.
    ///
    /// `action` is resolved against `pageURL` (the URL the page was served from) and kept only as a forum-origin path,
    /// because the posting flow sends the session, `hash_check` and the text there (LESSONS 37): an action on another
    /// host, an `http` one that is not upgraded (explicit port), a non-443 port, user info, or none at all gives `nil`, and
    /// the caller must not post. `http://forum.hardware.fr/…` without a port is upgraded to `https` and accepted.
    /// - Throws: `missingElement` when the page has no form named `hop` (a `.hop` message page, a login wall, an error page);
    ///   telling those apart is the job of the response classifier (LOT-037).
    public static func parse(_ html: String, pageURL: URL = HFRURL.base) throws(ParsingError) -> ForumForm {
        let document = try HTMLDocumentLoader.document(from: html)
        guard let form = form(in: document, attribute: "name", matching: .exact("hop")) else {
            throw .missingElement("form name=hop")
        }
        return makeForm(form, in: document, pageURL: pageURL)
    }

    /// The moderator alert form of `/user/modo.php`: the form whose `action` contains `modo.php`.
    ///
    /// It holds `hash_check`, `referer_page` and the submit button, and a `raison` textarea that is not read (the reason is
    /// the user's text). Its `action` is relative to the page URL (`modo.php?…` served from `/user/modo.php`), hence the
    /// `pageURL` default; it comes back as a forum-origin path (`/user/modo.php?…`) with the decoded query (legacy decoded
    /// `&amp;`, the Swift service did not: LOT-004 quirk 5), and `nil` when it leaves the forum origin (see `parse`).
    /// - Throws: `missingElement` when there is no such form, which is also the case of a message already reported
    ///   (a `.hop` block with a link replaces the form, `AlerteModoViewController.m:154-163`).
    public static func parseModerationForm(_ html: String, pageURL: URL = moderationPageURL) throws(ParsingError) -> ForumForm {
        let document = try HTMLDocumentLoader.document(from: html)
        guard let form = form(in: document, attribute: "action", matching: .contains("modo.php")) else {
            throw .missingElement("form action*=modo.php")
        }
        return makeForm(form, in: document, pageURL: pageURL)
    }

    /// Where the alert form is served from (`AlerteModoViewController.m:176`: `ForumURL/user/` + action).
    public static let moderationPageURL: URL = HFRURL.absolute("/user/modo.php") ?? HFRURL.base

    // MARK: - Implementation

    /// First descendant `<form>` whose `attribute` matches; legacy accepted any tag named `hop`, a `<form>` is stricter
    /// so an anchor `<a name="hop">` cannot stand for an empty form.
    private static func form(in document: Document, attribute: String, matching match: AttributeMatch) -> Element? {
        document.descendants(attribute: attribute, matching: match).first { $0.tagName() == "form" }
    }

    private static func makeForm(_ form: Element, in document: Document, pageURL: URL) -> ForumForm {
        ForumForm(
            action: attribute("action", of: form).flatMap { forumPath(of: $0, pageURL: pageURL) },
            fields: elements("input", in: form).compactMap(field),
            selects: elements("select", in: form).compactMap(select),
            textareaContent: prefill(in: form),
            dynamicSmileys: smileys(in: document)
        )
    }

    private static func elements(_ tag: String, in element: Element) -> [Element] {
        ((try? element.getElementsByTag(tag))?.array() ?? []).filter { $0 !== element }
    }

    /// The action as a path on the forum origin, nil when it points elsewhere: resolved against the page first, so a
    /// relative `modo.php?…` lands in `/user/`, then restricted like every link the session may follow (LESSONS 37, 43).
    private static func forumPath(of action: String, pageURL: URL) -> String? {
        HFRURL.absolute(action, relativeTo: pageURL).flatMap { HFRURL.forumRelativePath($0.absoluteString) }
    }

    /// Attribute value, nil when the attribute is absent. SwiftSoup decodes entities, which legacy did not (bug B1).
    private static func attribute(_ name: String, of element: Element) -> String? {
        element.hasAttr(name) ? (try? element.attr(name)) : nil
    }

    private static func field(_ input: Element) -> FormField? {
        guard let name = attribute("name", of: input) else { return nil }
        return FormField(
            name: name,
            value: attribute("value", of: input) ?? "",
            kind: FormInputKind(htmlType: attribute("type", of: input)),
            isChecked: input.hasAttr("checked")
        )
    }

    /// A browser sends an option without `value` by its text; legacy sent nothing. The first `selected` option wins.
    private static func select(_ element: Element) -> FormSelect? {
        guard let name = attribute("name", of: element) else { return nil }
        var options: [FormOption] = []
        var selected: String?
        for option in elements("option", in: element) {
            let label = option.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = attribute("value", of: option) ?? label
            options.append(FormOption(value: value, label: label))
            if selected == nil, option.hasAttr("selected") {
                selected = value
            }
        }
        return FormSelect(name: name, options: options, selectedValue: selected)
    }

    /// Text of `#content_form`. The HTML tokenizer already decoded the entities; CRLF (stored as sent, `R43a`) and a lone CR
    /// become LF, as legacy did for CRLF (`QuoteMessageViewController.m:459`), so callers re-encode line breaks once.
    private static func prefill(in form: Element) -> String? {
        let candidates = form.descendants(attribute: "id", matching: .exact("content_form"))
        guard let area = candidates.first(where: { $0.tagName() == "textarea" }) else { return nil }
        let text = area.rawText.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        return text.isEmpty ? nil : text
    }

    /// `<img src alt>` of `#dynamic_smilies`, looked up in the whole page like legacy (`QuoteMessageViewController.m:128-170`).
    /// An image without `alt` or with an unusable `src` is skipped (ADR 0006 amendment 1).
    private static func smileys(in document: Document) -> [ForumSmiley] {
        guard let container = document.firstDescendant(attribute: "id", matching: .exact("dynamic_smilies")) else { return [] }
        return elements("img", in: container).compactMap { image in
            guard
                let code = attribute("alt", of: image), !code.isEmpty,
                let source = attribute("src", of: image),
                let url = HFRURL.absolute(source)
            else { return nil }
            return ForumSmiley(code: code, url: url)
        }
    }
}
