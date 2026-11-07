# LOT-098 — Giphy client (search, trending; key and base URL injected)

- **Module:** HFRNetwork
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#190](https://github.com/ezzz/HFRnow/issues/190)
- **Inputs:** [LOT-071](LOT-071-third-party-services.md) (T5, R1, N1) · [ADR 0007](../adr/0007-third-party-api-keys.md) · [LOT-056](LOT-056-image-hosts.md) (the pattern) ·
  [LOT-040](LOT-040-transport.md) · captures `T40`, `T41` (#539, MANIFEST) · used by [LOT-155](https://github.com/ezzz/HFRnow/issues/245) (picker)

## Legacy sources

Lines are those of <https://github.com/ezzz/HFRnow> @ `2440d79`.

| Concern | Legacy |
|---|---|
| SDK configured at launch with an embedded key | `HFRswift/Swift/HFRswiftApp.swift:9, 20` (the key literal is deliberately not copied, ADR 0007) |
| Picker, rating R | `HFRswift/Swift/AnswerView.swift:2286-2335` (`GiphyViewController`, `rating = .ratedR` at `:2305`, theme, `mediaTypeConfig = [.gifs, .recents]`); opened from `:533` |
| What is inserted | `AnswerView.swift:2333` (`media.images?.original?.gifUrl`, then `[img]<url>[/img]` plus a newline) |
| Binary SDK | `GiphyUISDK.xcframework` 2.1.7 (audit E §6): not carried over, no SDK and no new package (AGENTS.md §3.3) |

Legacy has no REST call: the request shapes come from Giphy's public API reference, and the answers from the captures `T40` and `T41`.

## Legacy counterpart (app lots)

None: engine lot. The picker is LOT-155.

## UX evolutions (app lots)

None: engine lot.

## Behaviour

All in `Packages/HFRKit/Sources/HFRNetwork/Giphy/`. Nothing else is imported besides Foundation; `HFRModels` is not touched (the result types live in HFRNetwork).

- `GiphyConfiguration(baseURL:apiKey:)`: the two injected values (ADR 0007). A blank key throws `GiphyError.notConfigured`: a build without a key switches the
  feature off (the app lot tests the entry point, LOT-155). The base URL must be `https` (or `http` on `127.0.0.1`, `localhost` for tests), with no userinfo, query or
  fragment. `description`, `debugDescription`, `dump` and `Mirror` show the base URL only. Suggested build settings, for LOT-080's wiring: `GIPHY_BASE_URL` (`https://api.giphy.com`, as in the captures), `GIPHY_API_KEY`.
- `GiphyClient.search(_:limit:offset:rating:)` and `trending(limit:offset:rating:)` build `GET <base>/v1/gifs/search?q=…&limit=…&offset=…&rating=…&api_key=…` and
  `GET <base>/v1/gifs/trending?limit=…&offset=…&rating=…&api_key=…` (`T40`, `T41`). `q` is trimmed and percent-encoded (a space is `%20`, `+` is `%2B`); an empty one is
  `emptyQuery` and sends nothing. `limit` is clamped to 1...50 (default 25) and `offset` to 0 or more: the bounds are this lot's choice, not a Giphy fact. `rating` defaults
  to `.restricted` (`r`) as legacy. The search text is the only user data sent (T5 in LOT-071; N1 notice is the app's).
- **Policy**: the default transport is `AnonymousTransport` (cookie-less, R1) and no `Cookie`, `Referer` or `Authorization` header is set; the request goes to the injected host
  only and uses `RedirectPolicy.doNotFollow`, so a 3xx is `http(statusCode:)` and the key never reaches another host. Timeout 15 s, answer read up to 2 MiB.
- **Answer**: a 2xx with the `{data, …}` envelope gives a `GiphyPage` (`items`, `totalCount`, `offset`). `GiphyGIF` has `id`, `title`, `rating`, `originalURL`
  (`images.original.url`, what legacy posts), `originalWidth`/`originalHeight` (strings in the capture), `previewURL` (`images.fixed_width_small.url`) and
  `originalURLWithoutTracking`. An item without `id` or an absolute `https` `images.original.url` is dropped; a preview that is not `https` is nil. Only what `T40`/`T41` show is read.
- `GiphyError`: `notConfigured`, `invalidBaseURL`, `emptyQuery`, `network(NetworkError)` (key and query stripped from a `httpStatus` URL, `invalidRequest` reason replaced),
  `http(statusCode:)` (non-2xx, body not read), `invalidResponse` (not the envelope). No error holds the key.
- Both calls are GETs, so retrying is harmless; the client itself never retries.

## Edge cases

- The `cid` of every captured media URL is derived from the API key (MANIFEST `T40`). `originalURL` keeps it as served; a link posted into a message should not publish it
  if the CDN serves the URL without the query. **Pending capture**: one fetch of an `originalURLWithoutTracking`. LOT-155 posts `originalURL` as served (decided there, see its spec).
- The media URLs are checked for `https` only, not for host (the captures show `media*.giphy.com` only): a hijacked API host could point a GIF anywhere.
  LOT-155 restricts what it previews and posts to `https` on `*.giphy.com` (`GifMediaPolicy`).
- The request sent (no `lang`) differs from the captured one (`lang=en` on search): the omission is not verified, Giphy documents `lang` as optional.
- `rating` is a ceiling: `rating=r` returned `g` items.
- `pagination` of another shape is ignored (not fatal); one bad item does not fail the page.
- `meta.status` is not read: the HTTP status decides.
- `data` empty is a valid empty page.

## Fixtures

`T40` (search `q=hello`) and `T41` (trending), `limit=3&rating=r`, 2026-11-06, key stripped, `cid` prefix replaced by `00000000` (#539). The tests read them in place from
`HFRParsingTests/Fixtures/captures/` (as `RehostClientCaptureTests`) and answer through `MockTransport`. The tests' key is the dummy `DUMMYKEY0123`; no real key
is in any file. Requests are checked as data (host, redirect policy, headers): none of the tests needs a network path (LESSONS 56).

**Pending capture** (to open as an issue if not already): (1) a Giphy error answer (invalid key, rate limit) to decode its message; (2) a media URL fetched without its query.

## Intentional differences from legacy

- REST instead of the closed SDK: no binary dependency, nothing but the key and the search text leaves (the SDK may have sent more, not audited).
- Key and base URL injected, not embedded (ADR 0007); a build without a key has no GIF search.
- No `recents` tab (`mediaTypeConfig` had `.recents`): that is local state, for LOT-155 if wanted.
- No redirect is followed and no cookie is sent.

## Learnings

- Giphy's media URLs carry a key-derived value (`cid`): a link built from a response is not free of the key's fingerprint.
