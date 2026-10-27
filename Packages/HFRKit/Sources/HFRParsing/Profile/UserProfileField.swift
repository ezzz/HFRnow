import Foundation

/// One labelled row of a public profile (`td.profilCase2` label, `td.profilCase3` value).
public struct UserProfileField: Sendable, Hashable, Identifiable {
    /// Opaque stable key `field|<section title>|<title>`; two rows with the same title in one section share it (as in legacy).
    public var id: String
    /// Label without its trailing colon and spacing, e.g. `Date de naissance`.
    public var title: String
    /// Value as printed, whitespace normalized; empty when the page prints nothing or only `&nbsp;`.
    public var value: String
    /// First link of the value cell as an absolute `http(s)` URL; nil when there is none or it uses another scheme.
    ///
    /// Member-supplied and external (a website, anything): never request it with the session, open it in the browser only.
    public var url: URL?

    /// True when the page prints no value. Legacy replaced the empty value by the French text "Non renseigné";
    /// the wording is a display choice and belongs to the app.
    public var isPlaceholder: Bool { value.isEmpty }

    /// Creates a value; used by the parser and by tests.
    public init(id: String, title: String, value: String, url: URL? = nil) {
        self.id = id
        self.title = title
        self.value = value
        self.url = url
    }
}
