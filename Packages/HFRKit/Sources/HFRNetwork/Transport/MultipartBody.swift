import Foundation
/// An ordered `multipart/form-data` body (RFC 7578), for the image upload.
public struct MultipartBody: Sendable, Equatable {
    /// One part of the body.
    public enum Part: Sendable, Equatable {
        /// A plain text field.
        case text(name: String, value: String)
        /// A file field with its own file name and media type.
        case file(name: String, filename: String, contentType: String, data: Data)
    }

    /// Delimiter between parts; it must not occur in the parts' bytes (the default is random).
    public let boundary: String
    /// Parts in submission order.
    public let parts: [Part]

    /// Creates a body; pass a fixed `boundary` only in tests.
    public init(boundary: String = "Boundary-\(UUID().uuidString)", parts: [Part]) {
        self.boundary = boundary
        self.parts = parts
    }

    /// `Content-Type` header value that announces the boundary.
    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// The encoded body, with CRLF line ends as the RFC requires.
    public var data: Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            switch part {
            case let .text(name, value):
                body.append(Data("Content-Disposition: form-data; name=\"\(Self.quoted(name))\"\r\n\r\n".utf8))
                body.append(Data(value.utf8))
            case let .file(name, filename, contentType, bytes):
                body.append(Data(
                    "Content-Disposition: form-data; name=\"\(Self.quoted(name))\"; filename=\"\(Self.quoted(filename))\"\r\n".utf8
                ))
                body.append(Data("Content-Type: \(Self.header(contentType))\r\n\r\n".utf8))
                body.append(bytes)
            }
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// Escapes what would end a quoted header value or the header line (the HTML form rule: `"`, CR, LF become `%22`, `%0D`, `%0A`).
    static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    /// A header value on one line: CR and LF dropped so a caller's text cannot start another header.
    private static func header(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }
}
