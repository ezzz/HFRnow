import Foundation

/// A fetched page before any parsing: decoded text plus what the parsers and callers need to interpret it.
public struct RawPage: Sendable, Equatable {
    /// The body decoded with `TextDecoding` (never fails; see `encoding`).
    public let text: String
    /// How the bytes were interpreted.
    public let encoding: DecodedText.Encoding
    /// Charset declared by the server (`Content-Type`) or, failing that, a `<meta>` tag, lowercased; nil when undeclared.
    public let declaredCharset: String?
    /// URL that produced the body, after any followed redirect (the canonical page URL for a topic, HFR-PROTOCOL R5).
    public let finalURL: URL
    /// Status of the final answer (below 400: 4xx/5xx are thrown as `NetworkError.httpStatus`).
    public let statusCode: Int

    /// Creates a raw page.
    public init(text: String, encoding: DecodedText.Encoding, declaredCharset: String?, finalURL: URL, statusCode: Int) {
        self.text = text
        self.encoding = encoding
        self.declaredCharset = declaredCharset
        self.finalURL = finalURL
        self.statusCode = statusCode
    }

    /// Decodes a transport answer.
    public init(response: HTTPResponse) {
        let contentType = response.headers["Content-Type"]
        let decoded = TextDecoding.decode(response.body, contentType: contentType)
        self.init(
            text: decoded.text,
            encoding: decoded.encoding,
            declaredCharset: contentType.flatMap(TextDecoding.charset(fromContentType:))
                ?? TextDecoding.sniffMetaCharset(in: response.body),
            finalURL: response.url,
            statusCode: response.statusCode
        )
    }
}
