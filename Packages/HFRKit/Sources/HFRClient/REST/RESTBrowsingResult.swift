import HFRNetwork
import HFRParsing

/// A list read by `RESTBrowsingClient`, and where it came from (LOT-057).
public struct RESTBrowsingResult<Value: Sendable & Equatable>: Sendable, Equatable {
    /// The list, as LOT-010 models.
    public let value: Value
    /// The REST API, or the HTML page the client read after the REST answer failed.
    public let source: RESTBrowsingSource

    /// Creates a result.
    public init(value: Value, source: RESTBrowsingSource) {
        self.value = value
        self.source = source
    }
}

/// Where a `RESTBrowsingResult` came from.
public enum RESTBrowsingSource: Sendable, Equatable {
    /// The REST API's JSON.
    case rest
    /// The list's HTML page, read because the REST answer failed for that reason.
    case html(RESTFallbackReason)
}

/// Why the REST answer was not used.
public enum RESTFallbackReason: Sendable, Equatable {
    /// The request could not be sent, HFR answered an HTTP error or a redirect.
    case network(NetworkError)
    /// The answer is not the JSON expected; the payload names the field.
    case response(ParsingError)
}
