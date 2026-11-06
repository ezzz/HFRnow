import Foundation
import HFRModels
import SwiftSoup

/// Reads the existing AQs of a topic (`GET https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=<topic>`, capture `T02`).
///
/// The answer is XML (`text/xml`), not JSON: `<alertes><alerte id nom pseudoInitiateur date postsIds/>…</alertes>`, newest first
/// (HFR-PROTOCOL §8). Legacy has no parser: it only tests that the answer contains the message number
/// (`MessagesView.swift`, `isAQAlreadySignaled`, `content.contains(postID)`);
/// `isReported(postID:in:)` is that question answered on the parsed list.
public enum AQAlertListParser {
    /// Alerts in the order served; an `<alertes/>` with no child is an empty list.
    ///
    /// Attribute values are entity-decoded by the XML reader (`nom="&quot;x&quot;"` gives `"x"`) and otherwise kept as served
    /// (trailing spaces of `nom` included, repeated numbers of `postsIds` included).
    /// - Throws: `missingElement` when the root is not `<alertes>`; `missingAttribute` / `invalidValue` when an `<alerte>` lacks one of its
    ///   five attributes or one is not of the captured shape (`id` and each `postsIds` entry positive integers, `date` as `dd-MM-yyyy`).
    public static func parse(_ xml: String) throws(ParsingError) -> [AQAlert] {
        let document = try AQXMLDocument.document(from: xml)
        let records: Elements
        do {
            guard try !document.select("alertes").isEmpty() else { throw ParsingError.missingElement("alertes") }
            records = try document.select("alertes > alerte")
        } catch let error as ParsingError {
            throw error
        } catch {
            throw .malformedDocument
        }
        var alerts: [AQAlert] = []
        for record in records.array() {
            alerts.append(try alert(from: record))
        }
        return alerts
    }

    /// Whether any alert of the list already holds the message, the question legacy asked with a substring test.
    public static func isReported(postID: Int, in alerts: [AQAlert]) -> Bool {
        alerts.contains { $0.postIDs.contains(postID) }
    }

    // MARK: - Implementation

    private static func alert(from record: Element) throws(ParsingError) -> AQAlert {
        let identifier = try positiveInteger(try attribute("id", of: record), field: "id")
        let posts = try attribute("postsIds", of: record)
        var postIDs: [Int] = []
        for part in posts.split(separator: ",", omittingEmptySubsequences: false) {
            postIDs.append(try positiveInteger(String(part), field: "postsIds"))
        }
        let date = try attribute("date", of: record)
        guard date.wholeMatch(of: /[0-9]{2}-[0-9]{2}-[0-9]{4}/) != nil else { throw .invalidValue(field: "date") }
        return AQAlert(
            id: identifier,
            title: try attribute("nom", of: record),
            initiator: try attribute("pseudoInitiateur", of: record),
            dateText: date,
            postIDs: postIDs
        )
    }

    private static func attribute(_ name: String, of element: Element) throws(ParsingError) -> String {
        guard element.hasAttr(name), let value = try? element.attr(name) else {
            throw .missingAttribute(element: "alerte", attribute: name)
        }
        return value
    }

    private static func positiveInteger(_ text: String, field: String) throws(ParsingError) -> Int {
        guard text.wholeMatch(of: /[0-9]+/) != nil, let value = Int(text), value > 0 else { throw .invalidValue(field: field) }
        return value
    }
}
