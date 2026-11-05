# Wave 1 integration — source accuracy and feed/settings

Integrated on 5 November 2026, preserving main's marketing-site commit `a06059d`.

- Source accuracy: `fee7117`, merged as `573c2fd`.
- Feed/settings: `817402e`, merged as `097dadd`.
- No merge conflicts. The detail/flyover branch is separate and was not included.

## Combined validation

- Health regressions: 23 tests passed (`/tmp/sweatkit-wave1-merge-health.log`).
- Full Store suite: 51 tests passed, including cache compatibility (`/tmp/sweatkit-wave1-merge-store.log`).
- XcodeGen plus unsigned physical-iPhone Release build passed (`/tmp/sweatkit-wave1-merge-build.log`). No simulator or phone was accessed for this integration check.
- Diff whitespace check passed. Logs above are local/ephemeral; task-specific notes retain the wider implementation evidence.

## Acceptance still open

The feed/settings comparison captures show meaningful layout improvements, but header spacing and visual density still differ from the boards. This merge does not certify complete design parity, tap/swipe navigation, live permissions/sync behavior or reference-device performance. Retest the Health reference run and the existing library on the integrated signed build using the checklists in `WAVE1-SOURCE-ACCURACY.md` and `WAVE1-FEED-SETTINGS.md`.

Health segments are preserved in optional `RecordedActivity.segments`; their presentation remains an integration need for detail. Detail screens inherit the shared `AppTheme` tint; they should not introduce a separate accent preference. No TestFlight upload was performed as part of this merge.
