# FEAT-008 — Swipes and topic actions in the lists

- **Issue:** [#152](https://github.com/ezzz/HFRnow/issues/152) · **Proposed by:** Bybifok ([`moust4ki`](https://github.com/moust4ki), credit kept, see [CREDITS.md](../../CREDITS.md); message and PR #6, "Dernière page" swipe, [research](../research/bybifok-proposals.md))
- **Lots:** [LOT-125](../lots/LOT-125-list-swipes.md) (M2: the legacy swipes, the legacy row menu and the flag writes behind them), [LOT-177](../lots/LOT-177-uniform-swipes.md) (#417, M5: the uniform swipe set)

## What and why
Manage a topic without opening it: mark it read, remove its flag, jump to a page, copy its link, from the flags, favourites and forum lists. UXD-08 (2026-11-02, #379) splits it: LOT-125 ports the legacy swipes and menu as they were; the uniform set Bybifok proposed ("Lu" with "Annuler" kept until refresh, "Dernière page", "Super favori" and "Retirer" as swipes in every list) is an M5 evolution, LOT-177, optional and never the default.

## Screens and states (LOT-125)
- Leading swipe "Lu" (full swipe allowed) and trailing swipe "Supprimer" on every flags or favourites row and on a forum row that has a flag (legacy `Favorites.swift:1073-1097`, `MainWindow.swift:676-693` @ 2440d79).
- Row menu, legacy order: Première page, Dernière page, Dernière réponse, Page numéro…, Copier le lien; then Lu, the super favourite entry (LOT-124), Supprimer, and "Filtrer les posts" on the favourites (LOT-114).
- "Supprimer" in flight: "Suppression…", disabled. Confirmed: the row leaves the flags and favourites lists, a forum row loses its flag. Not confirmed: the row stays and an alert says why, in French.
- Every swipe is also a VoiceOver action of the row.
- "Favoris" in the message menu (LOT-087) adds the topic to the favourites through the same actions.

## HFR facts
No new fact. The removal is LOT-051's list POST (`P03h`, `P03j`, HFR-PROTOCOL §6c "LOT-051"); "Favoris" is LOT-051's `addflag` (`P03a`, `P03b`). "Lu" sends nothing (legacy is local only, GAP-034).

## Edge cases
Logged out: no "Supprimer" and no "Favoris". A row without a topic number has no "Supprimer". A removal is never sent twice, and an unconfirmed one is never resent. A reload forgets the local "Lu" marks and the removed rows: HFR's page says what is read and flagged.

## Engine lots needed
LOT-051 (done), LOT-064 (done). App side: LOT-124 (super favourites), LOT-125, LOT-177.

## Legacy settings kept
None: legacy had no setting for these menus (`TopicQuickActionPolicy.defaults`, every entry on).
