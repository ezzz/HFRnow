# LOT-102 — Image upload and insertion (rehost)

- **Module:** App
- **Difficulty / model:** medium (Opus → Fable; this PR coded by Sonnet 5.5 in the cloud, reviewed by Opus)
- **Issue:** [#193](https://github.com/ezzz/HFRnow/issues/193) (host: mac, coded in the cloud, Mac check list in the PR)
- **Inputs:** [LOT-056](LOT-056-image-hosts.md) (`RehostClient`, `RehostedImage`) · [LOT-071](LOT-071-third-party-services.md) (T4, N1) ·
  [ADR 0007](../adr/0007-third-party-api-keys.md) · LOT-085 (`ReplyTextInsertionEngine`, `ComposerFormattingModel`) · LOT-060 (settings keys) · LOT-064 (upload history store)

## Legacy sources

Lines of <https://github.com/ezzz/HFRnow> @ `2440d79`.

| Concern | Legacy |
|---|---|
| Panel (Photos, Caméra, size, BBCode mode, list, manual URL) | `HFRswift/Swift/AnswerView.swift:1801-1982` (`ReplyImageInsertionView`) |
| Row of an uploaded image, one button per rendition | `AnswerView.swift:1984-2046` |
| Camera / photo library | `AnswerView.swift:2048-2130` (`ReplyUIKitImagePicker`, `ReplyPhotoLibraryPicker`) |
| Upload task, error shown, history insert | `AnswerView.swift:646-676` (`startImageUpload`) |
| Settings and legacy keys | `ReplyService.swift:1735-1810` (`RehostBBCodeMode`, `RehostUploadMaxDimension`, `RehostPreferencesStore`: `rehost_use_link`, `rehost_resize_before_upload`) |
| Snippet per mode and variant | `ReplyService.swift:1866-1893` (`formattedSnippet`) |
| Downscale and JPEG quality | `ReplyService.swift:1983-1984, 2097-2120` (`rehostPreparedForUpload`, quality 1.0) |
| History file | `ReplyService.swift:1895-1920` (`rehostImagesSwiftUI.json`) |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `ImageUploadView` | `AnswerView.swift (ReplyImageInsertionView, ReplyUploadedImageRow, ReplyUIKitImagePicker)` |
| `ImageUploadModel` | `AnswerView.swift (startImageUpload)`, `ReplyService.swift (RehostPreferences, RehostUploadedImage)` |
| `ImageIOPreparer` | `ReplyService.swift (UIImage.rehostPreparedForUpload)` |
| `ReplyComposerView` toolbar "Image" | `AnswerView.swift` (image button opening the panel) |

## UX evolutions (GAP-091)

- **b·needed** — Notice N1 before the first upload (LOT-071: legacy had none), per device.
- **b·needed** — No EXIF/GPS in the uploaded JPEG (privacy label "Data Not Collected", #193 note of 2026-10-28).
- **b** — The "Preview" rendition is gone: the engine's `RehostedImage` has full, medium and mini (LOT-056); legacy's `preview` has no counterpart in the host answer the engine reads.
- **b** — No full-screen viewer of an uploaded image; `PhotosPicker` replaces the `PHPickerViewController` wrapper (no permission prompt for the library).
- Otherwise the same UX: size choice, three BBCode modes, list newest first with swipe to forget, manual link.

## Behaviour

- **Entry**: the composer toolbar's "Image" button opens `ImageUploadView` as a sheet (disabled while the composer cannot edit).
  The sheet's model lives as long as the composer: an upload that finishes after the sheet closed still lands in the list.
- **Gate (N1)**: `ImageUploadModel.submit(_:)` stores the picked bytes and shows the notice when `rehost_notice_accepted` is not `true`
  in the settings store. Nothing is prepared or sent until "Continuer"; "Annuler" drops the bytes and the notice asks again next time.
  The key is new (no legacy equivalent) and read raw: the `SettingKey` catalogue is the legacy one and its tests pin it, so the typed key waits for the Settings reset (below). "Continuer" stores the flag synchronously, then uploads in a task. A reset in Settings is **not** in this lot (left, see below).
- **Prepare** (`ImageIOPreparer`): decode with ImageIO, apply the orientation, downscale to `rehost_resize_before_upload` on the longest side
  (never upscale; default 1200), re-encode JPEG at quality 1.0 with **no properties** besides the quality: no EXIF, TIFF or GPS block.
  The test builds a JPEG carrying GPS, EXIF and TIFF blocks, checks the fixture has them, then checks the output has none (properties and raw bytes),
  and that the bytes reaching the uploader are that output. **Measured on a device: Mac check item.**
- **Upload**: `RehostClient.upload(jpeg:)` unchanged (LOT-056: cookie-less, 60 s, no retry, host's own confirmation). One upload at a time;
  a second pick while one runs is ignored.
- **Key**: read from the app's `Info.plist` keys `RehostBaseURL` and `RehostAPIKey` (`ImageUploadServices.configuration(from:)`). Absent, blank or an
  unexpanded `$(NAME)` means "no key": uploading is off, the sheet says so, manual links still work. The values come from the untracked
  `.xcconfig` of ADR 0007; **wiring that file into the project is pending (Mac check)**. No key is in source, tests or logs; error messages are the
  client's already redacted ones.
- **Errors** (French, the host's message kept): offline says nothing was sent; a timeout or another transport failure says the image may have been sent without the app knowing (the
  POST is never retried); HTTP and payload refusals show `Erreur de l'hébergeur (code) : message`. The composer text is never touched by a failure.
- **History**: the engine's `RehostUploadHistoryStore` (LOT-064: versioned file, `Application Support/RehostHistory/uploads.json`, newest first,
  no duplicate id), read once per model (reopening the panel keeps what is in memory). Unreadable data is never overwritten: the store refuses writes,
  the panel warns, new images stay in memory for the session. Setting the unreadable file aside (`discardUnreadableData`) is not offered here. A failed
  write warns and keeps the list in memory. Legacy's `rehostImagesSwiftUI.json` is not read (other schema, other app container).
- **Insert**: tapping a rendition builds `RehostedImage.snippet(variant:mode:)` (LOT-056 / LOT-012: `[url=FULL][img]URL[/img][/url]\n`,
  `[img]URL[/img]\n` or the bare URL; a missing rendition falls back to the next larger one) and `ComposerFormattingModel.insert` puts it at the caret
  through `ReplyTextInsertionEngine.insert`, replacing the selection, caret after. The sheet closes and the editor takes focus.
- **Manual link**: `http(s)` URL with a host, trimmed, full rendition, same modes. Nothing is uploaded.
- **Settings**: `rehost_use_link` (0, 1, 2) and `rehost_resize_before_upload` (400…1200) keep their legacy keys through `SettingKey.rehostLinkMode` and
  `rehostMaxDimension`.

## Edge cases

- Camera unavailable (simulator, iPad without camera): the button is disabled.
- A picked item that cannot be read as data: "Impossible de lire cette image." and nothing is sent.
- An image already smaller than the chosen dimension is re-encoded but not enlarged.
- Several renditions missing in the host's answer: only the buttons of the existing ones show.

## Pending capture

- **Host's behaviour on EXIF it receives** is irrelevant (we strip first); **what the host returns for a very large file or a refused type** is not captured
  (the host's message is shown as it comes). Listed for the Mac backlog (#337), not guessed here.
- **E26** (`Referer` for `reho.st`) stays LOT-056's.

## Fixtures

None: images are built in the tests with ImageIO.

## Intentional differences from legacy

See "UX evolutions". Also: the JPEG goes through ImageIO instead of a UIKit redraw (same pixels, no metadata).

## Left for later

- Offering to set an unreadable history file aside.
- Reset of notice N1 in Settings (LOT-071 N1 asks for it): the key is `rehost_notice_accepted`.
- Wiring `REHOST_BASE_URL` and `REHOST_API_KEY` from the untracked `.xcconfig` into `Info.plist` (ADR 0007, LOT-080), and the GitHub Actions secret for the app job.

## Learnings
- `CGImageSourceCreateThumbnailAtIndex` upscales when asked for more than the image has: cap the target at the real size.
