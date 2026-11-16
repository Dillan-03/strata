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

`scripts/next-version.py` prints the version the Unreleased entries call for, or exits 3 when there's nothing to release. `scripts/next-version.py --check <version>` refuses a release that doesn't match its entries, or one cut while Unreleased still has entries.

## Cutting a release

Merging a PR with changelog entries is the whole release. Nobody bumps versions or pushes tags.

1. Add the change's line under `## [Unreleased]` in its PR. CI's **Release check** annotates the PR with "Merging this releases <version>", or says it releases nothing.
2. Merge it once CI is green. The push to `main` starts `.github/workflows/release.yml`, which runs these jobs in order. Each starts only if the one before it passed.
   - **Plan** (Linux): picks the version `scripts/next-version.py` calls for. If Unreleased is empty, there's no release unless `MARKETING_VERSION` itself isn't released yet (a run that failed after committing its version), so Plan stops the run here. It checks:
     - the commit is on `main`
     - the version isn't already published
     - no leftover tag claims the version. A tag without a release fails the run with the command to delete it.
   - **CI**: all of `ci.yml` on the merged commit (lint, core tests on Linux, then app and UI tests on macOS 15)
   - **Commit version** (Linux, deploy key): sets `MARKETING_VERSION`, bumps `CURRENT_PROJECT_VERSION`, moves the Unreleased entries under `## [<version>] - <date>` with a release link, checks the result with `next-version.py --check`, and pushes `[Chore] Release <version> [skip ci]` to `main`. If another merge landed since the run started, the push is refused and the run for that newer push releases everything.
   - **build** (macOS 15, read-only token): builds a universal Release app from the version commit, signs and notarises it (or ad-hoc signs it), then zips it and uploads the zip as an artifact
   - **verify** (macOS 15 and macOS 26, read-only token): on each OS, checks the checksum and `codesign --verify --strict` (plus `spctl` for signed builds), launches the app, and runs the Homebrew round trip
   - **publish** (Linux, write token and deploy key):
     - creates the GitHub Release and its `v<version>` tag on the version commit. It's a pre-release when unsigned.
     - pushes `[Chore] Update Homebrew cask to <version> [skip ci]` to `main`
3. Check the release:

   ```bash
   brew update && brew upgrade --cask strata-inspector
   ```

Release tooling, CI and docs-only changes have no changelog entry, so merging them releases nothing.

If a job fails before **Commit version**, `main` is unchanged: fix the cause and merge the fix. If one fails after it, `main` already has the version commit. Fix the cause, then use **Re-run failed jobs** on the run, or **Actions → Release → Run workflow** on `main` with the version and `publish` ticked.

## Deploy key

The `main` ruleset requires a pull request for every change. The version and cask commits come from the workflow, so they're pushed with a deploy key that the ruleset lets bypass. Nothing else uses it.

- The **Release workflow** deploy key (Settings → Deploy keys) has write access.
- Its private half is the `RELEASE_DEPLOY_KEY` repository secret.
- The `main` ruleset lists **Deploy keys** as a bypass actor.

To rotate it:

```bash
ssh-keygen -t ed25519 -N '' -C "strata release workflow" -f release-key
gh repo deploy-key add release-key.pub --allow-write --title "Release workflow"
gh secret set RELEASE_DEPLOY_KEY < release-key
rm release-key release-key.pub
```

Then delete the old key under Settings → Deploy keys.

## Dry runs

- Any pull request that touches `scripts/`, `packaging/` or the release workflow runs Plan, build and verify without publishing. It skips the CI job, because the pull request's own CI run covers it.
- **Actions → Release → Run workflow** with `publish` unticked runs Plan, CI, build and verify for any branch. The zip is kept as a workflow artifact for 30 days.

With `publish` ticked, a manual run publishes `v<version>` from the commit being built. It refuses unless that commit is on `main`, the version isn't already published, and any existing tag points at that commit.

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
| `scripts/next-version.py [--check <version>]` | Prints the next version from the changelog, or checks a release version against it (Plan, Commit version and CI's Release check) |
| `scripts/package-release.sh <version>` | Zips the app to `dist/` with a `.sha256` file and checks the version |
| `scripts/smoke-test-app.sh <app>` | Launches the app headlessly and checks it stays up |
| `scripts/render-cask.sh <version> <sha256> [url]` | Writes the cask from `packaging/strata-inspector.rb.template` |
| `scripts/cask-smoke-test.sh <version> <zip>` | Homebrew install, launch, uninstall, reinstall and zap round trip |

## Rolling back

Delete the GitHub Release, revert the cask commit in a PR, then merge the fix with a `### Fixed` entry so the pipeline releases a new patch version. Never re-tag an existing version. Homebrew users may have already installed it, and the checksum in their cask would stop matching.
