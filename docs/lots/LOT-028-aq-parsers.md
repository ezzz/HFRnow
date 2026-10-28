# LOT-028 — AQ listing and RSS parsers

- **Module:** HFRParsing
- **Difficulty / model:** easy · Sonnet → Opus
- **Issue:** [#56](https://github.com/ezzz/HFRnow/issues/56). Split from [LOT-025](LOT-025-small-parsers.md), whose AQ part was left out ("Not covered / gaps").

Stub: the lot is `blocked` until the AQ capture ([#133](https://github.com/ezzz/HFRnow/issues/133)) exists (third-party host `aq.super-h.fr`, LOT-001 checklist row P08), with a legacy oracle for both parsers (LESSONS 35–36). Q-4 is decided: AQ is kept, with a first-use notice (LOT-071).

## Legacy sources
`AQPlusView.swift:29-87` (francoisgn/hfrnow @ `2440d79`; HFR-PROTOCOL §8, `aq.super-h.fr` row): `getAlertesByTopic.php?topic_id=` (response format unverified, pending the AQ capture) and `rss.php` (RSS). To complete with line ranges when the lot is claimed.

## Behaviour
Inputs: the `getAlertesByTopic` response and the RSS feed. Outputs: the AQ item models of LOT-012 (`HFRModels/AQ`), every item with its category (hiding the Apple category is app policy, Q-7).

## Edge cases
HTML entities in titles, authors and comments (HFR-PROTOCOL §7b B4, Bybifok; legacy fix `a817498`; [#105](https://github.com/ezzz/HFRnow/issues/105)).

## Fixtures
Pending capture.

## Intentional differences from legacy
To write with the fixtures.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
