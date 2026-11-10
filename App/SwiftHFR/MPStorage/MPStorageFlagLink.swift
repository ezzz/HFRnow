import HFRModels

/// The link of an MPStorage read position (LOT-130): legacy `getUrlFlagForTopidId:` (`Classes/MPStorage.m:527-545`, URL at
/// `:539` @ 87fe0d1c), as a forum path. `p` defaults to `1` as the legacy reader wrote it (`MessagesView.swift:3594`).
enum MPStorageFlagLink {
    /// The path of `flag`; nil without a page (legacy's link would hold `(null)`) or with a conversation number below 1.
    /// Values written by other clients are kept only when they cannot add query keys or leave the fragment: `p` must be
    /// digits (else `1`), `href` letters and digits (else no anchor).
    static func path(of flag: MPStorageMPFlag) -> String? {
        guard flag.topic > 0, let page = flag.page, page > 0 else { return nil }
        let pValue = flag.pValue.flatMap { value in value.isEmpty || !value.allSatisfy(\.isASCIIDigit) ? nil : value } ?? "1"
        var path = "/forum2.php?config=hfr.inc&cat=prive&post=\(flag.topic)&page=\(page)&p=\(pValue)&sondage=0&owntopic=0&trash=0"
            + "&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0"
        if let href = flag.href, !href.isEmpty, href.allSatisfy({ $0.isASCIIDigit || $0.isASCIILetter }) {
            path += "#\(href)"
        }
        return path
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
