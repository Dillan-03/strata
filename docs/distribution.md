# Distribution

Strata ships as a zipped universal (Apple silicon and Intel) `Strata.app` attached to each GitHub Release, and as a Homebrew cask in this repository.

## Homebrew

This repository is its own tap, so no separate `homebrew-*` repository is needed.

```bash
brew tap dillan-03/strata https://github.com/Dillan-03/verbose-octo-carnival
brew install --cask dillan-03/strata/strata-inspector
```

Installing by the fully qualified name (`dillan-03/strata/strata-inspector`) trusts only that cask under Homebrew's [tap trust](https://docs.brew.sh/Tap-Trust) rules, which arrived in Homebrew 6. You don't need `brew trust dillan-03/strata`, and the short-name commands below work afterwards.

| Task | Command |
| --- | --- |
| Upgrade | `brew upgrade --cask strata-inspector` |
| Uninstall (keeps preferences) | `brew uninstall --cask strata-inspector` |
| Uninstall and remove Strata's own data | `brew uninstall --zap --cask strata-inspector` |
| Remove the tap | `brew untap dillan-03/strata` |

The cask is only usable once `Casks/strata-inspector.rb` exists on `main`. The Release workflow opens a pull request adding it after each release, so it appears after the first release's cask PR is merged.

### What uninstalling removes

`uninstall` removes `/Applications/Strata.app`. `--zap` also removes these, which belong only to Strata:

- `~/Library/Preferences/com.dillankerai.strata.plist` (saved repository list and settings)
- `~/Library/Preferences/com.dillankerai.strata.uitests.plist` (only exists if UI tests ran on the machine)
- `~/Library/Caches/com.dillankerai.strata`
- `~/Library/HTTPStorages/com.dillankerai.strata`
- `~/Library/Saved Application State/com.dillankerai.strata.savedState`

Neither ever touches `~/.claude`, `~/.claude.json`, managed settings, plugins, MCP configuration, instruction files, or your repositories. The release pipeline checks this on every build (see below).

## Signed and unsigned builds

Release notes always say which kind of build a release is.

- **Signed:** signed with a Developer ID Application certificate, notarised by Apple, and stapled. It opens normally.
- **Unsigned:** ad-hoc signed only, published as a GitHub *pre-release* with a warning in its notes. Gatekeeper blocks the first launch. Either right-click Strata in Finder and choose **Open**, or run:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Strata.app
  ```

Builds stay unsigned until the Apple credentials in [#22](https://github.com/Dillan-03/verbose-octo-carnival/issues/22) are added as repository secrets.

## Verifying a download

Each release includes `Strata-<version>.zip.sha256`.

```bash
shasum -a 256 -c Strata-0.1.0.zip.sha256
codesign --verify --deep --strict --verbose=2 /Applications/Strata.app
spctl --assess --type execute --verbose /Applications/Strata.app   # signed builds only
```

## What the pipeline verifies

`scripts/cask-smoke-test.sh` runs on every release, and on any pull request that changes packaging. It:

1. Renders the cask against the freshly built zip and runs `brew style` on it.
2. Installs it, launches the app, uninstalls, reinstalls, then zaps.
3. Checks the app and Strata's preferences are gone after the zap.
4. Plants a stand-in skill in `~/.claude/skills` beforehand, and fails if it changes at any step.
