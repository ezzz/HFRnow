import Foundation
import HFRModels

/// The client-side multi-quote selection of one topic, as the site's `quoter()` JavaScript keeps it in a cookie.
///
/// Name `quotes<forum>-<cat>-<post>` (e.g. `quoteshardwarefr-13-42`), value the concatenated `|<numreponse>` markers,
/// domain `.hardware.fr`, path `/`, one hour of life, deleted when empty (HFR-PROTOCOL §4; legacy
/// `MessagesView.swift:1852-1945`). Markers are compared **exactly**: legacy used `contains("|\(id)")` and
/// `replacingOccurrences`, so `|12` counted as selecting `1` and unselecting `1` turned `|12|1` into `2`.
public struct MultiQuoteCookie: Sendable, Equatable {
    /// Domain the site's JavaScript writes the cookie for.
    public static let domain = ".hardware.fr"
    /// Path of the cookie.
    public static let path = "/"
    /// Lifetime given on every write, in seconds (legacy `Date().addingTimeInterval(60 * 60)`).
    public static let lifetime: TimeInterval = 60 * 60
    /// Prefix shared by every multi-quote cookie name.
    public static let namePrefix = "quotes"

    /// Cookie name for the topic of `token`.
    public let name: String
    /// Selected markers in selection order, without the `|` separators; normally decimal `numreponse` values.
    public private(set) var markers: [String]

    /// The cookie name for the topic `token` belongs to: `quotes<forum>-<cat>-<post>`.
    public static func name(for token: QuoteSelectionToken) -> String {
        "\(namePrefix)\(token.forum)-\(token.topic.category.queryValue)-\(token.topic.topic)"
    }

    /// An empty selection for the topic of `token`.
    public init(token: QuoteSelectionToken) {
        self.init(name: Self.name(for: token), value: "")
    }

    /// A selection read from a cookie `value` such as `|12|1`; empty segments are dropped.
    public init(name: String, value: String) {
        self.name = name
        self.markers = value.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
    }

    /// The cookie value, `|<marker>` repeated in selection order; empty when nothing is selected.
    public var value: String {
        markers.map { "|" + $0 }.joined()
    }

    /// True when nothing is selected (the cookie must then be deleted).
    public var isEmpty: Bool { markers.isEmpty }

    /// The selected message numbers in selection order; markers that are not decimal numbers are skipped.
    public var selectedNumbers: [Int] {
        markers.compactMap { marker in
            marker.utf8.allSatisfy { (48...57).contains($0) } ? Int(marker) : nil
        }
    }

    /// True when message `numreponse` is selected (exact match).
    public func contains(_ numreponse: Int) -> Bool {
        markers.contains(String(numreponse))
    }

    /// Selects `numreponse` (appended last) or unselects it (every exact occurrence removed); returns the new state.
    @discardableResult
    public mutating func toggle(_ numreponse: Int) -> Bool {
        let marker = String(numreponse)
        if markers.contains(marker) {
            markers.removeAll { $0 == marker }
            return false
        }
        markers.append(marker)
        return true
    }

    /// The cookie to store, expiring `lifetime` after `now`; nil when the selection is empty (delete instead).
    public func storedCookie(now: Date) -> StoredCookie? {
        guard !isEmpty else { return nil }
        return StoredCookie(
            name: name, value: value, domain: Self.domain, path: Self.path,
            expiresDate: now.addingTimeInterval(Self.lifetime)
        )
    }
}
