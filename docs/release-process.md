# Release process

Releases are built entirely by `.github/workflows/release.yml`. Nothing is built or signed on a developer machine.

## Versioning

Strata follows [semantic versioning](https://semver.org/), and `CHANGELOG.md` decides which number goes up. Every user-facing change adds a line under `## [Unreleased]`, under one of these headings:

| Changelog | Bump | Example |
| --- | --- | --- |
| `### Fixed`, `### Security` | Patch: 0.2.**0** → 0.2.**1** | A crash fix |
| `### Added`, `### Changed`, `### Deprecated` | Minor: 0.**2**.0 → 0.**3**.0 | A new feature |
| `### Removed`, or an entry starting `**Breaking:**` | Major: **1**.4.0 → **2**.0.0 | Dropping a macOS version, a settings format old versions can't read |

The biggest bump wins. While the version is 0.x, a breaking change bumps the minor number instead, and 1.0.0 can follow any 0.x release when Strata is ready to promise stability. `### Known limitations` describes a release without changing its number. Any other heading is rejected, so a typo can't under-bump a release. Release tooling, CI and docs-only changes don't need an entry.

`scripts/next-version.py` prints the version the Unreleased entries call for. At release time, `scripts/next-version.py --check <version>` refuses a tag that doesn't match, or one cut while Unreleased still has entries.

## Cutting a release

1. Run `scripts/next-version.py` to get the version. Open a PR that sets `MARKETING_VERSION` to it (and bumps `CURRENT_PROJECT_VERSION`) in `App/project.yml`, and moves the `Unreleased` entries in `CHANGELOG.md` under `## [<version>] - <date>`. Merge it once CI is green.
2. Tag the merge commit on `main` and push the tag:

   ```bash
   version=0.2.0
   git switch main && git pull
   git tag -a "v$version" -m "Strata $version"
   git push origin "v$version"
   ```

3. The workflow runs:
   - **build** (macOS 15, read-only token):
     - checks the tag points at a commit on `main` and matches `MARKETING_VERSION`
     - checks the version is the one the changelog calls for
     - runs core and app unit tests
     - builds a universal Release app, signs and notarises it (or ad-hoc signs it)
     - zips it and uploads the zip as an artifact
   - **verify** (macOS 15 and macOS 26, read-only token): on each OS, checks the checksum and `codesign --verify --strict` (plus `spctl` for signed builds), launches the app, and runs the Homebrew round trip.
   - **publish** (Linux, write token):
     - creates the GitHub Release (a pre-release when unsigned)
     - opens a `[Chore] Update Homebrew cask to <version>` PR
4. Close and reopen the cask PR so CI runs on it. PRs opened with the workflow token don't trigger workflows. Merge it once green.
5. Check the release:

   ```bash
   brew update && brew upgrade --cask strata-inspector
   ```

## Dry runs

- Any pull request that touches `scripts/`, `packaging/` or the release workflow runs the build and verify jobs without publishing.
- **Actions → Release → Run workflow** with `publish` unchecked does the same for any branch. The zip is kept as a workflow artifact for 30 days.

With `publish` checked, a manual run publishes the existing tag `v<version>`. It refuses to run unless that tag points at the commit being built.

## Signing secrets

`scripts/sign-and-notarize.sh` signs only when all six of these repository secrets exist:

| Secret | Contents |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 of the Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID of an App Store Connect API key with Developer access |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID for that key |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64 of the `.p8` key file |

If any are missing it ad-hoc signs, emits a workflow warning, and records `unsigned`, so the release is labelled honestly. If they're present but wrong, the job fails rather than publishing. The certificate goes into a temporary keychain that is deleted when the step ends, and no secret value is ever echoed.

Setup steps are in [#22](https://github.com/Dillan-03/strata/issues/22). To confirm the secrets work, run a dry run and check that the Sign and notarise step logs `Signed, notarised and stapled.`.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/build-release.sh` | Generates the project and builds a universal Release app to `build/Release/Strata.app` |
| `scripts/sign-and-notarize.sh` | Developer ID signing and notarisation, or an ad-hoc fallback |
| `scripts/next-version.py [--check <version>]` | Prints the next version from the changelog, or checks a release version against it |
| `scripts/package-release.sh <version>` | Zips the app to `dist/` with a `.sha256` file and checks the version |
| `scripts/smoke-test-app.sh <app>` | Launches the app headlessly and checks it stays up |
| `scripts/render-cask.sh <version> <sha256> [url]` | Writes the cask from `packaging/strata-inspector.rb.template` |
| `scripts/cask-smoke-test.sh <version> <zip>` | Homebrew install, launch, uninstall, reinstall and zap round trip |

## Rolling back

Delete the GitHub Release, revert the cask PR, then cut a new patch version. Never re-tag an existing version. Homebrew users may have already installed it, and the checksum in their cask would stop matching.
