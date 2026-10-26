import Foundation
import HFRModels
import SwiftSoup

/// Reads the page-level data of a topic page (`/hfr/<cat>/<slug>-sujet_<post>_<page>.htm` or `forum2.php?…`, also private
/// conversations): title, pager, answer form, hidden fields, unread link, poll presence, in-topic search form.
///
/// Port of `-[ObjCTopicPageWorker parseMetadataFromBody:parser:]`, `-searchInputDataFromBody:` and the title and pager part of
/// `-[ParseMessagesOperation parseData:]` (`ObjCTopicPageWorker.m:103-179`, `ParseMessagesOperation.m:488-507`).
/// Messages (LOT-030) and the poll (LOT-026) are not read here. A missing piece is an absent value, never an error: a deleted
/// private conversation is a valid page with no title, no pager and no forms.
public enum TopicPageMetadataParser {
    /// Parses one page.
    /// - Parameters:
    ///   - html: the page, decoded as UTF-8.
    ///   - pageURL: the URL the page was finally served from, after redirects (HFR redirects a page beyond the last one to
    ///     the last page, `R24`). Relative or absolute; it gives `currentPage` and, as a last resort, the topic identity.
    /// - Throws: `malformedDocument` when the HTML backend cannot read the document.
    public static func parse(html: String, pageURL: String) throws(ParsingError) -> TopicPageMetadata {
        let document = try HTMLDocumentLoader.document(from: html)
        let body = document.body() ?? document
        let answerFields = answerFormFields(in: body)
        let searchFields = searchFormFields(in: body)
        return TopicPageMetadata(
            topicID: topicID(answerFields: answerFields, searchFields: searchFields, pageURL: pageURL),
            title: title(in: body),
            currentPage: HFRURL.page(in: pageURL) ?? 1,
            maxPage: maxPage(in: body),
            answerFormURL: answerFormURL(in: body),
            answerFormFields: answerFields,
            isUnreadable: body.firstDescendant(attribute: "href", matching: .contains("nonlu")) != nil,
            hasPoll: body.firstDescendant(matching: .exact("sondage")) != nil,
            searchFormFields: searchFields
        )
    }

    // MARK: - Implementation

    /// Inputs legacy kept from the in-topic search form (`ObjCTopicPageWorker.m:166-179`).
    private static let searchFieldNames: Set<String> = [
        "hash_check", "p", "post", "cat", "firstnum", "currentnum", "word", "spseudo", "filter"
    ]

    /// Text of the first `h3` of the title row, trimmed (`ParseMessagesOperation.m:491-495`, `Common.swift:1814-1819`).
    private static func title(in body: Element) -> String {
        guard
            let row = body.firstDescendant(matching: .contains("fondForum2Title")),
            let heading = try? row.getElementsByTag("h3").first(),
            let text = try? heading.text()
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Highest page number printed in the pager's `left` block; 1 when there is none (`ParseMessagesOperation.m:498-507`).
    ///
    /// Legacy read the last child of the block (a link, or `<b>` on the last page). Taking the highest number among the
    /// children gives the same page on every capture and ignores a trailing node that is not a number.
    private static func maxPage(in body: Element) -> Int {
        guard
            let pager = body.firstDescendant(matching: .contains("fondForum2PagesHaut")),
            let block = pager.firstDescendant(matching: .exact("left"))
        else { return 1 }
        let numbers = block.children().array().compactMap { child in
            (try? child.text()).flatMap { HFRURL.positiveInteger($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return max(numbers.max() ?? 1, 1)
    }

    /// Absolute URL of the first link of `#repondre_form`, restricted to `https://forum.hardware.fr` because the session
    /// requests it (`ObjCTopicPageWorker.m:156-157,142-144`).
    private static func answerFormURL(in body: Element) -> URL? {
        guard
            let form = body.firstDescendant(attribute: "id", matching: .exact("repondre_form")),
            let link = try? form.getElementsByTag("a").first(),
            link.hasAttr("href"),
            let href = try? link.attr("href"),
            let url = HFRURL.absolute(href),
            url.scheme == "https",
            url.host(percentEncoded: false) == HFRURL.forumHost
        else { return nil }
        return url
    }

    /// Hidden inputs (`name` and `value` both present) of the element named `hop`; a repeated name keeps the last value.
    private static func answerFormFields(in body: Element) -> [String: String] {
        guard let form = body.firstDescendant(attribute: "name", matching: .exact("hop")) else { return [:] }
        var fields: [String: String] = [:]
        for input in form.descendants(attribute: "type", matching: .contains("hidden")) {
            if let (name, value) = nameAndValue(of: input) {
                fields[name] = value
            }
        }
        return fields
    }

    /// Kept inputs of the form posting to `/transsearch.php`; nil when the page has none.
    ///
    /// A checkbox counts only when `checked`; legacy compared the attribute to the text `checked`, any value of the
    /// attribute counts here and the type is case-insensitive, as in HTML. No capture shows a checked box (pending capture).
    private static func searchFormFields(in body: Element) -> [String: String]? {
        guard let form = body.firstDescendant(attribute: "action", matching: .exact("/transsearch.php")) else { return nil }
        var fields: [String: String] = [:]
        for input in (try? form.getElementsByTag("input").array()) ?? [] {
            guard let (name, value) = nameAndValue(of: input), searchFieldNames.contains(name) else { continue }
            if isCheckbox(input), !input.hasAttr("checked") { continue }
            fields[name] = value
        }
        return fields
    }

    /// HTML input types are case-insensitive (`TYPE="CHECKBOX"`); legacy compared the exact text.
    private static func isCheckbox(_ input: Element) -> Bool {
        input.hasAttr("type") && (try? input.attr("type"))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "checkbox"
    }

    private static func nameAndValue(of input: Element) -> (String, String)? {
        guard input.hasAttr("name"), input.hasAttr("value"), let name = try? input.attr("name"), let value = try? input.attr("value") else {
            return nil
        }
        return (name, value)
    }

    /// `cat` and `post` of the quick-answer form, else of the search form, else of the page URL (`cat=` and `post=` query).
    ///
    /// Legacy took the category from the quick-answer form only, which is empty on a logged out page and on a conversation
    /// whose reply form is gone (`RU2`): the search form and the URL still carry both numbers.
    private static func topicID(answerFields: [String: String], searchFields: [String: String]?, pageURL: String) -> TopicID? {
        for fields in [answerFields, searchFields ?? [:]] {
            if let cat = fields["cat"].flatMap(CategoryID.init(queryValue:)),
               let topic = fields["post"].flatMap(HFRURL.positiveInteger) {
                return TopicID(category: cat, topic: topic)
            }
        }
        return HFRURL.topicID(in: pageURL)
    }
}
