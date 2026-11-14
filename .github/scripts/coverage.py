"""Summarises line coverage of StrataCore's sources from `swift test --enable-code-coverage` output.

Usage: python3 coverage.py <codecov json>
Prints a GitHub Actions notice with the total and the three least-covered files.
"""
import json
import sys


def summarise(report: dict, marker: str = "/Sources/StrataCore/") -> tuple[int, int, list[tuple[float, str]]]:
    covered = total = 0
    files = []
    for entry in report["data"][0]["files"]:
        name = entry["filename"]
        if marker not in name:
            continue
        lines = entry["summary"]["lines"]
        covered += lines["covered"]
        total += lines["count"]
        if lines["count"]:
            files.append((100 * lines["covered"] / lines["count"], name.split(marker, 1)[1]))
    return covered, total, sorted(files)[:3]


def main() -> None:
    with open(sys.argv[1]) as handle:
        covered, total, lowest = summarise(json.load(handle))
    if not total:
        print("::error title=Coverage::No StrataCore source files in the coverage report")
        sys.exit(1)
    least = ", ".join(f"{path} {percent:.0f}%" for percent, path in lowest)
    print(f"::notice title=StrataCore line coverage (Linux)::{100 * covered / total:.1f}% ({covered} of {total} lines). Lowest: {least}")


if __name__ == "__main__":
    main()
