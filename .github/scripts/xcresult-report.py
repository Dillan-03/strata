"""Posts an xcresult bundle's build errors, test counts and every failing test as GitHub Actions annotations.

Usage: python3 xcresult-report.py <path.xcresult> <title>
Step logs can't be read through the checks API, so annotations are how failures are seen.
"""
import json
import os
import subprocess
import sys
from urllib.parse import unquote


def xcresult(kind: str, path: str) -> dict:
    return run(["test-results", kind], path)


def run(command: list[str], path: str) -> dict:
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", *command, "--path", path, "--compact"],
        capture_output=True, text=True, check=False,
    )
    return json.loads(output.stdout) if output.returncode == 0 and output.stdout else {}


def build_errors(path: str):
    """Compile errors, with the file and line when the bundle has them. A build that fails runs no tests."""
    for error in run(["build-results"], path).get("errors", []):
        location = ""
        url = error.get("sourceURL", "")
        if url.startswith("file://"):
            file_path, _, fragment = url[len("file://"):].partition("#")
            fields = dict(part.split("=", 1) for part in fragment.split("&") if "=" in part)
            # xcresult line numbers start at 0.
            line = int(fields.get("StartingLineNumber", "0")) + 1
            location = f"file={os.path.relpath(unquote(file_path))},line={line},"
        message = " ".join(error.get("message", "").split())[:900]
        yield location, message


def failures(node: dict, trail: list[str]):
    name, kind = node.get("name", ""), node.get("nodeType", "")
    if kind == "Test Case" and node.get("result") == "Failed":
        messages = [child.get("name", "") for child in node.get("children", []) if child.get("nodeType") == "Failure Message"]
        yield "/".join(trail[-1:] + [name]), " | ".join(messages)[:900] or "no message"
    for child in node.get("children", []):
        yield from failures(child, trail + ([name] if kind == "Test Suite" else []))


def main() -> None:
    path, title = sys.argv[1], sys.argv[2]
    for location, message in build_errors(path):
        print(f"::error {location}title=Build error::{message}")
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
