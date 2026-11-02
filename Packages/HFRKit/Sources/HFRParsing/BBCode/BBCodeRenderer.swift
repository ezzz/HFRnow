import Foundation
import HFRModels

/// What HFR's own preview form takes besides the text (`apercu_form`: `apercu_smiley`), plus the smiley codes the
/// renderer may substitute.
public struct BBCodeRenderOptions: Sendable, Hashable {
    /// Whether smiley codes become images: the composer's `smiley` checkbox read as HFR does (checked = disabled,
    /// HFR-PROTOCOL §6b "Checkbox values"), sent to HFR's preview as `apercu_smiley`.
    public var smileysEnabled: Bool
    /// Smiley codes as typed (`:)`, `:ange:`, `[:user]`, `[:user:1]`) and their image URLs: the catalogue of
    /// `CommonSmileyCatalog` plus the member's personal smileys, built by the app. A code is matched whatever its case;
    /// the image's `alt` is the text as typed and its `title` the code of the table (`R20`: `alt=":d" title=":D"`).
    public var smileys: [String: URL]

    /// Creates the options; by default smileys are on, as in a fresh composer, and no code is known.
    public init(smileysEnabled: Bool = true, smileys: [String: URL] = [:]) {
        self.smileysEnabled = smileysEnabled
        self.smileys = smileys
    }
}

/// Renders a message source (BBCode, as the composer sends it) into the `MessageContent` the reader will show once the
/// message is posted (ADR 0014, LOT-097).
///
/// The source becomes the HTML string HFR itself renders for the tags the captured pairs prove (`W61` / `R95d`,
/// `R41a` / `R20`), then goes through `MessageContentNormalizer`, the sanitizer of record: one rendering path, one
/// stylesheet, one image policy for the preview and for posted messages. Everything the pairs do not prove is text,
/// as HFR does with `[color=…]`, `[list]` and an unclosed tag. No I/O, no request: the draft never leaves the device.
public enum BBCodeRenderer {
    /// The content of `source` as the reader will show it. Line breaks are read as the posting flow sends them (CRLF,
    /// whatever the source holds); characters above U+FFFF are text (the posting flow refuses them before sending).
    /// `page` resolves relative links as the reader will, against the topic page the message is posted to.
    /// Only a backend failure throws.
    public static func render(
        _ source: String, options: BBCodeRenderOptions = BBCodeRenderOptions(), relativeTo page: URL = HFRURL.base
    ) throws(ParsingError) -> MessageContent {
        let writer = HFRBBCodeWriter(smileysEnabled: options.smileysEnabled, smileys: options.smileys)
        return try MessageContentNormalizer.normalize(contentHTML: writer.html(for: source), relativeTo: page)
    }
}
