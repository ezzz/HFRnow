# LOT-056 — Image hosts: rehost client and host adapter table

- **Module:** HFRNetwork
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#82](https://github.com/ezzz/HFRnow/issues/82) (old, frozen: [francoisgn/ios-app_SwiftHFR#84](https://github.com/francoisgn/ios-app_SwiftHFR/issues/84))
- **Inputs:** [LOT-071](LOT-071-third-party-services.md) (T4, R1-R3, D-071-1 point 4, N1) · [ADR 0007](../adr/0007-third-party-api-keys.md) ·
  [HFR-PROTOCOL §7 E26](../HFR-PROTOCOL.md#7-reported-by-redface2-to-verify-with-our-fixtures) · audit [D](../audit/D-posting.md) §3.2 ·
  [LOT-012](LOT-012-form-write-models.md) `RehostedImage`

## Legacy sources

Lines are those of <https://github.com/francoisgn/hfrnow> @ `2440d79`, the revision LOT-071 and the brief cite (`master` of ezzz/HFRnow has
drifted: its `ReplyService.swift` is about 40 lines longer). Only the `Referer` rule is also quoted at its `master` position.

| Concern | Legacy |
|---|---|
| Upload endpoint, key in the query | `HFRswift/Swift/ReplyService.swift:1970` (`https://img3.super-h.fr/api/1/upload/?key=…`; the key literal at `:1963` is deliberately not copied, ADR 0007) |
| Cookie-less session, 60 s, JPEG | `ReplyService.swift:1972-1997` (`httpCookieAcceptPolicy = .never` at `:1976`, `httpShouldSetCookies = false`, `timeoutInterval = 60` at `:1992`, quality 1.0 at `:1984`, file name `snapshot_<random>.jpg` at `:1997`) |
| Multipart body | `ReplyService.swift:2045-2060` (`imageCaption` = `Some Caption`, then `source` with `Content-Type: image/jpeg`) |
| Response handling | `ReplyService.swift:2002-2043, 2062-2093` (HTTP status, `status_code`, `error.message` / `success.message`, `image.url`, `image.width`, `image.height`, `image.medium.url`, `image.thumb.url`, numbers as number or string) |
| `Referer` for `reho.st` | `HFRswift/Swift/MessagesView.swift:5748-5762` (`PhotoViewerNetworkRequestFactory`: `Referer: https://forum.hardware.fr`, host `reho.st` or `*.reho.st`); `master:6653-6667` |
| Thumbnail to full image | `MessagesView.swift:2202-2215, 3298-3312` (`img3.super-h.fr/images/` `.th.` removed, `reho.st/thumb/` to `reho.st/`, `rehost.diberie.com/Picture/Get/t/` to `…/f/`) |
| Hosts without file extension | `MessagesView.swift:2170-2176` (`reho.st`, `img3.super-h.fr`, `rehost.diberie.com` count as images whatever the path) |
| `hfr-rehost.net` to `reho.st` | `HFRswift/Wrapped/LinkItem.m:163`: text rewrite of the page, out of scope here (reader, LOT-083) |

## Behaviour

All in `Packages/HFRKit/Sources/HFRNetwork/`. Nothing imports another HFRKit module besides `HFRModels` (`RehostedImage`).

### Rehost client (`ImageHosts/Rehost*.swift`, `Transport/MultipartBody.swift`)

- `RehostConfiguration(baseURL:apiKey:)` holds the two injected values (ADR 0007, LOT-071 R2). An empty or blank key throws
  `RehostError.notConfigured`, so a build without a key switches the feature off. The base URL must be `https`, or `http` on a loopback
  host (`127.0.0.1`, `localhost`, `::1`, for tests), because the key travels in the query string. `description` shows the base URL only.
  Names of the build settings are the app lot's to wire (LOT-080); suggested: `REHOST_BASE_URL`, `REHOST_API_KEY` in the untracked
  `.xcconfig` of ADR 0007.
- `RehostClient.upload(jpeg:)` builds `POST <base>/api/1/upload/?key=<percent-encoded key>`: `multipart/form-data` with
  `imageCaption=Some Caption` then the `source` file (`image/jpeg`, `snapshot_<random>.jpg`), 60 s total timeout, redirects **not** followed, response read up to 64 KiB (`maximumResponseBytes`, via `HTTPRequest.maximumBodyBytes`; a longer
  answer is `network(.invalidResponse)`).
  The default transport is `AnonymousTransport` (cookie-less, LOT-071 R1); no `Cookie` or `Referer` header is set.
