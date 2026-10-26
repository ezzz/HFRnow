import Foundation

/// A persisted HTTP cookie. HFRModels never uses `HTTPCookie` (not available the same way on Linux);
/// HFRNetwork converts to and from it. The value is a secret: descriptions hide it.
public struct StoredCookie: Sendable, Hashable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Cookie name, e.g. `md_user`.
    public var name: String
    /// Cookie value (a secret for session cookies).
    public var value: String
    /// Domain as the server set it, possibly with a leading dot (`.hardware.fr`).
    public var domain: String
    /// Path scope.
    public var path: String
    /// Expiry; nil for a session cookie.
    public var expiresDate: Date?
    /// Only sent over HTTPS.
    public var isSecure: Bool
    /// Hidden from scripts.
    public var isHTTPOnly: Bool

    /// Identity of a cookie in a jar: name, domain (case-insensitive, leading dot ignored) and path.
    public var jarKey: String {
        var host = domain.lowercased()
        if host.hasPrefix(".") { host.removeFirst() }
        return "\(name)|\(host)|\(path)"
    }

    /// Creates a cookie.
    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresDate: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    /// Description without the value.
    public var description: String { "StoredCookie(\(name) @ \(domain)\(path), value hidden)" }

    /// Same as `description`.
    public var debugDescription: String { description }

    /// Reflection (`dump`, debugger) hides the value too.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "name": name, "value": "<redacted>", "domain": domain, "path": path,
            "expiresDate": expiresDate as Any, "isSecure": isSecure, "isHTTPOnly": isHTTPOnly
        ], displayStyle: .struct)
    }
}
