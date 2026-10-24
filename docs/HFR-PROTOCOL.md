# HFR protocol reference

Everything we know about how forum.hardware.fr works: URLs, query parameters, forms, cookies, HTML structure.
**Every entry cites its source** (legacy file:line or fixture). No undocumented assumptions.

Filled during Phase 1 (audit) and every lot.

## Known so far

### Multi-quote selection cookie
- Name: `quotes{a}-{b}-{c}`, built from the first three arguments of the `quoteJS` call in a message; value: `|{postID}` concatenated per selected message; domain `.hardware.fr`, path `/`, 1 h lifetime.
- Source: legacy `HFRswift/Swift/MessagesView.swift` (`quoteComponents`, `toggleQuoteSelection`).
- The quote URL of any selected message returns all selected messages when this cookie is sent.