- The app prepares the JPEG (orientation, downscale to `RehostMaxDimension`, re-encode): those need UIKit/ImageIO and stay out of `HFRKit`.
  Whether the re-encode strips EXIF/GPS is unverified (LOT-071 T4, audit D §10 Q9) and is the app lot's.
- Answer: a 2xx whose payload says `status_code` 200 (or has none) and holds `image.url` gives a `RehostedImage` (`fullURL`, `mediumURL`,
  `miniURL`, `width`, `height`, `uploadedAt` from an injected clock). Renditions whose URL is not an absolute `http(s)` URL with a host are
  dropped; a bad `image.url` is `missingImageURL`.
- `RehostError`: `notConfigured`, `invalidBaseURL`, `emptyImage`, `network(NetworkError)` (offline, timeout, cancelled), `http(statusCode:message:)`
  (non-2xx), `rejected(statusCode:message:)` (2xx but payload status not 200), `invalidResponse` (not a JSON object), `missingImageURL`. The
  host's message is kept (actionable, LESSONS 5) but any occurrence of the key is replaced and it is cut to 200 characters. No error holds the
  key, the image or a URL with a query.
- **A POST is never retried and success is reported only on the host's confirmation** (a lost answer is an error; the user decides whether to
  upload again, and the host may already hold the image).

### Host adapter table (`ImageHosts/ImageHostRule.swift`, `ImageHostTable.swift`)

`ImageHostTable.standard` is a list of `ImageHostRule` values: **data**, so a capture changes a row without touching logic. A rule has a host
(with or without subdomains), an optional `referer`, `observedHTTPOnly`, `servesExtensionlessImages` and an optional `thumbnailRewrite`.
No rule carries a key: the table is keyless by construction, only `RehostConfiguration` has one.

| Host (subdomains) | Rule | Source |
|---|---|---|
| `reho.st` (yes) | `Referer: https://forum.hardware.fr`; extension-less; `/thumb/` to `/` | legacy `MessagesView.swift:5748-5762`; E26 **pending capture** |
| `img3.super-h.fr` (no) | extension-less; `.th.` removed from the file name under `/images/` | legacy `MessagesView.swift:2202-2215` |
| `rehost.diberie.com` (no) | extension-less; `/Picture/Get/t/` to `/Picture/Get/f/` | legacy `MessagesView.swift:2202-2215` |
| `hostingpics.net`, `casimages.com`, `free.fr`, `photorapide.com`, `camif.fr`, `hn.org` (yes) | `observedHTTPOnly` | LOT-071 (captures `R20`, `R21`, `R22a`) |

- `rule(for:)` recognises a host by the **parsed host at a label boundary**, lower-cased, one trailing dot ignored; never by a substring
  (`reho.st.evil.example`, `notreho.st`, `…/reho.st/…` and `?u=reho.st` do not match). Only `http(s)` URLs with a host match.
- `request(for:)` returns a cookie-less GET (`AnonymousTransport`, LOT-071 R1) with the rule's `Referer` and no other third-party header
  (R3: no `Referer` for hosts without a rule). It never rewrites the scheme and uses `RedirectPolicy.doNotFollow`: the caller reads
  `redirectLocation` and applies the D-071-1 block rules to every hop itself, and the `Referer` never travels to the next host. A non-`http(s)` or host-less URL throws `invalidRequest`.
- `observedHTTPOnly` means "every captured reference is `http://`"; whether `https` works is not measured, so the table does not upgrade.
  How the reader loads these hosts is LOT-083's decision (D-071-1 point 4; no ATS exception exists, `Info.plist` has no
  `NSAppTransportSecurity`). This lot only publishes the list.
- `fullSizeURL(for:)` applies the rewrite by parsed path (whole prefix; file name only for `.th.`), keeps query and fragment, and returns any
  other URL unchanged. The legacy code did a text replacement on the whole URL.
- Blocking private/LAN hosts and non-image `*.hardware.fr` paths (D-071-1 point 1) is **not** here: it belongs to the reader (LOT-083),
  before any request.

## Edge cases

