"""Safety rules of scripts/release-testflight.sh (LOT-161), run end to end against stub Apple tools.

Each test copies the script into a throwaway git repository (branch dev-swift, pushed to a local bare "origin") and puts
stub `xcodebuild`, `xcrun`, `codesign` and `xcode-select` first on PATH: they log their arguments, fake an archive and an
.ipa, and never contact Apple. The upload prompt is answered through a pseudo-terminal. macOS only: the script reads the
archive with /usr/libexec/PlistBuddy and writes ExportOptions with plutil.
"""
import os
import plistlib
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPT = ROOT / "scripts/release-testflight.sh"
TEMPLATE = ROOT / "scripts/release-notes.template.md"
BETA_ID = "hfrplus-swift.red.super"
STORE_ID = "hfrplus.red.super"
ON_MAC = sys.platform == "darwin" and Path("/usr/libexec/PlistBuddy").exists() and Path("/usr/bin/plutil").exists()

XCODEBUILD = r"""#!/bin/bash
printf 'xcodebuild %s\n' "$*" >>"$STUB_LOG"
case "$1" in
  -version) echo "Xcode 27.2"; echo "Build version 27C0"; exit 0 ;;
  archive)
    scheme=""; ap=""; ver=""; build=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -scheme) scheme="$2"; shift 2 ;;
        -archivePath) ap="$2"; shift 2 ;;
        MARKETING_VERSION=*) ver="${1#*=}"; shift ;;
        CURRENT_PROJECT_VERSION=*) build="${1#*=}"; shift ;;
        *) shift ;;
      esac
    done
    if [ -n "${STUB_BUNDLE_ID:-}" ]; then id="$STUB_BUNDLE_ID"
    elif [ "$scheme" = "SwiftHFR Beta" ]; then id=hfrplus-swift.red.super
    else id=hfrplus.red.super; fi
    app="$ap/Products/Applications/SwiftHFR.app"
    mkdir -p "$app" && touch "$app/PrivacyInfo.xcprivacy"
    cat >"$app/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleDisplayName</key><string>stub</string>
<key>CFBundleShortVersionString</key><string>$ver</string>
<key>CFBundleVersion</key><string>$build</string>
<key>ITSAppUsesNonExemptEncryption</key><false/>
</dict></plist>
EOF
    exit 0 ;;
  -exportArchive)
    ep=""
    while [ $# -gt 0 ]; do case "$1" in -exportPath) ep="$2"; shift 2 ;; *) shift ;; esac; done
    mkdir -p "$ep" && echo stub >"$ep/SwiftHFR.ipa"
    exit 0 ;;
esac
exit 0
"""
XCRUN = r"""#!/bin/bash
printf 'xcrun %s\n' "$*" >>"$STUB_LOG"
echo "UPLOAD SUCCEEDED (stub)"
exit "${STUB_ALTOOL_RC:-0}"
"""
CODESIGN = "#!/bin/bash\nprintf 'codesign %s\\n' \"$*\" >>\"$STUB_LOG\"\nexit 0\n"
XCODE_SELECT = "#!/bin/bash\necho /Applications/Xcode.app/Contents/Developer\n"


def git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", *args], cwd=cwd, check=True,
                   capture_output=True)


