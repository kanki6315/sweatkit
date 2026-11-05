# Wave 1 integration — source accuracy, feed/settings and detail/flyover

Integrated on 5 November 2026, preserving main's marketing-site commit `a06059d`.

- Source accuracy: `fee7117`, merged as `573c2fd`.
- Feed/settings: `817402e`, merged as `097dadd`.
- Detail/flyover: `16c1925`, merged as `e742c39`, preserving subsequent marketing-site changes through `c51df23`.
- All three first-wave branches are integrated without merge conflicts.

## Combined validation

- Health regressions: 23 tests passed (`/tmp/sweatkit-wave1-merge-health.log`).
- Full Store suite: 51 tests passed, including cache compatibility (`/tmp/sweatkit-wave1-merge-store.log`).
- XcodeGen plus unsigned physical-iPhone Release build passed (`/tmp/sweatkit-wave1-merge-build.log`). No simulator or phone was accessed for this integration check.
- Diff whitespace check passed. Logs above are local/ephemeral; task-specific notes retain the wider implementation evidence.
- After detail/flyover integration, 217 affected package tests passed: Detail 74, Timeline 116, Flyover 27 (`/tmp/sweatkit-wave1-detail-merge-tests.log`).
- XcodeGen plus the combined unsigned physical-iPhone Release build passed again (`/tmp/sweatkit-wave1-detail-merge-build.log`). No simulator or phone was accessed for this integration check.

## Acceptance still open

The feed/settings comparison captures show meaningful layout improvements, but header spacing and visual density still differ from the boards. This merge does not certify complete design parity, tap/swipe navigation, live permissions/sync behavior or reference-device performance. Retest the Health reference run and the existing library on the integrated signed build using the checklists in `WAVE1-SOURCE-ACCURACY.md` and `WAVE1-FEED-SETTINGS.md`.

Health segments are preserved in optional `RecordedActivity.segments`; their presentation remains an integration need for detail. Detail screens inherit the shared `AppTheme` tint; they should not introduce a separate accent preference. No TestFlight upload was performed as part of this merge.

The detail branch includes fixture-based light/dark, large-text and swipe-back evidence in `WAVE1-DETAIL-FLYOVER.md`. The integrated feed → detail → analysis → back flow still needs device acceptance. Camera feel, live Health corrections, elapsed/moving-time agreement and full design parity remain open; the merge is not acceptance of those items.
