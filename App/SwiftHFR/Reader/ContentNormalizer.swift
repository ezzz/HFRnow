import Foundation
import HFRModels
import HFRParsing

/// The app's normalizer. TEMPORARY until LOT-034 (ezzz/HFRnow#23) is on `dev-swift`: the raw content is escaped and shown
/// as text, so nothing from the page is ever inserted as markup. Replaced by `MessageContentNormalizer` when #23 lands.
struct ContentNormalizer: MessageContentNormalizing {
    func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
        MessageContent(html: "<p>" + HTMLEscaping.text(contentHTML) + "</p>")
    }
}
