## What changed

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- The user problem or engineering reason. -->

## How to test

<!-- Exact steps or commands. -->

- [ ] `swift build`
- [ ] `swift test`
- [ ] `bash scripts/check-version-sync.sh`
- [ ] `scripts/live-malware-scan.sh quick` (if rules, detection or scanning changed)
- [ ] Tested the change in the running app (not only compilation)

## Screenshots

<!-- Required for UI changes. Use synthetic data only. Before/after is ideal. -->

## Safety

- [ ] No file operation bypasses `SafetyGuard` / `CleaningEngine`
- [ ] New deletion paths have review-first defaults and tests
- [ ] No telemetry, analytics or undisclosed network calls
- [ ] No secrets, private paths or real user data in the diff or screenshots
