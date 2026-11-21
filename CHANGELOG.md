# Changelog

All notable changes to Clean My Life are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
semantic versioning after 1.0.

Clean My Life is a fork of [Clean My Life](https://github.com/iliyami/CleanMyLife). The
first fork release starts at 0.1.0; upstream's history remains available in
git.

## [Unreleased]

### Added

- A public landing site under `site/`, deployed to GitHub Pages by
  `.github/workflows/pages.yml`.
- Issue forms, a pull-request template, Dependabot and a Code of Conduct.

## [0.1.0] - 2026-11-21

The first public beta of the Clean My Life fork.

### Added

- **New malware engine.** Apple's full XProtect rules and Elastic Security's
  macOS rules are evaluated with YARA-X (about 639 rules, versus 32 hashes
  before), in a separate helper process.
- **Deep scan containers.** Disk images, installer packages and zips are opened
  read-only in a temporary folder; mounted external drives are scanned too.
- **Full persistence sweep.** Launch agents and daemons, macOS background
  items, login items, cron, shell startup files, periodic scripts, login hooks,
  authorization plugins, kernel extensions, Quick Look plug-ins and browser
  policies, with code-trust checks (unsigned, ad-hoc, revoked, not notarized,
  quarantine, hidden folders, Apple-lookalike labels).
- **Browser extension audit** across every Chromium profile and Firefox, with
  install source, Chrome Web Store verdicts and risky permissions.
- **Apple protection status.** XProtect version and the results of Apple's
  background remediators, read from the system log without admin rights.
- **"Worth a look"** notices for cron lines, shell startup lines, periodic
  scripts, login hooks and forced browser policies. These are never deleted.
- **Real scan progress** with per-phase text and a fraction, including hash
  counts during the file pass.
- **AI Clutter.** Caches and logs from Claude, ChatGPT, Perplexity and LM
  Studio, plus local models from Ollama, LM Studio and Hugging Face.
- **Downloads.** Top-level `~/Downloads`, grouped by the app that downloaded
  it, with installers and duplicate downloads separated.
- **Similar Photos.** Bursts and near-identical shots; extras go to an album,
  never to the Trash.
- **Screenshots.** Recent screenshots are kept; older ones can be removed.
- **Browser Tabs.** Reads open tabs from Safari, Chrome, Brave and Edge through
  AppleScript, marks duplicate URLs, and closes only the tabs you select. The
  first read asks for Automation permission; the Chrome/Safari extensions are
  the next step.
- A rebuilt interface with the Soft Eraser brand, onboarding, a Tools tab, an
  Activity view and a new menu-bar popover.
- `scripts/live-malware-scan.sh` and the opt-in `MacCleanLiveTests` target.

### Changed

- Phase 11 polish: Reduce Motion stops the onboarding switch, status dot, hero
  sweep/radar, numeric rolls, stagger, sheet and fly-to-button; the hero loops
  pause when the window is inactive.
- The ten brand-kit module illustrations replace the SF Symbol hero
  placeholders, with the symbol as a safe fallback.
- White text now sits on a 16 % scrim, measured at 4.5:1 or better on every
  module gradient.
- VoiceOver announces scan progress at 25 % steps and labels the Browser Tabs
  rows, filters and actions.
- A debug-only preview gallery and the keyboard shortcut table in the README
  and site.
- `TEAM_IDENTIFIER` is stamped into `CMTeamIdentifier` at build time; the
  helper's XPC requirement follows it, so a fork can sign with its own team
  without editing source.
- The malware table now reads "Apple XProtect rule", "Elastic Security rule",
  "Starts with your Mac" and "Browser extension" alongside the older sources.
- Pattern rules also run on new files in the real-time monitor.
- The app is now called **Clean My Life** in every visible place, including the
  DMG, app bundle, cask, installer, README and site. Internal bundle identifiers
  and preference keys stay the same so existing data is not orphaned.
- Upstream update checks are disabled in this fork; the app never offers to
  replace itself with Clean My Life.

### Fixed

- The Deep scan now actually runs the pattern pass over `/Applications` and
  `~/Downloads`; the previous `-r` argument was being misread by YARA-X.
- The hash pass runs on every core and reports progress, so a large Downloads
  folder no longer looks frozen.
- Downloads reports the file it is sizing instead of sitting at 40 % while it
  walks a large folder.
- Malware results now open a **Scan details** popover with the rule sets,
  Apple's protection status, signatures and anything that needs review,
  instead of two lines of grey caption text under the progress ring.
- **Administrator approval is shared.** Maintenance and Wi-Fi route through one
  in-process runner, so macOS caches the Touch ID approval for about five
  minutes instead of prompting for every task. Settings > Helper has
  "Approve now" and "Ask when the app opens". A signed background helper is the
  only way to extend this to once per install.
- Codeless kernel extensions (such as SoftRAID's) are no longer reported as
  unsigned, and signature checks run in parallel.
- Chrome extensions retired for "minor policy" (Manifest V2) are no longer
  flagged as malware.
- The Quit action moved to the menu-bar popover; its source-text test now
  follows it.
- Phase 10 category rationales now have German and Traditional Chinese
  translations.

### Security

- XPC callers are pinned to the Developer ID team, not just a bundle
  identifier.
- Optional network paths stay opt-in and are documented in the README and
  `SECURITY.md`.

[0.1.0]: https://github.com/itchyparrot53/clean-my-life/releases/tag/v0.1.0
