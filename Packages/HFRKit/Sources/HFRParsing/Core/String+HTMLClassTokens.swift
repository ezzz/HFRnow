extension StringProtocol {
    /// Class tokens as HTML splits them: on ASCII whitespace only (space, tab, LF, CR, form feed),
    /// so U+00A0 and other Unicode spaces stay inside a token.
    var htmlClassTokens: [SubSequence] {
        split(whereSeparator: \.isHTMLWhitespace)
    }

    /// The value without leading and trailing ASCII whitespace (the HTML definition).
    var trimmingHTMLWhitespace: SubSequence {
        guard
            let first = firstIndex(where: { !$0.isHTMLWhitespace }),
            let last = lastIndex(where: { !$0.isHTMLWhitespace })
        else { return self[endIndex...] }
        return self[first...last]
    }
}

extension Character {
    /// HTML "ASCII whitespace"; checked per scalar because `\r\n` is a single `Character`.
    var isHTMLWhitespace: Bool {
        unicodeScalars.allSatisfy { [" ", "\t", "\n", "\r", "\u{0C}"].contains($0) }
    }
}
