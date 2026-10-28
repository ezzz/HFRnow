"""Tests for scripts/check-lot-deps.py: row shape (9 cells, the last one the issue link) and module rules."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "check-lot-deps.py"
HEADER = "| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |\n|---|---|---|---|---|---|---|---|---|\n"


def row(lot: str, module: str, deps: str = "—", issue: str = "[#1](https://github.com/ezzz/HFRnow/issues/1)") -> str:
    return f"| LOT-{lot} | Scope | {module} | easy | Sonnet → Opus | {deps} | — | — | {issue} |\n"


class CheckLotDepsTests(unittest.TestCase):
    def run_script(self, table: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "LOTS.md"
            path.write_text(HEADER + table, encoding="utf-8")
            return subprocess.run([sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True, check=False)

    def test_valid_plan_passes(self):
        result = self.run_script(row("010", "HFRModels") + row("020", "HFRParsing", "010"))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("2 lots checked, 0 violation(s)", result.stdout)

    def test_issue_numbers_are_not_read_as_dependencies(self):
        result = self.run_script(row("010", "HFRModels", issue="[#123](https://github.com/ezzz/HFRnow/issues/123)"))
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_old_owner_and_status_columns_are_refused(self):
        old_row = "| LOT-010 | Scope | HFRModels | easy | Sonnet → Opus | — | — | — | — | todo |\n"
        result = self.run_script(old_row)
        self.assertEqual(result.returncode, 1)
        self.assertIn("row has 10 cells, expected 9", result.stdout)

    def test_forbidden_module_dependency_fails(self):
        result = self.run_script(row("036", "HFRParsing") + row("040", "HFRNetwork", "036"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("forbidden by the module rules", result.stdout)

    def test_unknown_dependency_fails(self):
        result = self.run_script(row("020", "HFRParsing", "999"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("depends on unknown LOT-999", result.stdout)


if __name__ == "__main__":
    unittest.main()