- Redirect on the upload (3xx): not followed (it would replay the key and the image to another host); reported as `http(statusCode:)`.
- HTTP 4xx with the host's JSON error (invalid key, size limit): `http` with the host's message. A non-JSON 5xx: `http` with no message.
- 200 with `status_code` other than 200: `rejected`. 200 with a non-JSON body, `[]` or an empty body: `invalidResponse`.
- `status_code` and `width`/`height` as JSON numbers or numeric strings both read.
- File name, field name or content type containing `"`, CR or LF cannot start another header (`%22`, `%0D`, `%0A`; CR/LF dropped from the type).
- An upload answer over 64 KiB is not read (`network(.invalidResponse)`), so an untrusted or hijacked host cannot make the app hold a large body.
- The key is redacted from host messages in both its raw and its URL-encoded form (`+` is `%2B`).
- Task cancellation: `RehostError.network(.cancelled)`.
- Transport errors are wrapped after sanitizing: a `httpStatus` URL loses query and userinfo (the key is in the query), an `invalidRequest`
  reason is replaced by fixed text.
- `status_code` present but not an integer or numeric string (`"error"`, `null`, an object) is `invalidResponse`: the HTTP-status fallback is
  only for an absent key.
- A base URL with userinfo, query or fragment is `invalidBaseURL` (it is printed by `description`).
- A thumbnail rule that would build an invalid percent-encoded path leaves the URL unchanged (Foundation's setter traps otherwise).

## Fixtures

None. No capture of an upload answer exists and the real host is never contacted: tests use `MockTransport` and an in-process loopback
server (`LoopbackServer`, 127.0.0.1). The wire shape comes from the legacy code only.

Differential: `MultipartBodyTests.matchesTheLegacyUploadLayout` writes legacy's `makeMultipartBody` byte for byte and compares; the response
tests use the payload shapes legacy reads; `ImageHostTableTests.thumbnailsMapToFullImages` reproduces the three legacy rewrites.

**Pending capture** (issues: [#134](https://github.com/ezzz/HFRnow/issues/134) for 1, [#301](https://github.com/ezzz/HFRnow/issues/301) for 2, [#302](https://github.com/ezzz/HFRnow/issues/302) for 3):

1. A `reho.st` image fetched cookie-less **with and without** `Referer: https://forum.hardware.fr/` (and `https://forum.hardware.fr`):
   settles E26 and the exact value of the table's `referer`. Until then the rule is legacy's value (no trailing slash).
2. One `http://`-only host (`R20`/`R21`/`R22a`) requested over `https`: does it work or upgrade? Settles `observedHTTPOnly` and LOT-083's ATS choice.
3. One real upload answer of the Chevereto host (success and an error such as a wrong key), anonymized: needs the key and publishes an image
   publicly, so it is the operator's decision. Until then the response shape is "as legacy reads it", not verified.
   **The key travels in the query string because legacy does so, and hosts and proxies may log it** (ADR 0007 threat model). Moving it
   to a POST field is **not assumed**: it waits for capture #302 (whether the host accepts it) and an operator decision.

## Intentional differences from legacy

- Key and base URL are injected; empty key disables the feature (ADR 0007). Legacy had the key as a default parameter.
- Upload redirects are not followed and non-2xx is checked **before** the payload: legacy parsed the JSON first, so a non-JSON 5xx page became
  "invalid response" and the status was lost.
- The key is percent-encoded in the query and redacted from host messages; messages are capped at 200 characters.
- Plain `http` base URLs are refused outside loopback (legacy hard-coded `https`).
- Image/rendition URLs from the host are accepted only as absolute `http(s)` URLs with a host.
- Host matching by parsed host (label boundary, trailing dot ignored) instead of `host == … || hasSuffix(".reho.st")` on a lower-cased string; thumbnail rewrites by parsed path, not text replacement on the whole URL.
- Photo-viewer requests no longer share the forum cookie jar: `AnonymousTransport` (LOT-071 R1).

## Learnings

- A Swift Testing struct with a throwing `init` keeps `try` out of helpers; with typed throws, a `do/catch` whose body also calls an untyped
  throwing helper turns `error` into `any Error`, so keep helpers non-throwing.
- Loopback tests prove "no cookie" and "redirect not followed" against a real socket; a mock only proves what the client put on the request.
