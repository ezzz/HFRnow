import Foundation
import HFRModels
import HFRNetwork

/// Validates an `AQNewReport` against what the AQ database accepts and builds the `addAlerte.php` form.
///
/// Facts: HFR-PROTOCOL §6c LOT-055 ("Create request", "Values the database refuses", `T72`-`T90`): a value over its column, a
/// character outside the BMP or a number out of range gets `-1` under a strict `sql_mode` and is silently cut, zeroed or
/// turned into `?` without it, and the live mode is unknown, so such a report is refused here.
enum AQReportEncoder {
    /// Sent as `from`: a client name the server logs (decided by the operator, #573).
    static let clientName = "SwiftHFR"
    static let forumPrefix = "https://forum.hardware.fr"
    private static let limits: [AQReportField: Int] = [.title: 512, .topicTitle: 512, .postURL: 512, .pseudo: 128, .comment: 1024]
    private static let maxInt11 = Int(Int32.max)

    static func form(for report: AQNewReport) throws(AQCreateError) -> FormBody {
        let isAddition = report.existingAlertID != nil
        var form = FormBody()
        if let id = report.existingAlertID {
            try number(id, .existingAlertID)
            form.append("alerte_qualitay_id", String(id))
        } else {
            form.append("alerte_qualitay_id", "-1")
        }
        if !isAddition {
            // An addition keeps the AQ's own values and ignores these (toyo@96c0aea:api/addAlerte.php:104-107).
            form.append("nom", try text(report.title, .title, required: true))
            try number(report.topicID, .topicID)
            form.append("topic_id", String(report.topicID))
            form.append("topic_titre", try text(report.topicTitle, .topicTitle, required: true))
        }
        // Legacy lower-cases the pseudo (`MessagesView.swift:439-441` @ 2440d79); the unique keys ignore case anyway.
        // Lower-cased first: it can add scalars, and the 128 limit applies to what is sent.
        form.append("pseudo", try text(report.pseudo.lowercased(), .pseudo, required: true))
        try number(report.postID, .postID)
        form.append("post_id", String(report.postID))
        let url = report.postURL.absoluteString
        guard url.hasPrefix(forumPrefix) else { throw .invalidReport(.notForumPermalink) }
        form.append("post_url", try text(url, .postURL, required: true))
        form.append("commentaire", try text(report.comment, .comment, required: false))
        form.append("from", clientName)
        return form
    }

    private static func number(_ value: Int, _ field: AQReportField) throws(AQCreateError) {
        guard value > 0, value <= maxInt11 else { throw .invalidReport(.outOfRange(field)) }
    }

    private static func text(_ value: String, _ field: AQReportField, required: Bool) throws(AQCreateError) -> String {
        if required, value == "0" || value.allSatisfy(\.isWhitespace) { throw .invalidReport(.missing(field)) }
        // Counted in scalars: past the BMP is refused below, so a scalar is one database character.
        if let limit = limits[field], value.unicodeScalars.count > limit { throw .invalidReport(.tooLong(field)) }
        if value.unicodeScalars.contains(where: { $0.value > 0xFFFF }) { throw .invalidReport(.unsupportedCharacters(field)) }
        return value
    }
}
