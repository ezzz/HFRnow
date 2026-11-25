"""The legacy-pointer check (#1252): a `// Port of` pointer must find its symbol in the lines it cites."""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tooling" / "docs"))

import check_legacy_pointers as clp  # noqa: E402

SHA = "87fe0d1c"
LEGACY_PATH = "HFRswift/Swift/AppSettingsView.swift"


def legacy_file() -> list:
    """A stand-in for the legacy file: `applyIconSelection` at 221-231, the icon `Picker` at 411-416, filler elsewhere."""
    lines = [f"// filler {n}" for n in range(1, 501)]
    lines[220] = "    private func applyIconSelection() {"
    lines[230] = "    }"
    lines[410] = '            Picker("Icône", selection: $iconValue) {'
    return lines


def reader(sha: str, path: str):
    return legacy_file() if (sha, path) == (SHA, LEGACY_PATH) else None


def check(header: str, extra: str = "") -> clp.Result:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "App").mkdir()
        (root / "App" / "View.swift").write_text(f"import SwiftUI\n\n{header}\n{extra}struct View {{}}\n")
        return clp.check(root / "App", reader, root)


class LegacyPointerTests(unittest.TestCase):
    def test_the_appicon_pointer_before_1197_is_wrong(self):
        # 2440d79 lines under a 87fe0d1c sha: the icon Picker is not at 360-365 any more.
        old = f"// Port of {LEGACY_PATH} (icon Picker, lines 360-365, `applyIconSelection` 213-224) @ {SHA}. Differences: none."
        result = check(old)
        self.assertEqual(len(result.failures), 1, result.failures)
        self.assertIn("`Picker` is not in these lines", result.failures[0])

    def test_the_corrected_pointer_passes(self):
        new = f"// Port of {LEGACY_PATH} (icon Picker, lines 411-416, `applyIconSelection` 221-231) @ {SHA}. Differences: none."
        result = check(new)
        self.assertEqual((result.failures, result.checked), ([], 2))

    def test_a_symbol_range_with_a_colon_and_a_wrapped_header(self):
        header = f"// Port of {LEGACY_PATH} (applyIconSelection `:221-231`)\n// @ {SHA}. Differences: none."
        self.assertEqual(check(header).failures, [])
        wrong = f"// Port of {LEGACY_PATH} (applyIconSelection :300-310)\n// @ {SHA}. Differences: none."
        self.assertEqual(len(check(wrong).failures), 1)

    def test_a_range_past_the_end_of_the_file_is_wrong(self):
        result = check(f"// Port of {LEGACY_PATH} (applyIconSelection :900-910) @ {SHA}.")
        self.assertIn("range outside the file", result.failures[0])

    def test_two_files_in_one_header_are_checked_each_against_its_own_path(self):
        # The second pair's items must not be read against the first path (probe of the round 1 review).
        header = (
            f"// Port of {LEGACY_PATH} (AppSettingsView) and Other/AnswerView.swift (title, composerHeader `:765-819`) @ {SHA}."
        )
        self.assertEqual(check(header).failures, [])
        both = (
            f"// Port of {LEGACY_PATH} (applyIconSelection :221-231) and {LEGACY_PATH} (Picker, lines 411-416) @ {SHA}."
        )
        self.assertEqual(check(both).checked, 2)

    def test_a_range_after_prose_is_not_attached_to_a_word_of_the_prose(self):
        header = f"// Port of {LEGACY_PATH} (initOrResetMP:fromView:, the creation alert, lines 1-3) @ {SHA}."
        result = check(header)
        self.assertEqual((result.failures, result.checked), ([], 0))

    def test_a_bare_colon_range_after_a_list_is_unchecked(self):
        # « A, B, :a-b »: the range may cover the group, so it is not read as B's (52 real headers, no false alarm).
        header = f"// Port of {LEGACY_PATH} (ReplyDraftPickerSheet, applyIconSelection, :300-310) @ {SHA}."
        result = check(header)
        self.assertEqual((result.failures, result.checked), ([], 0))

    def test_a_reversed_range_is_wrong_and_says_so(self):
        result = check(f"// Port of {LEGACY_PATH} (applyIconSelection :231-221) @ {SHA}.")
        self.assertIn("reversed range", result.failures[0])

    def test_a_plain_word_before_a_range_is_prose_not_a_symbol(self):
        result = check(f"// Port of {LEGACY_PATH} (applyIconSelection :221-231, alerts `:300-310`) @ {SHA}.")
        self.assertEqual((result.failures, result.checked), ([], 1))
        result = check(f"// Port of {LEGACY_PATH} (alerts :300-310) @ {SHA}.")
        self.assertEqual((result.failures, result.checked), ([], 0))

    def test_what_cannot_be_checked_never_fails(self):
        for header in (
            f"// Port of {LEGACY_PATH} (AppSettingsView) @ {SHA}. Differences: none.",  # no range
            f"// Port of {LEGACY_PATH} (applyIconSelection, Common.swift:108-110) @ {SHA}.",  # another file's range
            "// Port of Classes/Other.m (-initOrReset:) @ 87fe0d1c.",  # unknown file
            f"// Port of {LEGACY_PATH} (applyIconSelection :221-231) @ deadbeef.",  # sha git cannot read
            "// not a pointer at all: 411-416",
            f"/// Port of {LEGACY_PATH} (applyIconSelection :1-2) @ {SHA} in a doc comment, not a header.",
        ):
            with self.subTest(header=header):
                result = check(header)
                self.assertEqual(result.failures, [])

    def test_the_repository_headers_hold(self):
        """The real `App/` headers, when the legacy shas are fetched; unchecked (not failed) when they are not."""
        result = clp.check(ROOT / "App", clp.git_reader(ROOT), ROOT)
        self.assertEqual(result.failures, [])


if __name__ == "__main__":
    unittest.main()
