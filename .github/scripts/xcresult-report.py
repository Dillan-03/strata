"""Posts an xcresult bundle's test counts and every failing test as GitHub Actions annotations.

Usage: python3 xcresult-report.py <path.xcresult> <title>
Step logs can't be read through the checks API, so annotations are how failures are seen.
"""
import json
import subprocess
import sys


def xcresult(kind: str, path: str) -> dict:
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", path, "--compact"],
        capture_output=True, text=True, check=False,
    )
    return json.loads(output.stdout) if output.returncode == 0 and output.stdout else {}


def failures(node: dict, trail: list[str]):
    name, kind = node.get("name", ""), node.get("nodeType", "")
    if kind == "Test Case" and node.get("result") == "Failed":
        messages = [child.get("name", "") for child in node.get("children", []) if child.get("nodeType") == "Failure Message"]
        yield "/".join(trail[-1:] + [name]), " | ".join(messages)[:900] or "no message"
    for child in node.get("children", []):
        yield from failures(child, trail + ([name] if kind == "Test Suite" else []))


def main() -> None:
    path, title = sys.argv[1], sys.argv[2]
    summary = xcresult("summary", path)
    if not summary:
        print(f"::warning title={title}::No test results in {path}")
        return
    print(
        f"::notice title={title}::result={summary.get('result')} total={summary.get('totalTestCount')} "
        f"passed={summary.get('passedTests')} failed={summary.get('failedTests')} skipped={summary.get('skippedTests')}"
    )
    for root in xcresult("tests", path).get("testNodes", []):
        for test, detail in failures(root, []):
            print(f"::error title=Failed: {test}::{detail}")


if __name__ == "__main__":
    main()
