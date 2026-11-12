import HFRNetwork

/// The part of an `AQNewReport` a check refused (see `AQCreateError.invalidReport`).
public enum AQReportField: Sendable, Equatable {
    case existingAlertID, title, topicID, topicTitle, pseudo, postID, postURL, comment
}

/// Why a report was refused before anything was sent.
public enum AQReportProblem: Sendable, Equatable {
    /// Empty, blank or the string `0` (the server tests `empty()`, so `0` counts as missing).
    case missing(AQReportField)
    /// Over the column size of the AQ database (`nom`, `topic_titre`, `post_url` 512, `pseudo` 128, `commentaire` 1024).
    case tooLong(AQReportField)
    /// A character outside the Basic Multilingual Plane (most emoji): refused (`-1`) or turned into `?` by the server.
    case unsupportedCharacters(AQReportField)
    /// A number that is not positive or over `int(11)`.
    case outOfRange(AQReportField)
    /// `post_url` is not a permalink on `https://forum.hardware.fr`: the server answers 403 and may ban the client.
    case notForumPermalink
}

/// What is known when a create may have reached the AQ server but was not confirmed.
public enum AQCreateUncertainty: Sendable, Equatable {
    /// The exchange failed after the request was handed to the network (timeout, lost connection, cancellation).
    case transport(NetworkError)
    /// The host answered a redirect; it is not followed.
    case redirected(statusCode: Int)
    /// Any answer but status 200 with the body `1`. `code` is the trimmed body when it is a bare number (`-2`, `-3`, `-4`
    /// on a local instance, HFR-PROTOCOL §6c LOT-055), else nil (empty body, a page): none is captured on the live host,
    /// so none is read as a refusal either.
    case unrecognizedAnswer(statusCode: Int, code: String?)
}

/// Why an AQ create did not succeed. Never retried by the client.
public enum AQCreateError: Error, Sendable, Equatable {
    /// The injected base URL is not an acceptable AQ origin.
    case invalidBaseURL
    /// Nothing was sent: the report cannot be accepted by the server as it is.
    case invalidReport(AQReportProblem)
    /// The task was cancelled before the request was handed to the network: nothing was sent, the user may try again.
    case cancelled
    /// The report may have been recorded; the app must not resend it on its own (check `alerts(topicID:)` first).
    case unconfirmed(AQCreateUncertainty)
}
