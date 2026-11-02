# LOT-184 — On-demand « aperçu HFR » through `POST /apercu.php` (M5)

- **Module:** HFRClient
- **Difficulty / model:** medium (Opus → Fable)
- **Issue:** [#449](https://github.com/ezzz/HFRnow/issues/449) · **Milestone:** M5 (UX evolutions)
- **Decision:** [ADR 0014](../adr/0014-bbcode-preview-renderer.md), operator choice **O-1 = (b)** (2026-11-02, [#189](https://github.com/ezzz/HFRnow/issues/189)): the local renderer of LOT-097 labelled as a preview, plus this on-demand server preview.

Stub created on 2026-11-02 with the O-1 decision. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
None: this is an evolution, the legacy app has no preview. The HFR facts come from the captures of #400 (run 9).

## Behaviour
To write, on top of the merged LOT-097. Engine only: this lot delivers the `HFRClient` flow and its tests; LOT-152 (#242) adds the « aperçu HFR » action to its preview screen once the flow is merged (no dependency between the two lots: the local preview ships without it). Known today ([HFR-PROTOCOL](../HFR-PROTOCOL.md) §6b "BBCode round trip"): the form `apercu_form` of every composer posts `hash_check`, `apercu_contenu`, `apercu_smiley` (`1`/`0`) and `config` to `/apercu.php` (`editPost.js` `apercevoir()`); HFR answers 200 with the rendered message in `body.reponse` (`W61` → `R95d`, `W62` → `R95h`), equal to the thread page's message body once whitespace is removed, apart from the opening `<p>`. The flow checks the session before sending (LOT-044, LESSONS of #314), sends one POST, and gives its answer to the LOT-034 normalizer so the reader shows it like the local preview. `/apercu.php` writes nothing (`R95d.meta.json`: "no write"), so a failed exchange is reported as a plain failure and the member may ask again; the write rule of LOT-048 (`unconfirmed`, never retried) does not apply. The draft leaves the device only when the member asks for this preview.

## Edge cases
*Pending capture* (`host: mac`, a capture issue naming this lot, never hand-built, LESSONS 35-36): the answer logged out or with an expired session; with a missing or stale `hash_check`; with `apercu_smiley=1` (box checked, smileys disabled, §6b "Checkbox values"; `R95d` and `R95h` were posted with `0`); from a public-topic composer (`R95d`/`R95h` were posted from the `apercu_form` of the MP edit forms `R95c`/`R95f`; the `config` value of a public topic to confirm); a refusal shape if any (flood, closed topic).

## Fixtures
`R95c-mp-edit-form-bbcode-source.html` and `R95f-mp-edit-form-bmp-emoji-source.html` (the composers whose `apercu_form` and `hash_check` the flow reads, LOT-036), `R95d-apercu-bbcode-preview.html`, `R95d.meta.json` (the preview of the `W61` source, `apercu_smiley=0`), `R95h-apercu-bmp-emoji-preview.html`, `R95h.meta.json` (the preview of the `W62` source), `W61.meta.json`, `W62.meta.json` (#400, run 9). The failure states above once captured.

## Intentional differences from legacy
The whole lot is one: the legacy app has no preview.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
