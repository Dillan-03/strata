# Testing

## Suites

| Suite | Runs on | Covers |
| --- | --- | --- |
| `StrataCoreTests` | Linux and macOS | Every scanner and precedence rule, against fixture folders built in a temporary directory. Includes the secret-masking guarantee (no planted credential appears anywhere in an encoded report), import cycles, malformed JSON and frontmatter, files that are too large, not UTF-8 or unreadable, symlink loops, `CLAUDE_CONFIG_DIR`, and a 5,000-item filtering speed check. |
| `StrataTests` | macOS | `AppModel`: repository persistence, moved and missing folders, scanning, filtering, and refresh batching. |
| `StrataUITests` | macOS | End-to-end flows: launch, empty state, following an issue to the overridden item, category switching, filter chips sharing state with the Filter menu. |
| `issue-title.test.mjs` | Node | The workflow that checks issue title prefixes. |

## Measured results

From the CI run on `main` at commit `bee48c6` (17 November 2026), with everything planned for 0.3.0:

| Suite | Result |
| --- | --- |
| StrataCore on Linux (Swift 6.4) | 257 tests, 0 failures |
| StrataCore on macOS 15 (Xcode 16.4) | 257 tests, 0 failures |
| App and UI tests on macOS 15 | 60 tests: 59 passed, 1 skipped (`ScreenshotTests`, which runs only in the Screenshots workflow and passed there) |
| StrataCore line coverage (Linux) | 93.7% (5,231 of 5,583 lines) |

Release checks from the v0.1.0 dry run (PR #43) passed on macOS 15.8.2 and macOS 26.7.2: checksum, `codesign --verify --strict`, launch, and the Homebrew round trip. Each CI run posts its own counts and coverage as check annotations, so later numbers are always on the commit's checks.

Coverage is lowest in `ConfigItem` and `Diagnostic` (63–67%). Most of the uncovered lines are display titles and convenience accessors that the app tests exercise but Linux coverage doesn't count. The app target's coverage isn't measured.

## Running locally

```bash
swift test --package-path Packages/StrataCore

cd App && xcodegen generate
xcodebuild test -project Strata.xcodeproj -scheme Strata -destination 'platform=macOS'

node --test .github/scripts/issue-title.test.mjs
```

App and UI tests need an unlocked Mac. With the screen locked, `xcodebuild test` launches the test host but never starts a test, and waits until it's stopped. The core tests don't need a session.

UI tests launch the app with `-StrataUITesting` and point it at a fixture home folder through `STRATA_UITEST_HOME`. They never read your real configuration or saved repositories.

## Fixtures

Tests build their fixtures in code with the helpers in `Tests/StrataCoreTests/Support`, rather than committing fixture folders. That keeps each test's setup next to its assertions, and it means no fixture can ever contain a real credential. Fake secrets in tests are obviously fake, such as `sk-ant-api03-SECRETSECRET…`.

## CI

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`. The Release workflow also runs all of it before building a release.

- **Lint:** actionlint, shellcheck, SwiftLint `--strict`, the issue-title tests and the version script tests. Its **Release check** says what merging does: updates the release PR to the version the Unreleased entries call for, releases, or nothing. It counts as releasing only when the change itself sets a new `MARKETING_VERSION`, as the release PR does, and then also runs `scripts/next-version.py --check`. Its **Changelog check** fails a pull request that adds entries to a release section that already exists (`next-version.py --against`), so a merge can't drop a new line into a version that shipped without it. A changelog the script can't read fails both checks before it merges.
- **Core (Linux):** checks StrataCore has no package dependencies, builds with warnings as errors, and runs the core tests.
- **Changes:** decides whether the macOS app tests are needed. A pull request runs them only if it changes `App/`, `Packages/`, `ci.yml` or `.github/scripts/xcresult-report.py`. Every other run tests the app. An annotation says which, and why.
- **App (macOS):** runs the core tests on macOS, then generates the project and runs the app and UI tests, then `xcodebuild analyze`. When Changes skips it, it shows as skipped, which still counts as passing for a required check.
  - Test counts are posted as check annotations, along with the name of every failing test.
  - The `.xcresult` bundle is uploaded as an artifact.
- **Dependency review:** runs once the dependency graph is enabled (see #21).

`.github/workflows/release.yml` adds the packaging checks on any PR that touches `scripts/` or `packaging/`:

- a universal Release build
- signing, or the ad-hoc fallback
- a launch smoke test of the zipped app
- a Homebrew round trip (install, uninstall, reinstall, zap), checking that `~/.claude` is untouched

## Screenshots

`ScreenshotTests` is a UI test that is skipped unless `STRATA_SCREENSHOTS=1` is set. The Screenshots workflow sets it, captures the window against a made-up configuration, and force-pushes the images to the `screenshots` branch, which the README embeds. It runs only on pushes to `main`, not on pull requests, to save macOS runners. To see a branch's screenshots before merging, run it by hand from **Actions → Screenshots → Run workflow** on that branch. Only `main` publishes, so a branch run keeps its images as a workflow artifact for 14 days.

## What tests can't prove

The tests check Strata's reading of the documented rules. They can't check that Claude Code itself behaves as documented, and they can't observe a running session. When the documentation changes, update [configuration-resolution.md](configuration-resolution.md) and the matching fixture test together.
