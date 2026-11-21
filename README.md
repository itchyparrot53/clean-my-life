<div align="center">

<img src="docs/brand/readme-hero.png" width="100%" alt="Clean My Life: the open-source Mac cleaner, optimizer and malware scanner" />

![Status](https://img.shields.io/badge/status-public%20beta-c86c8e?style=for-the-badge&labelColor=241a30)
![Platform](https://img.shields.io/badge/macOS-14%2B-7c5cff?style=for-the-badge&labelColor=241a30)
![Swift](https://img.shields.io/badge/Swift-6-f05138?style=for-the-badge&logo=swift&logoColor=white&labelColor=241a30)
![Licence](https://img.shields.io/badge/licence-BSD--3--Clause-2ea44f?style=for-the-badge&labelColor=241a30)
![Telemetry](https://img.shields.io/badge/telemetry-none-5ee6c8?style=for-the-badge&labelColor=241a30)
[![Tests](https://img.shields.io/github/actions/workflow/status/itchyparrot53/clean-my-life/ci.yml?branch=main&style=for-the-badge&label=tests&labelColor=241a30)](https://github.com/itchyparrot53/clean-my-life/actions/workflows/ci.yml)

</div>

> [!IMPORTANT]
> 0.1.0 is the first public beta of the Clean My Life fork. Back up anything important and pin a release tag. The app is not notarized yet: a downloaded build needs one extra step, described under [Install](#install).

<a name="what-is-clean-my-life"></a>

## What is Clean My Life?

Clean My Life is a free, open-source Mac cleaner, optimizer and malware scanner. It is an independent fork with a rebuilt interface, four new cleanup tools, and a much deeper malware engine.

It is built natively with Swift 6 and SwiftUI: one app, one menu-bar helper, no Electron, no account, no subscription and no telemetry.

- **25 tools** across cleanup, protection, performance, applications, files and disk insight.
- **Trash-first deletion** with a protected-path guard, symlink checks and a per-item safety rationale.
- **Real malware depth**: Apple's full XProtect rule set, Elastic's macOS YARA rules, startup-item and browser-extension audits, and a Deep scan that opens disk images, installers and zips.
- **BSD-3-Clause**, with upstream and third-party credits in [NOTICE](NOTICE) and [LICENSE](LICENSE).

<a name="why-clean-my-life"></a>

## Why Clean My Life?

- **Your files stay yours.** Cleaning is local. There is no analytics, no crash reporter, no account and no server to phone home to. The only optional network call is the MalwareBazaar hash feed, and you have to add your own free key.
- **It tells you why.** Every flagged item carries a reason, and anything that is a judgement call starts unchecked. Confirmed Apple signatures are the only things pre-selected.
- **It does not pretend to be an antivirus.** Exact hashes and published rules catch known families. A brand-new, never-seen sample can still get through, and the app says so instead of promising total protection.
- **Nothing is hidden behind a paywall.** Every module, including the malware engine, is here and free.
- **The safety model is testable.** More than 1,000 tests, including adversarial path handling and live end-to-end scans in temporary folders.

<a name="whats-inside"></a>

## What's inside

<div align="center">
  <img src="assets/app_icon.png" width="180" alt="Clean My Life app icon: a lilac and pink eraser" />
</div>

| Area | Tools |
| --- | --- |
| **Checkup** | Smart Scan: one click runs cleanup, protection and performance modules, then shows what each one found |
| **Cleanup** | System Junk (20+ categories), AI Clutter, Downloads, Similar Photos, Screenshots, Mail Attachments, Trash Bins, Project Junk, Disk Hogs, Clean History (one-click Restore) |
| **Protection** | Malware Removal, Privacy, Browser Extensions, Saved Wi-Fi, Permissions Overview |
| **Performance** | Optimization (login items), Maintenance (system tasks) |
| **Applications** | Uninstaller (+ Reset to Defaults), Unused Apps, Extensions, Updater |
| **Files** | Space Lens (disk treemap), Large & Old Files, Duplicates (+ Consolidate), Shredder |
| **Menu bar** | Live CPU, memory, disk and battery, network and swap, an actionable recommendation, and the last malware scan |

<details>
<summary><strong>Cleanup, in detail</strong></summary>

<br>

- **System Junk.** Caches, logs, language files, broken preferences and login items, document versions, iOS backups, Xcode junk, package-manager and IDE caches, deleted-user leftovers, Universal Clipboard archives, and Universal Binary thinning. Anything irreversible is listed for review, never pre-selected.
- **AI Clutter.** Caches and logs from Claude, ChatGPT, Perplexity and LM Studio, plus local model files from Ollama, LM Studio and Hugging Face. Models are listed for review; deleting one means downloading it again.
- **Downloads.** Everything at the top of `~/Downloads`, grouped by the app that downloaded it, with installers and duplicate downloads called out.
- **Similar Photos.** Finds bursts and near-identical shots and adds the extras to an album. Photos-library items are never deleted.
- **Screenshots.** Finds screenshots, keeps the recent ones, and lets you remove the rest.
- **Mail Attachments.** Cached attachments from Apple Mail, Outlook and Spark.
- **Trash Bins.** Empties every Trash, including external drives.
- **Project Junk.** `node_modules`, `.next`, `dist`, Rust and Maven `target`, Gradle `build`, Python virtualenvs and CocoaPods `Pods`. A folder only counts when the files beside it confirm the project type.
- **Disk Hogs.** Docker and Xcode simulator space. Stopped containers, dangling images and old runtimes each sit behind a confirmation; volumes and the newest runtime are never touched.
- **Clean History.** The last 30 days of cleans, stored locally, with one-click Restore from the Trash.

</details>

<details>
<summary><strong>Applications and files, in detail</strong></summary>

<br>

- **Uninstaller.** Finds associated files across 17+ Library locations, including apps nested in vendor subfolders. Also **Reset to Defaults**, which wipes an app's caches and preferences while keeping the app.
- **Unused Apps.** Uses Spotlight's last-used date and never lists a running app. If Spotlight has no usage data, it says so instead of guessing.
- **Updater.** Reads other apps' own Sparkle feeds. It sends nothing about you.
- **Space Lens.** A squarified treemap of disk usage with drill-down.
- **Duplicates.** Progressive detection (size, partial hash, full hash, inode check) plus **Consolidate**, which reclaims space with APFS copy-on-write clones and deletes nothing.
- **Shredder.** Standard, permanent and secure-overwrite erasure.

</details>

<a name="malware"></a>

## The malware engine

This is the part that changed most in the fork. The old scanner matched exact file hashes and a short adware-name list. It now evaluates Apple's full rule set and Elastic's macOS rules, and checks the places malware actually restarts from.

### Three depths

| Depth | What it does | Typical time |
| --- | --- | --- |
| **Quick** | Launch agents and daemons, startup programs, browser extensions, and exact XProtect hashes. | seconds |
| **Balanced** (default) | Adds Application Support, `/Users/Shared`, every app in `/Applications`, every browser profile, Apple Remediator results and the YARA rules. | ~15 s |
| **Deep** | Adds every file in `/Applications` and `~/Downloads`, opens disk images, installer packages and zips in a temp folder, and checks mounted external drives. | minutes |

### What it checks

- **Apple XProtect hashes and rules.** The app reads the copy macOS keeps updated on disk. All rules are evaluated through YARA-X, not just the whole-file hashes: about 639 rules on the test machine, up from 32 hashes before.
- **Elastic Security macOS rules.** 141 macOS and cross-platform YARA rules, bundled with their licence and credited in Settings.
- **MalwareBazaar (opt-in).** Add your own free abuse.ch key and press Update. Requests send only the key and the query, never file hashes or paths. A match on properly signed code is dropped.
- **Apple's Safari extension blocklist**, plus a **full browser-extension audit**: every Chromium profile and Firefox, with the install source and permissions that matter (reading every site, proxying traffic, attaching a debugger, controlling other extensions).
- **Persistence**, not just launch agents: background items macOS tracks, login items, cron jobs, shell startup files (`.zshrc`, `.zprofile`, `.bash_profile`), periodic scripts, login hooks, authorization plugins, kernel extensions, Quick Look plug-ins, and browser policies. Configuration profiles that change your home page or search engine are surfaced as "Worth a look", never deleted.
- **Code trust**: unsigned, ad-hoc signed, broken or revoked signatures, Developer ID without notarization, quarantined downloads, hidden folders, Apple-lookalike labels, and `DYLD_INSERT_LIBRARIES`.
- **Apple's own protection state**: the installed XProtect version and what Apple's 25 background remediators last found.

### What it deliberately does not do

- It is **not an antivirus**. There is no behavioural monitoring, no cloud sandbox and no zero-day guarantee. Unknown or heavily modified samples can be missed.
- It does not delete files inside a disk image, package or zip. It reports the container and you decide.
- It does not pre-select guesses. Only confirmed Apple signatures are ticked by default.
- YARA pattern rules need `yara-x` (`brew install yara-x`). Without it the hash and heuristic checks still work, and the app says pattern rules are off.

<a name="install"></a>

## Install

### Download

Grab the latest DMG from [Releases](https://github.com/itchyparrot53/clean-my-life/releases/latest). The 0.1.0 build is ad-hoc signed, so macOS will ask you to confirm the first launch:

```bash
xattr -dr com.apple.quarantine "/Applications/Clean My Life.app"
open "/Applications/Clean My Life.app"
```

Notarization needs a Developer ID certificate and is wired for CI, not for this first build. Building from source avoids the warning entirely.

### Build from source

Requirements: macOS 14 or later, Xcode 16 or later (Swift 6), and optionally YARA-X for pattern rules.

```bash
git clone https://github.com/itchyparrot53/clean-my-life.git
cd clean-my-life
brew install yara-x          # optional, enables the pattern-rule pass
swift build
swift test                   # full suite; the live scan is opt-in
bash scripts/build-dmg.sh --app-only
```

The local app bundle lands in `.build/dmg/Clean My Life.app`. `scripts/build-dmg.sh` without `--app-only` also builds a DMG.

### Homebrew

The cask lives in the repo until a tap is published:

```bash
brew install --cask ./Casks/clean-my-life.rb
```

### Full Disk Access

Mail Attachments, Privacy and parts of the malware scan read protected folders. Grant access in **System Settings → Privacy & Security → Full Disk Access**, add **Clean My Life.app**, then restart the app.

<a name="privacy"></a>

## Privacy

- **No telemetry.** No analytics, no crash reporting, no account, no device fingerprint.
- **No hidden network calls.** The only optional outbound paths are the MalwareBazaar hash download (after you add your own key), other apps' update feeds when you open the Updater, and the release feed if a signed build is configured with one.
- **No file contents leave the Mac.** Scan results and file lists stay local.
- **One Apple check is disclosed.** If a MalwareBazaar hash matches a signed file, macOS asks Apple whether its signing certificate was revoked, the same OCSP check Gatekeeper makes. That request is about the certificate, not your files.
- **Local history only.** Clean History is a JSON file under `~/Library/Logs/MacClean/`, readable by your user.

### Verify no telemetry yourself

The repository ships a checker that inspects the built bundle, not just the source:

```bash
bash scripts/check-network-surface.sh "/Applications/Clean My Life.app"
```

It covers the main app and every bundled helper: `Sparkle.framework`, `Autoupdate`, `Updater.app`, `Downloader.xpc` and `Installer.xpc`.

You can also watch the live process. This snapshot selects PIDs by executable paths inside the chosen app bundle, so an unrelated Installer or Updater is excluded:

```bash
(
CML_APP=$(cd "/Applications/Clean My Life.app" && pwd -P) || exit 1
CML_PIDS=$(ps -ww -axo pid=,comm= | awk -v bundle="$CML_APP/" '
  { pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
    if (index($0, bundle) == 1) print pid }' | paste -sd, -)
if [ -n "$CML_PIDS" ]; then
  ps -p "$CML_PIDS" -o pid=,comm=
  lsof -nP -a -p "$CML_PIDS" -i
else
  echo "No running executables from this Clean My Life bundle"
fi
)
```

Run it while the app is idle and again while you press Update Now on the MalwareBazaar feed. An idle app opens no sockets.

<a name="docs"></a>

## Documentation

- [Malware engine](docs/MALWARE.md)
- [Testing](docs/TESTING.md)
- [Releasing](docs/RELEASING.md)
- [In-app updates](docs/IN_APP_UPDATES.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

<a name="support"></a>

## Support

Questions and setup help go to [GitHub Discussions](https://github.com/itchyparrot53/clean-my-life/discussions). Bugs and feature requests go to [GitHub Issues](https://github.com/itchyparrot53/clean-my-life/issues). Vulnerabilities go through the private advisory in [SECURITY.md](SECURITY.md).

This is a best-effort project. There is no SLA and no hosted support.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, and follow the [Code of Conduct](CODE_OF_CONDUCT.md). Run `swift test` before you push. The live scan is opt-in:

```bash
scripts/live-malware-scan.sh quick      # or balanced / deep
```

## Licence

BSD-3-Clause. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Clean My Life is an independent fork; it is not affiliated with Apple or with the upstream maintainers.

### Third-party notices

- **YARA-X** by VirusTotal, BSD-3-Clause. Runs as a separate helper process.
- **Elastic protections-artifacts**, Elastic License 2.0. The bundled macOS rules keep their notice in [`Sources/MacClean/MalwareRules/`](Sources/MacClean/MalwareRules/NOTICE.md).
- **Apple XProtect** rules are read from macOS at runtime and are not redistributed.

<div align="center">
  <sub>Built with Swift 6, SwiftUI and YARA-X. No subscription, no telemetry, no dark patterns.</sub>
</div>
