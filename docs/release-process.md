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

Nobody edits `MARKETING_VERSION`, moves changelog entries or pushes tags. Merging the release PR is the whole release.

1. Merge PRs as normal, each with its line under `## [Unreleased]`. Nothing ships. After each merge, `.github/workflows/release-pr.yml` opens or updates one `[Chore] Release <version>` PR from the `release/next` branch. It:
   - sets `MARKETING_VERSION` to the version `scripts/next-version.py` calls for, and bumps `CURRENT_PROJECT_VERSION`
   - moves the Unreleased entries under `## [<version>] - <date>`, with a release link

   The branch is rebuilt from `main` after every merge, so it's always up to date and the version always covers everything merged. Don't edit it: change `## [Unreleased]` in a normal PR instead. To refresh the release date, run **Actions → Release PR → Run workflow**.

   CI's **Release check** says what each PR does: "Merging this updates the Release <version> PR" on a normal PR, and "This change releases <version>" on the release PR, the only PR that changes `MARKETING_VERSION`. CI's **Changelog check** fails a PR that adds entries to an existing release section. If a feature branch was cut before the release PR merged, its line can otherwise end up in the release that just shipped without it (#125).
2. When you want to ship, click **Approve workflows to run** on the release PR, then approve and merge it once CI is green. GitHub holds CI on PRs opened by the workflow token until someone approves it, and the PR can't merge without those checks. The push to `main` starts `.github/workflows/release.yml`, which runs these jobs in order. Each starts only if the one before it passed.
   - **Plan** (Linux): sees that `v<version>` isn't released yet, so this push is a release. It checks:
     - the commit is on `main`
     - the version isn't already published
     - no leftover tag points at another commit. A tag without a release fails the run with the command to delete it.
     - the changelog calls for this version

     On any other push to `main` the version is already released, so Plan stops the run here.
   - **CI**: all of `ci.yml` on the merged commit (lint, core tests on Linux, then app and UI tests on macOS 15)
   - **build** (macOS 15, read-only token): builds a universal Release app, signs and notarises it (or ad-hoc signs it), then zips it and uploads the zip as an artifact
   - **verify** (macOS 15 and macOS 26, read-only token): on each OS, checks the checksum and `codesign --verify --strict` (plus `spctl` for signed builds), launches the app, and runs the Homebrew round trip
   - **publish** (Linux, write token):
     - creates the GitHub Release and its `v<version>` tag on the merged commit. It's a pre-release when unsigned.
     - commits `[Chore] Update Homebrew cask to <version>` straight to `main`, so Homebrew users get the release on their next `brew update`. See [Homebrew cask](#homebrew-cask).
     - starts the Screenshots workflow on the new tag, which refreshes the README screenshots
3. Check the release:

   ```bash
   brew update && brew upgrade --cask strata-inspector
   ```

If a job fails, nothing is published and no tag is created. Fix the cause, then go to **Actions → Release → Run workflow** on `main`, with the version and `publish` ticked, to retry. Merging any other PR first also retries it, because Plan releases whatever unreleased version `main` declares.

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

## Homebrew cask

The tap is this repository, so the cask has to change on `main`. The `main` ruleset needs a pull request with passing checks, and the workflow token can't bypass that. Instead, Publish pushes the cask commit with a deploy key:

- **Deploy key** "Release: Homebrew cask", with write access. Its private half is the `CASK_DEPLOY_KEY` repository secret.
- **Ruleset:** "Deploy keys" is on the `main branch` ruleset's bypass list, next to the repository owner. That key is the only deploy key.

Publish commits only `Casks/strata-inspector.rb`, rendered from the template that Verify just installed and zapped. If `main` moved since it fetched, it rebases and retries. GitHub's SSH host keys come from `api.github.com/meta`. The push to `main` starts the usual push workflows, and each finds nothing to do.

If the secret is missing or the push still fails, Publish opens a `[Chore] Update Homebrew cask to <version>` PR instead, with a warning on the run. The release itself is already out. Click **Approve workflows to run** on that PR, then merge it once it's green.

To rotate the key, delete it under **Settings → Deploy keys**, then add a new one with write access and put its private half in `CASK_DEPLOY_KEY`:

```bash
ssh-keygen -t ed25519 -N "" -C strata-release-cask -f cask-key
gh repo deploy-key add cask-key.pub --allow-write --title "Release: Homebrew cask"
gh secret set CASK_DEPLOY_KEY < cask-key
rm cask-key cask-key.pub
```

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/build-release.sh` | Generates the project and builds a universal Release app to `build/Release/Strata.app` |
| `scripts/sign-and-notarize.sh` | Developer ID signing and notarisation, or an ad-hoc fallback |
| `scripts/next-version.py [--check <version>] [--against <base changelog>]` | Prints the next version from the changelog, checks a release version against it (Release PR, Plan and CI's Release check), or refuses new entries in existing releases (CI's Changelog check) |
| `scripts/package-release.sh <version>` | Zips the app to `dist/` with a `.sha256` file and checks the version |
| `scripts/smoke-test-app.sh <app>` | Launches the app headlessly and checks it stays up |
| `scripts/render-cask.sh <version> <sha256> [url]` | Writes the cask from `packaging/strata-inspector.rb.template` |
| `scripts/cask-smoke-test.sh <version> <zip>` | Homebrew install, launch, uninstall, reinstall and zap round trip |

## Rolling back

Delete the GitHub Release, revert the cask commit, then merge the fix with a `### Fixed` entry and merge the release PR it produces. Never re-tag an existing version. Homebrew users may have already installed it, and the checksum in their cask would stop matching.