@unittest.skipUnless(ON_MAC, "needs macOS PlistBuddy and plutil")
class ReleaseScriptSafetyTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(os.path.realpath(self._tmp.name))
        self.repo = self.tmp / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "App/SwiftHFR.xcodeproj").mkdir(parents=True)
        (self.repo / "App/SwiftHFR.xcodeproj/project.pbxproj").write_text("stub\n")
        shutil.copy2(SCRIPT, self.repo / "scripts/release-testflight.sh")
        shutil.copy2(TEMPLATE, self.repo / "scripts/release-notes.template.md")
        git(self.tmp, "init", "-q", "--bare", "origin.git")
        git(self.repo, "init", "-q", "-b", "dev-swift")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "fixture")
        git(self.repo, "remote", "add", "origin", str(self.tmp / "origin.git"))
        git(self.repo, "push", "-q", "origin", "dev-swift")
        git(self.repo, "fetch", "-q", "origin")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for name, body in (("xcodebuild", XCODEBUILD), ("xcrun", XCRUN), ("codesign", CODESIGN),
                           ("xcode-select", XCODE_SELECT)):
            (self.bin / name).write_text(body)
            (self.bin / name).chmod(0o755)
        self.home = self.tmp / "home"
        (self.home / "keys").mkdir(parents=True)
        self.key = self.home / "keys/AuthKey_TEST.p8"
        self.key.write_text("stub, not a key\n")
        self.counter = self.home / "beta-build-number"
        self.log = self.tmp / "stub.log"
        self.log.touch()
        self.runs = 0

    def tearDown(self):
        self._tmp.cleanup()

    # ------------------------------------------------------------ helpers
    def env(self, **extra: str) -> dict[str, str]:
        env = {
            "PATH": f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.home), "NO_COLOR": "1",
            "TMPDIR": str(self.tmp), "STUB_LOG": str(self.log), "HFR_ASC_KEY_ID": "TESTKEY",
            "HFR_ASC_ISSUER_ID": "00000000-0000-0000-0000-000000000000", "HFR_ASC_KEY_PATH": str(self.key),
            "HFR_PROFILE_NAME": "stub profile", "HFR_BETA_COUNTER": str(self.counter),
        }
        env.update(extra)
        return env

    def output_args(self) -> list[str]:
        self.runs += 1
        self.out = self.tmp / f"out{self.runs}"
        return ["--output", str(self.out)]

    def run_plain(self, *args: str, **extra: str) -> tuple[int, str]:
        """Runs the script without a controlling terminal."""
        result = subprocess.run(["/bin/bash", str(self.repo / "scripts/release-testflight.sh"), *args,
                                 *self.output_args()], cwd=self.repo, env=self.env(**extra), capture_output=True,
                                text=True, stdin=subprocess.DEVNULL, start_new_session=True, check=False)
        return result.returncode, result.stdout + result.stderr

    def run_tty(self, *args: str, answer: str, **extra: str) -> tuple[int, str]:
        """Runs the script on a pseudo-terminal and types `answer` at the confirmation prompt."""
        argv = ["/bin/bash", str(self.repo / "scripts/release-testflight.sh"), *args, *self.output_args()]
        env = self.env(**extra)
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(self.repo)
            os.execve(argv[0], argv, env)
        output, answered, deadline = b"", False, time.monotonic() + 120
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 1)
            if not ready:
                continue
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
            if not answered and b"to confirm: " in output:
                os.write(fd, answer.encode() + b"\n")
                answered = True
        os.close(fd)
        _, status = os.waitpid(pid, 0)
        return os.waitstatus_to_exitcode(status), output.decode(errors="replace")

    def calls(self, tool: str) -> list[str]:
        return [line for line in self.log.read_text().splitlines() if line.startswith(tool + " ")]

    def export_options(self) -> dict:
        with open(self.out / "ExportOptions.plist", "rb") as handle:
            return plistlib.load(handle)

    def phrase(self, bundle_id: str, version: str, build: str) -> str:
        return f"upload {bundle_id} {version} ({build})"

    # ------------------------------------------------------------ app record and scheme
    def test_store_run_refuses_an_archive_with_another_bundle_id(self):
        rc, out = self.run_plain("--version", "5.0", "--build", "40", "--dry-run", STUB_BUNDLE_ID=BETA_ID)
        self.assertEqual(rc, 1, out)
        self.assertIn(f"bundle id is {BETA_ID}, expected {STORE_ID}", out)

    def test_beta_run_refuses_an_archive_with_the_store_bundle_id(self):
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run", STUB_BUNDLE_ID=STORE_ID)
        self.assertEqual(rc, 1, out)
        self.assertIn(f"bundle id is {STORE_ID}, expected {BETA_ID}", out)

    def test_beta_run_archives_the_beta_scheme_internal_only(self):
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run", HFR_INTERNAL_ONLY="0")
        self.assertEqual(rc, 0, out)
        archive = [call for call in self.calls("xcodebuild") if call.startswith("xcodebuild archive")]
        self.assertEqual(len(archive), 1, archive)
        self.assertIn("-scheme SwiftHFR Beta -configuration Beta", archive[0])
        self.assertIn("CURRENT_PROJECT_VERSION=1", archive[0])
        self.assertIs(self.export_options().get("testFlightInternalTestingOnly"), True)
        self.assertEqual(self.calls("xcrun"), [])
        self.assertFalse(self.counter.exists(), "a dry run must not write the counter")

    def test_store_run_archives_the_store_scheme(self):
        rc, out = self.run_plain("--version", "5.0", "--build", "40", "--dry-run")
        self.assertEqual(rc, 0, out)
        archive = [call for call in self.calls("xcodebuild") if call.startswith("xcodebuild archive")]
        self.assertIn("-scheme SwiftHFR -configuration Release", archive[0])
        self.assertNotIn("testFlightInternalTestingOnly", self.export_options())

    # ------------------------------------------------------------ files that must stay outside the repository
    def assert_refused_inside(self, rc: int, out: str, what: str):
        self.assertEqual(rc, 1, out)
        self.assertIn(what, out)
        self.assertEqual([c for c in self.calls("xcodebuild") if "archive" in c], [])

    def test_counter_inside_the_repository_is_refused(self):
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run",
                                 HFR_BETA_COUNTER=str(self.repo / "not/yet/created/counter"))
        self.assert_refused_inside(rc, out, "The beta counter is inside the repository")

    def test_counter_through_a_symlink_to_the_repository_is_refused(self):
        (self.tmp / "link").symlink_to(self.repo)
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run",
                                 HFR_BETA_COUNTER=str(self.tmp / "link/new-folder/counter"))
        self.assert_refused_inside(rc, out, "The beta counter is inside the repository")

    def test_counter_in_another_letter_case_is_refused(self):
        variant = str(self.repo).swapcase()
        if not os.path.isdir(variant):
            self.skipTest("case-sensitive file system")
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run", HFR_BETA_COUNTER=variant + "/counter")
        self.assert_refused_inside(rc, out, "The beta counter is inside the repository")

    def test_key_file_in_another_letter_case_is_refused(self):
        key = self.repo / "AuthKey_TEST.p8"
        key.write_text("stub\n")
        variant = str(key).swapcase()
        if not os.path.exists(variant):
            self.skipTest("case-sensitive file system")
        rc, out = self.run_plain("--version", "5.0", "--build", "40", "--dry-run", HFR_ASC_KEY_PATH=variant)
        self.assert_refused_inside(rc, out, "The API key file is inside the repository")

    def test_settings_file_inside_the_repository_is_refused(self):
        config = self.repo / "release.env"
        config.write_text("HFR_TEAM_ID=QMG83DG7YP\n")
        rc, out = self.run_plain("--version", "5.0", "--build", "40", "--dry-run", "--config", str(config))
        self.assert_refused_inside(rc, out, "is inside the repository")

    # ------------------------------------------------------------ settings of the other mode
    def test_beta_settings_are_refused_without_beta(self):
        config = self.home / "release-beta.env"
        config.write_text("HFR_CHANNEL=beta\n")
        config.chmod(0o600)
        rc, out = self.run_plain("--version", "5.0", "--build", "1", "--dry-run", "--config", str(config))
        self.assert_refused_inside(rc, out, "These settings are for beta builds")

    def test_store_settings_are_refused_with_beta(self):
        config = self.home / "release.env"
        config.write_text("HFR_CHANNEL=store\n")
        config.chmod(0o600)
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run", "--config", str(config))
        self.assert_refused_inside(rc, out, "These settings are for store builds")

    def test_the_store_settings_variable_does_not_feed_a_beta_run(self):
        config = self.home / "store.env"
        config.write_text("HFR_TEAM_ID=STORETEAM\n")
        config.chmod(0o600)
        rc, out = self.run_plain("--beta", "--version", "5.0", "--dry-run", HFR_RELEASE_CONFIG=str(config))
        self.assertEqual(rc, 0, out)
        self.assertNotIn("teamID", self.export_options())

    # ------------------------------------------------------------ upload confirmation and counter
    def test_upload_without_a_terminal_is_refused_before_any_build(self):
        rc, out = self.run_plain("--beta", "--version", "5.0", "--upload")
        self.assertEqual(rc, 1, out)
        self.assertIn("needs an interactive terminal", out)
        self.assertEqual(self.log.read_text(), "")

    def test_a_reused_beta_build_is_refused_before_the_archive(self):
        self.counter.write_text("3\n")
        rc, out = self.run_tty("--beta", "--version", "5.0", "--build", "3", "--upload",
                               answer=self.phrase(BETA_ID, "5.0", "3"))
        self.assertEqual(rc, 1, out)
        self.assertIn("is not above the last uploaded beta build 3", out)
        self.assertEqual([c for c in self.calls("xcodebuild") if "archive" in c], [])
        self.assertEqual(self.calls("xcrun"), [])

    def test_a_phrase_without_the_app_record_is_refused(self):
        self.counter.write_text("3\n")
        rc, out = self.run_tty("--beta", "--version", "5.0", "--upload", answer="upload 5.0 (4)")
        self.assertEqual(rc, 1, out)
        self.assertIn("Not confirmed", out)
        self.assertEqual(self.calls("xcrun"), [])
        self.assertEqual(self.counter.read_text(), "3\n")

    def test_a_beta_phrase_does_not_confirm_a_store_upload(self):
        rc, out = self.run_tty("--version", "5.0", "--build", "1", "--upload", answer=self.phrase(BETA_ID, "5.0", "1"))
        self.assertEqual(rc, 1, out)
        self.assertIn(f'Type "{self.phrase(STORE_ID, "5.0", "1")}"', out)
        self.assertIn("Not confirmed", out)
        self.assertEqual(self.calls("xcrun"), [])

    def test_a_failed_upload_leaves_the_counter(self):
        self.counter.write_text("3\n")
        rc, out = self.run_tty("--beta", "--version", "5.0", "--upload", answer=self.phrase(BETA_ID, "5.0", "4"),
                               STUB_ALTOOL_RC="1")
        self.assertNotEqual(rc, 0, out)
        self.assertEqual(len(self.calls("xcrun")), 1)
        self.assertEqual(self.counter.read_text(), "3\n")

    def test_a_confirmed_beta_upload_sends_the_package_and_advances_the_counter(self):
        self.counter.write_text("3\n")
        rc, out = self.run_tty("--beta", "--version", "5.0", "--upload", answer=self.phrase(BETA_ID, "5.0", "4"),
                               HFR_INTERNAL_ONLY="0")
        self.assertEqual(rc, 0, out)
        self.assertIn("internal testing only", out)
        upload = self.calls("xcrun")
        self.assertEqual(len(upload), 1, upload)
        self.assertIn("altool --upload-package", upload[0])
        self.assertIn("SwiftHFR.ipa", upload[0])
        self.assertEqual(self.counter.read_text(), "4\n")


if __name__ == "__main__":
    unittest.main()
