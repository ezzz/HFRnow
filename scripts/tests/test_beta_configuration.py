"""Tests for the internal-TestFlight beta variant (LOT-161 step 1, #251).

The beta must get its own bundle id and display name from App/Config/Beta.xcconfig while Debug and Release keep
hfrplus.red.super: a target-level setting in project.pbxproj would silently win over the xcconfig, so these tests read
the project file itself. They also check the release script's argument rules that run before any build.
"""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PROJECT = ROOT / "App/SwiftHFR.xcodeproj/project.pbxproj"
SCHEMES = ROOT / "App/SwiftHFR.xcodeproj/xcshareddata/xcschemes"
BETA_XCCONFIG = ROOT / "App/Config/Beta.xcconfig"
SCRIPT = ROOT / "scripts/release-testflight.sh"
APP_TARGET_LIST = "Build configuration list for PBXNativeTarget \"SwiftHFR\""


def configurations(project: str, list_name: str) -> dict[str, str]:
    """Maps each configuration name of a configuration list to the text of its XCBuildConfiguration block."""
    listed = re.search(r"/\* " + re.escape(list_name) + r" \*/ = \{.*?buildConfigurations = \((.*?)\);", project, re.S)
    assert listed, list_name
    result = {}
    for ident, name in re.findall(r"([0-9A-F]{24}) /\* (\w+) \*/", listed.group(1)):
        block = re.search(r"\t\t" + ident + r" /\* \w+ \*/ = \{\n(.*?)\n\t\t\};", project, re.S)
        assert block, ident
        result[name] = block.group(1)
    return result


def xcconfig_value(text: str, key: str) -> str | None:
    match = re.search(r"^" + re.escape(key) + r"\s*=\s*(.*?)\s*$", text, re.M)
    return match.group(1) if match else None


class BetaConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = PROJECT.read_text(encoding="utf-8")

    def test_every_list_has_a_beta_configuration(self):
        for name in ("Build configuration list for PBXProject \"SwiftHFR\"", APP_TARGET_LIST,
                     "Build configuration list for PBXNativeTarget \"SwiftHFRTests\""):
            self.assertEqual(sorted(configurations(self.project, name)), ["Beta", "Debug", "Release"], name)

    def test_debug_and_release_keep_the_store_bundle_id(self):
        app = configurations(self.project, APP_TARGET_LIST)
        for name in ("Debug", "Release"):
            self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = hfrplus.red.super;", app[name], name)
            self.assertIn("INFOPLIST_KEY_CFBundleDisplayName = HFR;", app[name], name)
            self.assertIn("/* Shared.xcconfig */", app[name], name)

    def test_beta_takes_its_identity_from_the_xcconfig(self):
        beta = configurations(self.project, APP_TARGET_LIST)["Beta"]
        self.assertIn("baseConfigurationReference = 080A00000000000000000504 /* Beta.xcconfig */;", beta)
        # A target-level value would override the xcconfig and ship the beta under the store id.
        self.assertNotIn("PRODUCT_BUNDLE_IDENTIFIER", beta)
        self.assertNotIn("CFBundleDisplayName", beta)
        self.assertIn("path = Config/Beta.xcconfig;", self.project)
        text = BETA_XCCONFIG.read_text(encoding="utf-8")
        self.assertIn('#include "Shared.xcconfig"', text)
        self.assertEqual(xcconfig_value(text, "PRODUCT_BUNDLE_IDENTIFIER"), "hfrplus-swift.red.super")
        self.assertEqual(xcconfig_value(text, "INFOPLIST_KEY_CFBundleDisplayName"), "SwiftHFR β")
        self.assertEqual(xcconfig_value(text, "DEVELOPMENT_TEAM"), "QMG83DG7YP")
        self.assertEqual(xcconfig_value(text, "CODE_SIGN_STYLE"), "Automatic")

    def test_beta_build_settings_otherwise_match_release(self):
        app = configurations(self.project, APP_TARGET_LIST)
        dropped = ("PRODUCT_BUNDLE_IDENTIFIER", "INFOPLIST_KEY_CFBundleDisplayName", "baseConfigurationReference", "name =")

        def settings(block: str) -> list[str]:
            return [line for line in block.splitlines()[1:] if not any(key in line for key in dropped)]

        self.assertEqual(settings(app["Beta"]), settings(app["Release"]))

    def test_beta_scheme_archives_the_beta_configuration(self):
        scheme = (SCHEMES / "SwiftHFR Beta.xcscheme").read_text(encoding="utf-8")
        for action in ("LaunchAction", "ProfileAction", "ArchiveAction"):
            self.assertRegex(scheme, r"<" + action + r"\s+buildConfiguration = \"Beta\"", action)
        default = (SCHEMES / "SwiftHFR.xcscheme").read_text(encoding="utf-8")
        self.assertRegex(default, r"<ArchiveAction\s+buildConfiguration = \"Release\"")


class ReleaseScriptBetaArgumentsTests(unittest.TestCase):
    def run_script(self, *args: str) -> subprocess.CompletedProcess:
        # An invalid signing style stops the script right after its settings are read, before any git or xcodebuild call.
        env = {"PATH": "/usr/bin:/bin", "NO_COLOR": "1", "HOME": "/nonexistent", "HFR_SIGNING_STYLE": "invalid"}
        return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, check=False, env=env)

    def test_beta_build_must_be_an_integer(self):
        result = self.run_script("--beta", "--version", "5.0", "--build", "1.2", "--dry-run")
        self.assertEqual(result.returncode, 1)
        self.assertIn("--build must be a positive integer with --beta", result.stderr)

    def test_store_build_is_still_required_without_beta(self):
        result = self.run_script("--version", "5.0", "--dry-run")
        self.assertEqual(result.returncode, 1)
        self.assertIn("--build is required", result.stderr)

    def test_beta_skips_the_legacy_floor(self):
        store = self.run_script("--version", "1.0", "--build", "1", "--dry-run")
        self.assertIn("does not exceed the legacy floor", store.stderr)
        beta = self.run_script("--beta", "--version", "1.0", "--dry-run")
        self.assertIn("Beta hfrplus-swift.red.super, version 1.0", beta.stdout)
        self.assertIn("HFR_SIGNING_STYLE must be manual or automatic", beta.stderr)

if __name__ == "__main__":
    unittest.main()
