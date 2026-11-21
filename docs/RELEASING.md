# Releasing Clean My Life

This is the short path from a green `main` to a GitHub release and a live site.
Signing is optional for the first beta; the workflow supports a Developer ID
build when the secrets are present.

## 1. Before the tag

```bash
swift build
swift test
bash scripts/check-version-sync.sh
python3 site/tools/check.py
scripts/live-malware-scan.sh balanced
```

The live scan is the one that catches false alarms in the malware rules. Run at
least `balanced` on a real Mac before a release; `deep` before a stable release.

The two source-text guard tests also matter:

- `MenuBarLauncherTests.testQuitMonitorSetsSharedUserQuitFlag`
- `NoEmptyButtonActionsTests.testNoViewHasAnEmptyButtonAction`

Fix the source or the test, never skip them.

## 2. Bump the version

`VERSION` and `MCConstants.appVersion` must match:

```bash
printf '0.1.1\n' > VERSION
# Edit Sources/MacCleanKit/Constants.swift: appVersion = "0.1.1"
bash scripts/check-version-sync.sh
```

Update `CHANGELOG.md` in the same commit.

## 3. Build a local DMG

```bash
BUILD_ARCHS="--arch arm64" bash scripts/build-dmg.sh --app-only   # quick app bundle
bash scripts/build-dmg.sh                                         # DMG
```

The output is `.build/dmg/CleanMyLife-<version>.dmg`. Without a signing identity
the build is ad-hoc signed and macOS will ask for confirmation on first launch.
The README and the site both document the quarantine command.

## 4. Signing (optional, recommended)

The release workflow imports a Developer ID certificate from repository secrets
and notarizes both the app and the DMG. Required secrets:

| Secret | What it is |
| --- | --- |
| `APPLE_DEVELOPER_ID` | `Developer ID Application: Name (TEAMID)` |
| `DEVID_CERT_P12_BASE64` | The `.p12` certificate and key, base64 encoded |
| `DEVID_CERT_PASSWORD` | The `.p12` export password |
| `KEYCHAIN_PASSWORD` | Any throwaway password for the CI keychain |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_KEY_P8_BASE64` | The `.p8` key, base64 encoded |

Also replace `MCConstants.teamIdentifier` and the XPC requirement with your own
team before shipping a signed helper build. The current value belongs to
the upstream project.

For the 0.1.0 beta, signing was not configured. The workflow falls back to an
ad-hoc build and the GitHub release is marked as a pre-release.

## 5. Publish

```bash
git tag v0.1.0
git push origin v0.1.0
```

A tag containing a hyphen is published as a pre-release. A stable tag must match
`VERSION`. The workflow builds, tests, signs when it can, and attaches the DMG to
the release.

## 6. Landing site

`.github/workflows/pages.yml` publishes the `site/` folder on every push to
`main` that changes it. One-time setup in the repository:

1. Settings, Pages, Build and deployment, Source: **GitHub Actions**.
2. Push a change under `site/`, or run the workflow manually.
3. The site appears at `https://itchyparrot53.github.io/clean-my-life/`.

The page uses relative asset paths, so it works from a project path without a
build step.

## 7. Homebrew cask

The cask lives in `Casks/clean-my-life.rb`. After a release, replace `:no_check`
with the DMG's SHA-256 and the tag's version:

```bash
shasum -a 256 .build/dmg/CleanMyLife-<version>.dmg
```

To let people install it before a tap exists:

```bash
brew install --cask ./Casks/clean-my-life.rb
```

## 8. After launch

- Check the release page and the site on a phone.
- Install the DMG on a clean user account and grant Full Disk Access.
- Run Quick and Balanced scans; confirm the coverage line reports rules and
  startup items.
- Watch the first day of issues for false positives; add a regression test and a
  rule note before changing a heuristic.
