import Foundation
import HFRModels

/// The account's flag on a topic, as the function bar of a logged-in topic page shows it (#306).
///
/// The bar holds one `a.cHeader` to `/user/delflag.php?…` whose icon tells the flag (`R21`, `R33b`, `P03m`); following the
/// link removes the flag (`TopicFlagFlow.removeFlag(link:in:)`, LOT-051). The link carries no token.
public struct TopicPageFlag: Sendable, Hashable {
    /// The flag from the icon's file name: `flagn0.gif` read (`.red`), `flagn1.gif` participated (`.blue`), `favorisn.gif`
    /// favourite (`.yellow`); nil for another icon.
    public var flag: TopicFlag?
    /// The `delflag.php` link, absolute on `https://forum.hardware.fr`, with the parameters HFR printed.
    public var removalURL: URL

    /// Creates a value; used by the parser and by tests.
    public init(flag: TopicFlag?, removalURL: URL) {
        self.flag = flag
        self.removalURL = removalURL
    }
}
