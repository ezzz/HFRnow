/// The `display_images` setting: when images of messages are loaded. Raw values are the legacy defaults strings.
public enum ImageDisplayMode: String, Sendable, Codable, CaseIterable {
    /// Always.
    case always = "yes"
    /// Never.
    case never = "no"
    /// Only on Wi-Fi.
    case wifiOnly = "wifi"
}
