import Foundation
import HFRModels

/// Where an image URL points, for the loading policy C of the reader (LOT-071 decision D-071-1).
enum ImageOrigin: Equatable, Sendable {
    /// HFR's own images (smileys, avatars, `forum-images.hardware.fr`): first-party, loaded normally.
    case forum
    /// Any other public host: loaded on tap, or automatically when the image setting allows it.
    case thirdParty
    /// Never requested, whatever the setting or a tap; shown as a link instead.
    case blocked(ImageBlockReason)
}

/// Why an image URL is never requested.
enum ImageBlockReason: Equatable, Sendable {
    /// Not an `http(s)` URL, or a URL with user info.
    case scheme
    /// A host the policy cannot read safely: empty label, percent-encoding, characters outside `[a-z0-9.-]`.
    case malformedHost
    /// An IP literal in a private, loopback, link-local, shared, multicast or reserved range, or any IPv6 literal.
    case privateAddress
    /// A host whose labels are all numbers but that is not a canonical dotted quad (`0xC0.0xA8.1.1`, `0300.0250.1.1`,
    /// `192.168.1`): Foundation keeps the text as is and the system resolver reads it as an address.
    case numericHost
    /// A name without a dot (`localhost`, `3232235777`, `router`) or a local-network name (`.local`, `.home.arpa`).
    case localName
    /// A `*.hardware.fr` URL that is not an image path (`/user/logout.php`): never fetched, even cookie-less.
    case forumNonImage
}

/// Policy C, point 1 and 3 (LOT-071 D-071-1): classifies an image URL by its shape, before any request.
///
/// Numeric spellings are rejected by shape, never by matching their text against the ranges: only a canonical dotted
/// quad of four decimal labels is read as an address and checked against the ranges.
enum ImagePolicy {
    /// The forum's image host (smileys, avatars, personal smileys).
    static let forumImageHost = "forum-images.hardware.fr"
    /// Path extensions a `*.hardware.fr` image may have outside `forum-images.hardware.fr`.
    static let imageExtensions: Set<String> = ["gif", "png", "jpg", "jpeg", "webp", "svg"]
    /// Suffixes of names that only resolve on a local network.
    static let localSuffixes = [".local", ".localhost", ".home.arpa", ".internal", ".lan"]

    /// The origin of `url`.
    static func classify(_ url: URL) -> ImageOrigin {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.user() == nil, url.password() == nil else { return .blocked(.scheme) }
        guard let rawHost = url.host(percentEncoded: true), !rawHost.isEmpty else { return .blocked(.malformedHost) }
        // Any colon is an IPv6 literal (Foundation drops the brackets). Every one is refused: mapped, NAT64 and 6to4 forms
        // embed IPv4 private addresses, and zone ids name local interfaces, so range matching would be error-prone.
        if rawHost.contains(":") { return .blocked(.privateAddress) }
        var host = rawHost.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.utf8.allSatisfy(isHostByte) else { return .blocked(.malformedHost) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.contains(where: \.isEmpty) else { return .blocked(.malformedHost) }
        if labels.allSatisfy(isNumericLabel) {
            guard let address = canonicalIPv4(labels) else { return .blocked(.numericHost) }
            return isPublic(address) ? .thirdParty : .blocked(.privateAddress)
        }
        guard labels.count > 1, host != "localhost", !localSuffixes.contains(where: host.hasSuffix) else {
            return .blocked(.localName)
        }
        if host == "hardware.fr" || host.hasSuffix(".hardware.fr") {
            if host == forumImageHost { return .forum }
            return imageExtensions.contains(url.pathExtension.lowercased()) ? .forum : .blocked(.forumNonImage)
        }
        return .thirdParty
    }

    /// `[a-z0-9.-]` (after lowercasing): no percent-encoding, no Unicode, no `_` tricks.
    private static func isHostByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (97...122).contains(byte) || byte == 46 || byte == 45
    }

    /// A label an IPv4 parser (`inet_aton`) may read as a number: decimal, octal (leading zero) or `0x` hexadecimal.
    private static func isNumericLabel(_ label: Substring) -> Bool {
        if label.hasPrefix("0x") {
            return label.dropFirst(2).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
        return label.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// Four decimal labels 0–255 without a leading zero, as an integer; nil for any other numeric spelling.
    private static func canonicalIPv4(_ labels: [Substring]) -> UInt32? {
        guard labels.count == 4 else { return nil }
        var address: UInt32 = 0
        for label in labels {
            guard label.count <= 3, label == "0" || !label.hasPrefix("0"),
                  label.utf8.allSatisfy({ (48...57).contains($0) }), let value = UInt32(label), value <= 255 else { return nil }
            address = address << 8 | value
        }
        return address
    }

    /// Ranges that never reach a public image host (RFC 6890 special-purpose blocks).
    private static let nonPublicRanges: [(base: UInt32, prefix: UInt32)] = [
        (0x0000_0000, 8),   // 0/8, "this network", 0.0.0.0 included
        (0x0A00_0000, 8),   // 10/8
        (0x6440_0000, 10),  // 100.64/10, shared address space
        (0x7F00_0000, 8),   // 127/8, loopback
        (0xA9FE_0000, 16),  // 169.254/16, link-local
        (0xAC10_0000, 12),  // 172.16/12
        (0xC000_0000, 24),  // 192.0.0/24, IETF protocol assignments
        (0xC0A8_0000, 16),  // 192.168/16
        (0xC612_0000, 15),  // 198.18/15, benchmarking
        (0xE000_0000, 4),   // 224/4, multicast
        (0xF000_0000, 4)    // 240/4, reserved and broadcast
    ]

    private static func isPublic(_ address: UInt32) -> Bool {
        !nonPublicRanges.contains { range in
            let mask: UInt32 = range.prefix == 0 ? 0 : ~UInt32(0) << (32 - range.prefix)
            return address & mask == range.base
        }
    }
}

/// When third-party images load by themselves: policy C, point 2, from the `display_images` setting (FEAT-011).
enum ImageAutoLoad: Equatable, Sendable {
    /// Third-party images wait for a tap.
    case onTap
    /// Third-party images load by themselves on Wi-Fi (or Ethernet), on tap otherwise.
    case onWiFi
    /// Third-party images load by themselves.
    case always

    /// The mode for a stored setting value; nil (no value stored yet) gives the reader's default, Wi-Fi only.
    /// Legacy's "never" becomes the tap-to-load placeholder.
    init(setting: ImageDisplayMode?) {
        switch setting {
        case .always: self = .always
        case .never: self = .onTap
        case .wifiOnly, nil: self = .onWiFi
        }
    }

    /// Whether a third-party image loads without a tap, given the current network.
    func loadsThirdPartyImages(onWiFi: Bool) -> Bool {
        switch self {
        case .onTap: false
        case .onWiFi: onWiFi
        case .always: true
        }
    }
}

/// What the page does with one image.
enum ImageDecision: String, Equatable, Sendable {
    /// Request it now (through the cookie-less client).
    case load
    /// Show a tap-to-load placeholder; nothing is requested before the tap.
    case tap
    /// Never request it; show its URL as a link.
    case block

    /// The decision for `origin`; `tapped` is the reader's explicit request for this image.
    init(origin: ImageOrigin, autoLoadsThirdParty: Bool, tapped: Bool = false) {
        switch origin {
        case .blocked: self = .block
        case .forum: self = .load
        case .thirdParty: self = autoLoadsThirdParty || tapped ? .load : .tap
        }
    }
}
