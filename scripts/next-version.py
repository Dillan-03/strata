#!/usr/bin/env python3
"""Works out Strata's next version from CHANGELOG.md, or checks a release version against it.

Usage:
  scripts/next-version.py [--changelog PATH]              print the version the Unreleased entries call for
  scripts/next-version.py [--changelog PATH] --check X.Y.Z  fail unless X.Y.Z is the newest release and matches its entries

Exits 1 on a changelog error, and 3 when Unreleased has nothing to release.

Rules (semantic versioning):
  major  a "**Breaking:**" entry, or a "### Removed" section
  minor  "### Added", "### Changed" or "### Deprecated"
  patch  "### Fixed" or "### Security"
While the version is 0.x a breaking change bumps the minor number. 1.0.0 may follow any 0.x release.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

PATCH, MINOR, MAJOR = 1, 2, 3
LEVEL_NAMES = {PATCH: "patch", MINOR: "minor", MAJOR: "major"}
HEADING_LEVELS = {
    "Removed": MAJOR,
    "Added": MINOR,
    "Changed": MINOR,
    "Deprecated": MINOR,
    "Fixed": PATCH,
    "Security": PATCH,
}
# Headings that describe a release without changing what it is.
NEUTRAL_HEADINGS = {"Known limitations"}

SECTION = re.compile(r"^## \[(?P<name>[^\]]+)\]")
HEADING = re.compile(r"^### (?P<name>.+?)\s*$")
ENTRY = re.compile(r"^\s*[-*] \S")
BREAKING = re.compile(r"^\s*[-*] (\*\*Breaking:\*\*|\*\*Breaking\*\*:|Breaking:)")
VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


class ChangelogError(Exception):
    pass


class NothingToRelease(ChangelogError):
    pass


@dataclass
class Section:
    name: str
    entries: dict[str, list[str]] = field(default_factory=dict)

    @property
    def version(self) -> tuple[int, int, int] | None:
        match = VERSION.match(self.name)
        return tuple(int(part) for part in match.groups()) if match else None

    @property
    def has_entries(self) -> bool:
        return any(self.entries.values())

    def bump_level(self) -> tuple[int, str] | None:
        """The bump these entries call for and the reason, or None when nothing would change."""
        if any(BREAKING.match(line) for lines in self.entries.values() for line in lines):
            return MAJOR, "a **Breaking:** entry"
        levels = [(HEADING_LEVELS[name], f"### {name}") for name, lines in self.entries.items()
                  if lines and name in HEADING_LEVELS]
        return max(levels, key=lambda found: found[0]) if levels else None


def parse(text: str, path: str = "CHANGELOG.md") -> list[Section]:
    sections: list[Section] = []
    heading: str | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        if match := SECTION.match(line):
            sections.append(Section(match["name"]))
            heading = None
        elif match := HEADING.match(line):
            name = match["name"]
            if not sections:
                raise ChangelogError(f"{path}:{number}: '### {name}' comes before any '## [version]' section.")
            if name not in HEADING_LEVELS and name not in NEUTRAL_HEADINGS:
                allowed = ", ".join([*HEADING_LEVELS, *sorted(NEUTRAL_HEADINGS)])
                raise ChangelogError(f"{path}:{number}: unknown heading '### {name}'. Use one of: {allowed}.")
            heading = name
            sections[-1].entries.setdefault(name, [])
        elif ENTRY.match(line) and sections:
            if heading is None:
                raise ChangelogError(f"{path}:{number}: this entry isn't under a '### ' heading, so it can't be classified.")
            sections[-1].entries[heading].append(line)
    return sections


def format_version(version: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in version)


def bump(version: tuple[int, int, int], level: int) -> tuple[int, int, int]:
    major, minor, patch = version
    if level == MAJOR and major > 0:
        return major + 1, 0, 0
    if level >= MINOR:
        return major, minor + 1, 0
    return major, minor, patch + 1


def releases(sections: list[Section]) -> list[Section]:
    return [section for section in sections if section.version is not None]


def unreleased(sections: list[Section]) -> Section | None:
    return next((section for section in sections if section.name.lower() == "unreleased"), None)


def next_version(sections: list[Section]) -> tuple[str, str]:
    pending = unreleased(sections)
    found = pending.bump_level() if pending else None
    if found is None:
        raise NothingToRelease("Nothing to release: the Unreleased section has no entries under Added, Changed, "
                               "Deprecated, Removed, Fixed or Security.")
    released = releases(sections)
    if not released:
        raise ChangelogError("There's no released version in the changelog to bump from.")
    level, reason = found
    previous = released[0].version
    result = format_version(bump(previous, level))
    return result, f"{format_version(previous)} plus {reason} is a {LEVEL_NAMES[level]} bump: {result}."


def check(sections: list[Section], version: str) -> str:
    if not VERSION.match(version):
        raise ChangelogError(f"'{version}' isn't a version like 1.2.3.")
    released = releases(sections)
    if not released or released[0].name != version:
        newest = released[0].name if released else "nothing"
        raise ChangelogError(f"The changelog's newest release is {newest}, not {version}. "
                             f"Move the Unreleased entries under '## [{version}] - <date>' first.")
    pending = unreleased(sections)
    if pending and pending.has_entries:
        raise ChangelogError(f"Unreleased still has entries. Move them under '## [{version}]' before tagging.")
    if len(released) == 1:
        return f"{version} is the first release."
    found = released[0].bump_level()
    if found is None:
        raise ChangelogError(f"'## [{version}]' has no entries under Added, Changed, Deprecated, Removed, Fixed or Security.")
    level, reason = found
    previous = released[1].version
    expected = format_version(bump(previous, level))
    if version == expected:
        return f"{format_version(previous)} plus {reason} is a {LEVEL_NAMES[level]} bump: {version}."
    if version == "1.0.0" and previous[0] == 0:
        return f"{version} follows {format_version(previous)}: the first stable release."
    raise ChangelogError(f"{version} doesn't match the changelog: {format_version(previous)} plus {reason} "
                         f"is a {LEVEL_NAMES[level]} bump, so this release should be {expected}.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--changelog", default=str(Path(__file__).resolve().parent.parent / "CHANGELOG.md"))
    parser.add_argument("--check", metavar="VERSION", help="check a release version instead of printing the next one")
    arguments = parser.parse_args()
    try:
        path = Path(arguments.changelog)
        sections = parse(path.read_text(encoding="utf-8"), path.name)
        if arguments.check:
            print(f"::notice title=Version check::{check(sections, arguments.check)}")
        else:
            version, reason = next_version(sections)
            print(reason, file=sys.stderr)
            print(version)
    except NothingToRelease as error:
        print(error, file=sys.stderr)
        return 3
    except (ChangelogError, OSError) as error:
        print(f"::error title=Version check::{error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
