# FEAT-014 — HD gallery

- **Issue:** [#158](https://github.com/ezzz/HFRnow/issues/158) · **Proposed by:** Bybifok (credit kept, see [CREDITS.md](../../CREDITS.md))
- **Lots:** [LOT-109](../lots/LOT-109-image-viewer.md) (the viewer; last lot of this feature)

## What and why
A tap on a posted picture opens it full screen, in its full-size version, and a swipe moves to the other pictures of the page. Readers complained that the gallery was lost and that thumbnails stay blurry (≈21 reports).

## Screens and states
- Tap on a loaded picture of a message (not a smiley, an avatar, a placeholder or a picture shown as a link): full-screen viewer over the reader.
- Pager: swipe left/right between the pictures of the **page** (decision of this spec: the legacy open question "per message or per page" is answered per page, which is what the page-wide list of `reader.js` gives). Title "2 / 5" when there are several, nothing for one.
- Zoom: pinch, double tap (up to 7.5x, legacy maximum); pan when zoomed.
- Toolbar: **Fermer** (always visible, so it is reachable on iPad and with a keyboard or pointer) and a menu: Partager, Enregistrer dans Photos, Copier le lien. Save and share appear once the image is downloaded; **Partager hands the downloaded bytes to the share sheet, never the address** (the system would fetch an address itself, previews and redirects, outside policy C). Copier le lien copies the full-size address as text.
- Loading: spinner; failure: "Impossible de charger la photo" and **Réessayer**.
- Feedback line at the bottom: "Photo enregistrée", "Lien copié", "Autorise l'accès aux Photos pour enregistrer l'image." (legacy texts).
- Light/dark: the viewer is always dark over black; Dynamic Type XL: toolbar and banner are system text.

## Which pictures are in the gallery
The page reports the pictures it shows; the app **re-decides** (policy C, LOT-071 D-071-1): a forum image, or a third-party image the user already allowed (tap on its placeholder, or the "Images externes" setting loads them). The consent given to a thumbnail covers its host-table full-size URL on the **same host** (a rewrite that changes the host is ignored). A picture inside a closed spoiler is not in the gallery. A neighbour that is still a placeholder is **not** in the gallery, so a swipe never fetches an image the reader would not have loaded. A blocked address is never in it.

## Requests (D-071-1, LOT-056)
- Every download goes through `ReaderImageFetcher` (cookie-less `AnonymousTransport`, never the account session), redirect by redirect through the policy.
- Full-size URL from the host table (`ImageHostTable.fullSizeURL`: `reho.st/thumb/`, `img3.super-h.fr` `.th.`, `rehost.diberie.com/Picture/Get/t/`); when it fails, the thumbnail the page showed is used.
- `Referer: https://forum.hardware.fr` only for `reho.st`, looked up again at each hop (LOT-056); none for other hosts. `http` is requested over `https` (ATS), as in the reader.

## HFR facts
None new. Host rewrites and the `reho.st` Referer are LOT-056's (legacy `MessagesView.swift:2202-2215`, `:5748-5762`); **pending capture** #134 (images and rehost behaviour on live pages: whether `reho.st` still needs the Referer, which hosts answer the full-size URL), checked by review #328.

## Edge cases
- Animated GIF/WebP: shown as a still image in this lot (**pending Mac check**; legacy animated them).
- Picture inside a link to another page: the tap opens the viewer, not the link (legacy opened the viewer for image links; a link to a non-image page behind a picture is not followed from the picture).
- Page changed while the viewer is open: the viewer keeps its own list; closing returns to the page.
- At most 500 pictures per viewer (a window around the tapped one); only the selected image and its direct neighbours are held in memory, the others are dropped and downloaded again if the user swipes back.
- The filtered-posts screen opens the same viewer (it shares `reader.js`).
- Image larger than 15 MB or not `image/*`: failure state.

## Legacy settings kept
`display_images` (policy, LOT-107).
