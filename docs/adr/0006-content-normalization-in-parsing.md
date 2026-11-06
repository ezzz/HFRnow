# 0006 — Message content normalization lives in HFRParsing, display-independent

**Status:** Accepted — 2026-10-24 (maintainer, after the LOT-000 reviews)

## Context
Message content must be rewritten before display: smileys, images (incl. rehost rewrites), relative links, signature split, code blocks, spoilers, video embeds (audit C §4).
The legacy app does this with regexes over libxml2's serialized HTML, which is fragile, and inserts some values unescaped into a `WKWebView` that has file read access (C §5.2, C 6.3).
DOM-level work needs an HTML parser, and ADR 0002 confines SwiftSoup to `HFRParsing`.

Options considered:
1. **Normalize in `HFRParsing`, display-independent**: the parser emits normalized, sanitized content HTML plus typed lists (images, smileys, links, embeds, quotes, spoilers, signature). Display choices are applied later by the app's HTML builder on those lists.
2. Normalize in `HFRParsing` driven by display options (`MessageRenderOptions`). Rejected: every settings change would require re-parsing, and oracle comparisons would depend on settings.
3. A typed content AST (text, image, smiley, link, quote, spoiler, code blocks) rendered by the app. Best testability and removes HTML string handling entirely, but means rewriting ~1,077 lines of tuned CSS-driven rendering. Rejected for now; can supersede this ADR later.
4. Relax ADR 0002 so the app uses SwiftSoup. Rejected: spreads the riskiest dependency.
5. Keep regex rewriting app-side. Rejected: it is the source of the legacy bugs.

## Decision
Option 1.
- **Output contract**: per message, normalized content HTML + typed lists; legacy CSS class names that the stylesheet relies on (`citation`, `oldcitation`, `messCase2`, `signature`, `masque`, …) are part of the contract.
- **Sanitization contract**: `HFRParsing` is the sanitizer of record. Allow-list of tags and attributes; all event-handler attributes (`on*`) and `javascript:` URLs removed; every value the app injects (pseudo, date, labels) is escaped by the HTML builder.
- **Policy stays out**: blacklist, whitelist and filters are applied app-side on parsed messages.
- `MessageRenderOptions` is dropped from `HFRModels` unless a genuinely parse-time option appears.

## Consequences
- SwiftSoup stays confined; the riskiest transformations are Linux-testable against fixtures, independent of user settings.
- The app's HTML builder (Phase 4 backlog C12) applies image mode, embed mode, signature visibility from the typed lists without re-parsing.
- A sanitization test suite (malicious `onclick`, `javascript:` links, injected pseudos) is part of LOT-034.

## Amendment 1 — 2026-10-24: URL schemes in typed outputs

Raised by the CodeRabbit review of PR #8 (CWE-79). It tightens the sanitization contract and does not change the decision.

- Every URL the parser emits — in normalized HTML (`href`, `src`) **and** in the typed lists (links, images, embeds) — is resolved against the forum base URL and kept only if its scheme is `https` or `http`. `http` is upgraded to `https` where the host supports it. `javascript:`, `data:`, `file:`, `blob:` and any other scheme are dropped: the link becomes plain text and the image is removed.
- Internal forum links stay absolute `https://forum.hardware.fr/…` URLs; the app routes them itself.
- Embeds are produced only for an allow-list of hosts (YouTube, Vimeo, Streamable at the time of writing), with the embed URL **built** by the parser from the extracted id, never copied from the page.
- The app's HTML builder still escapes every value it injects and treats typed URLs as untrusted input.
- LOT-034 includes tests for each rejected scheme, mixed-case and whitespace-obfuscated variants (`JaVaScRiPt:`, `java\nscript:`), and percent-encoded schemes.
