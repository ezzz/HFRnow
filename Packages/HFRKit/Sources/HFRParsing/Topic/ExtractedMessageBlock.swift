import SwiftSoup

/// A `MessageBlock` together with the DOM elements it was read from, for the stages that keep working on the
/// same tree inside HFRParsing (LOT-031 reads the toolbar links, LOT-032 the quotes, LOT-034 the content).
/// Internal: SwiftSoup never leaves the module (ADR 0002).
struct ExtractedMessageBlock {
    /// The facts read from the block.
    let block: MessageBlock
    /// The `table.messagetable` element.
    let table: Element
    /// The content element (`div#para<numreponse>`), whose inner HTML is `block.contentHTML`.
    let content: Element
    /// The `div.toolbar` of the block (date and action links), when present.
    let toolbar: Element?
    /// The `div.edited` trailer, when present.
    let edited: Element?
}
