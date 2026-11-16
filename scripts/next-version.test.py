#!/usr/bin/env python3
"""Tests for scripts/next-version.py. Run: python3 scripts/next-version.test.py"""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "next-version.py"
spec = importlib.util.spec_from_file_location("next_version", SCRIPT)
next_version = importlib.util.module_from_spec(spec)
# dataclasses look the module up by name while the file is still loading.
sys.modules[spec.name] = next_version
spec.loader.exec_module(next_version)


def changelog(unreleased: str = "", *releases: tuple) -> str:
    parts = ["# Changelog\n\nIntro text.\n", f"## [Unreleased]\n\n{unreleased}\n"]
    parts += [f"## [{version}] - 2026-11-14\n\nSummary line.\n\n{body}\n" for version, body in releases]
    parts.append("[0.1.0]: https://github.com/Dillan-03/strata/releases/tag/v0.1.0\n")
    return "\n".join(parts)


def upcoming(body: str, previous: str = "0.1.0") -> str:
    return changelog(body, (previous, "### Added\n\n- First release."))


class NextVersionTests(unittest.TestCase):
    def next(self, text: str) -> str:
        return next_version.next_version(next_version.parse(text))[0]

    def test_fixed_only_is_a_patch(self):
        self.assertEqual(self.next(upcoming("### Fixed\n\n- A crash.")), "0.1.1")

    def test_security_is_a_patch(self):
        self.assertEqual(self.next(upcoming("### Security\n\n- A leak.")), "0.1.1")

    def test_added_is_a_minor_and_resets_the_patch(self):
        self.assertEqual(self.next(upcoming("### Added\n\n- A feature.\n\n### Fixed\n\n- A crash.", "0.1.3")), "0.2.0")

    def test_changed_and_deprecated_are_minor(self):
        self.assertEqual(self.next(upcoming("### Changed\n\n- A tweak.")), "0.2.0")
        self.assertEqual(self.next(upcoming("### Deprecated\n\n- An old flag.")), "0.2.0")

    def test_breaking_after_1_0_is_a_major(self):
        text = upcoming("### Changed\n\n- **Breaking:** Requires macOS 26.", "1.4.2")
        self.assertEqual(self.next(text), "2.0.0")

    def test_removed_after_1_0_is_a_major(self):
        self.assertEqual(self.next(upcoming("### Removed\n\n- The old export.", "1.4.2")), "2.0.0")

    def test_breaking_before_1_0_is_a_minor(self):
        self.assertEqual(self.next(upcoming("### Fixed\n\n- **Breaking:** New backup format.", "0.3.1")), "0.4.0")

    def test_breaking_marker_spellings(self):
        for entry in ("- **Breaking:** x", "- **Breaking**: x", "- Breaking: x", "    - **Breaking:** nested"):
            with self.subTest(entry=entry):
                self.assertEqual(self.next(upcoming(f"### Fixed\n\n- A crash.\n{entry}", "1.0.0")), "2.0.0")

    def test_a_feature_named_breaking_news_isnt_breaking(self):
        self.assertEqual(self.next(upcoming("### Added\n\n- **Breaking news** banner.", "1.0.0")), "1.1.0")

    def test_neutral_heading_alone_is_nothing_to_release(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "Nothing to release"):
            self.next(upcoming("### Known limitations\n\n- Static only."))

    def test_empty_unreleased_is_nothing_to_release(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "Nothing to release"):
            self.next(upcoming("### Added\n"))

    def test_no_previous_release(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "no released version"):
            self.next(changelog("### Added\n\n- A feature."))

    def test_unknown_heading_names_the_line(self):
        with self.assertRaisesRegex(next_version.ChangelogError, r"CHANGELOG.md:\d+: unknown heading '### Fixd'"):
            next_version.parse(upcoming("### Fixd\n\n- A crash."))

    def test_entry_without_heading_is_rejected(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "isn't under a '### ' heading"):
            next_version.parse(upcoming("- A stray entry."))


class CheckTests(unittest.TestCase):
    def check(self, text: str, version: str) -> str:
        return next_version.check(next_version.parse(text), version)

    def released(self, body: str, version: str, previous: str = "0.1.0") -> str:
        return changelog("", (version, body), (previous, "### Added\n\n- First release."))

    def test_matching_minor(self):
        self.assertIn("minor bump: 0.2.0", self.check(self.released("### Added\n\n- A feature.", "0.2.0"), "0.2.0"))

    def test_feature_tagged_as_a_patch_is_refused(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "should be 0.2.0"):
            self.check(self.released("### Added\n\n- A feature.", "0.1.1"), "0.1.1")

    def test_fix_tagged_as_a_minor_is_refused(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "should be 0.1.1"):
            self.check(self.released("### Fixed\n\n- A crash.", "0.2.0"), "0.2.0")

    def test_graduating_to_1_0_from_any_0_x(self):
        self.assertIn("first stable release", self.check(self.released("### Fixed\n\n- A crash.", "1.0.0", "0.4.2"), "1.0.0"))

    def test_1_0_isnt_skipped_to_from_1_x(self):
        with self.assertRaises(next_version.ChangelogError):
            self.check(self.released("### Added\n\n- A feature.", "1.0.0", "1.2.0"), "1.0.0")

    def test_unreleased_entries_left_behind_are_refused(self):
        text = changelog("### Fixed\n\n- Forgot this.", ("0.2.0", "### Added\n\n- A feature."), ("0.1.0", "### Added\n\n- First."))
        with self.assertRaisesRegex(next_version.ChangelogError, "Unreleased still has entries"):
            self.check(text, "0.2.0")

    def test_version_not_the_newest_section(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "newest release is 0.1.0, not 0.2.0"):
            self.check(upcoming("### Added\n\n- A feature."), "0.2.0")

    def test_release_section_without_entries(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "has no entries"):
            self.check(self.released("### Known limitations\n\n- Static only.", "0.2.0"), "0.2.0")

    def test_first_release_needs_no_previous(self):
        self.assertIn("first release", self.check(changelog("", ("0.1.0", "### Added\n\n- First.")), "0.1.0"))

    def test_malformed_version(self):
        with self.assertRaisesRegex(next_version.ChangelogError, "isn't a version"):
            self.check(upcoming(""), "v0.2")


class RepositoryChangelogTests(unittest.TestCase):
    def test_changelog_uses_only_known_headings(self):
        path = SCRIPT.parent.parent / "CHANGELOG.md"
        self.assertTrue(next_version.releases(next_version.parse(path.read_text(encoding="utf-8"))))


class CommandLineTests(unittest.TestCase):
    def run_script(self, text: str, *arguments: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "CHANGELOG.md"
            path.write_text(text, encoding="utf-8")
            return subprocess.run([sys.executable, str(SCRIPT), "--changelog", str(path), *arguments],
                                  capture_output=True, text=True, check=False)

    def test_prints_only_the_version_on_stdout(self):
        result = self.run_script(upcoming("### Added\n\n- A feature."))
        self.assertEqual((result.returncode, result.stdout), (0, "0.2.0\n"))
        self.assertIn("minor bump", result.stderr)

    def test_check_failure_is_an_annotation_and_exit_1(self):
        text = changelog("", ("0.1.1", "### Added\n\n- A feature."), ("0.1.0", "### Added\n\n- First."))
        result = self.run_script(text, "--check", "0.1.1")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(result.stdout.startswith("::error title=Version check::0.1.1 doesn't match"))

    def test_missing_changelog_is_reported(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--changelog", "/nonexistent/CHANGELOG.md"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("::error title=Version check::", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
