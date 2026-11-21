# Localization backlog

English, Simplified Chinese and Russian are the source languages for the app
(`L10n.tr` takes three inline strings). German, French, Italian, Spanish,
Brazilian Portuguese, Japanese, Korean, Turkish, Persian and Traditional
Chinese live in the fallback dictionaries in `Sources/MacCleanKit/Localization.swift`.

The Phase 10 and Phase 11 screens added English copy faster than translations.
These are the visible strings that still fall back to English in the other
languages. They are safe to ship in English for 0.1.0; translate them before
claiming full language coverage.

## Browser Tabs (`Views/NewModules/BrowserTabsView.swift`)

- Title, subtitle, read/refresh button and hint.
- Filters: All, Duplicates, Safari, Chrome/Brave/Edge.
- Empty states, duplicate badge, window label, Close, Close Tabs, selected count.
- Status and error banners.

## Downloads (`Views/NewModules/DownloadsView.swift`, `Modules/Downloads`)

- Intro title/subtitle, Installers, Downloaded twice.
- Scan phase and empty state.

## Similar Photos (`Views/NewModules/SimilarPhotosView.swift`)

- Include my Photos library, Auto-select, Compare, Keep This Instead,
  Select All but Best, Deselect, group titles, captions.

## Screenshots (`Views/NewModules/ScreenshotsView.swift`)

- Move to Pictures, Older Than a Week/Month/Year, Everything Here,
  Deselect Everything, Quick Look, group titles.

## Malware (`Views/Protection/MalwareView.swift`, `Modules/Malware`)

- "Worth a look", the coverage summary, scan depth descriptions.
- Startup and browser-extension reasons, Apple Remediator notices.
- The YARA and Elastic credits row in Settings.

## Adding a translation

1. Wrap the string in `L10n.tr("简体中文", "English", "Русский")`.
2. Add the Simplified Chinese key to each fallback dictionary that should be
   translated.
3. Run `swift test --filter Localization` and `swift test --filter MalwareLocalization`.
4. Add the new keys to the guard tests when the string is user-facing and
   permanent.

The dynamic malware reasons are built from data, so translate the reason
phrases at their source (`PersistenceSweep`, `BrowserExtensionAudit`,
`CodeTrust`) rather than at the view.
