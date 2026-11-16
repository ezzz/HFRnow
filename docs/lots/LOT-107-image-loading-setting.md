# LOT-107 — Image loading setting

Spec: [FEAT-011](../features/FEAT-011.md). Issue [#198](https://github.com/ezzz/HFRnow/issues/198), feature [#155](https://github.com/ezzz/HFRnow/issues/155).

## Legacy counterpart
`display_images` / `ImageDisplayMode` (LOT-060). Legacy had no screen for it (options removed in 3.0); the picker is the M5-free minimum that restores the choice with the legacy keys and values.

## Already shipped by LOT-083
Policy C, `ImageAutoLoad`, `ReaderSettings`, `NetworkMonitor` (default Wi-Fi), tap consent, tests in `ImagePolicyTests`.

## This lot
- `GeneralSettingsModel.imageLoading` (key `display_images`) and the "Images externes" picker in `SettingsView`.
- Tests: default and legacy values, write-through, effect on `ReaderSettings` with a stubbed Wi-Fi flag, private host blocked whatever the setting.
- Pending Mac check: device/simulator look and behaviour (see the PR).

## Legacy oracles not compared yet
`Packages/HFRKit/Tests/HFRParsingTests/Fixtures/LOT-003-settings/R21-sig-noimg-novid` and `R28-noimg-novid` hold legacy's `toHTML` with `display_images=no` (LOT-003). No test compares the reader's rendering with them: the engine's `MessageContent` does not depend on the setting (LOT-070 gate A, which owns them without comparing their image half).
