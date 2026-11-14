# Testing

## Suites

| Suite | Runs on | Covers |
| --- | --- | --- |
| `StrataCoreTests` | Linux and macOS | Every scanner and precedence rule, against fixture folders built in a temporary directory. Includes the secret-masking guarantee (no planted credential appears anywhere in an encoded report), import cycles, malformed JSON and frontmatter, and a 5,000-item filtering speed check. |
| `StrataTests` | macOS | `AppModel`: repository persistence, moved and missing folders, scanning, filtering, and refresh batching. |
| `StrataUITests` | macOS | End-to-end flows: launch, empty state, following an issue to the overridden item, category switching. |
| `issue-title.test.mjs` | Node | The workflow that checks issue title prefixes. |

## Running locally

```bash
swift test --package-path Packages/StrataCore

cd App && xcodegen generate
xcodebuild test -project Strata.xcodeproj -scheme Strata -destination 'platform=macOS'

node --test .github/scripts/issue-title.test.mjs
```

UI tests launch the app with `-StrataUITesting` and point it at a fixture home folder through `STRATA_UITEST_HOME`. They never read your real configuration or saved repositories.

## Fixtures

Tests build their fixtures in code with the helpers in `Tests/StrataCoreTests/Support`, rather than committing fixture folders. That keeps each test's setup next to its assertions, and it means no fixture can ever contain a real credential. Fake secrets in tests are obviously fake, such as `sk-ant-api03-SECRETSECRET…`.

## CI

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:

- **Lint:** actionlint, shellcheck, SwiftLint `--strict`, and the issue-title tests.
- **Core (Linux):** checks StrataCore has no package dependencies, builds with warnings as errors, and runs the core tests.
- **App (macOS):** runs the core tests on macOS, then generates the project and runs the app and UI tests, then `xcodebuild analyze`.
  - Test counts are posted as check annotations, along with the name of every failing test.
  - The `.xcresult` bundle is uploaded as an artifact.
- **Dependency review:** runs once the dependency graph is enabled (see #21).

`.github/workflows/release.yml` adds the packaging checks on any PR that touches `scripts/` or `packaging/`:

- a universal Release build
- signing, or the ad-hoc fallback
- a launch smoke test of the zipped app
- a Homebrew round trip (install, uninstall, reinstall, zap), checking that `~/.claude` is untouched

## Screenshots

`ScreenshotTests` is a UI test that is skipped unless `STRATA_SCREENSHOTS=1` is set. The Screenshots workflow sets it, captures the window against a made-up configuration, and force-pushes the images to the `screenshots` branch, which the README embeds. Pull requests that change the capture publish to `screenshots-preview` instead, so the result can be checked before merging.

## What tests can't prove

The tests check Strata's reading of the documented rules. They can't check that Claude Code itself behaves as documented, and they can't observe a running session. When the documentation changes, update [configuration-resolution.md](configuration-resolution.md) and the matching fixture test together.
