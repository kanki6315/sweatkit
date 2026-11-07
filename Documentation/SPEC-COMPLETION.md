# Spec completion — 5 November 2026

This branch closes the remaining original-spec presentation gaps before the combined design build. Physical-device acceptance stays deferred until the next TestFlight.

- Cycling feed headlines now use weighted power. Rides with recorded power but ineligible weighted power show an unavailable headline rather than silently substituting average power. Feed row algorithm version 2 rebuilds old rows from preserved analysis streams; the old headline identifier remains readable during migration.
- Activity analysis displays kilometre splits with timer duration, pace, average heart rate and ascent, including partial final kilometres. Boundaries remain kilometres as specified; pace and elevation respect unit preferences. Missing sensor channels are described, and unknown pause timing leaves splits unavailable.
- Known-route detail now includes chronological occurrence, speed rank and time behind best, with an explicit Compare action. Chronology uses start date and stable identity for ties; moving rankings/gaps exclude unreliable pause timing. Comparison continues to select the fastest other effort by default.
- Analysis summary explicitly labels elapsed, timer and moving time, including reported-only timer time. Split pace uses timer time. A stopped second without a recorded pause remains in timer-based splits while being excluded from moving time. No source-specific adjustment was invented to match Apple Fitness.

No shared Model schema changed. The LibraryRoute API additions are derived read-only helpers.

## Verification

- Generic physical-iOS Release compilation passed with signing disabled; final incremental build includes the Compare label and descriptive missing split channels (`/tmp/sweatkit-spec-build-final.log`).
- Library suite: 149 tests passed (`/tmp/sweatkit-spec-library-tests.log`). Final migration and chronological/ranked route regressions were added after that suite began and both passed separately; see `/tmp/sweatkit-spec-focused-tests.log`.
- Analysis suite: 290 tests passed, including stopped-but-unpaused timer/split semantics (`/tmp/sweatkit-spec-analysis-tests.log`).
- Existing split fixtures cover complete and partial kilometres, boundary seconds, pauses, HR averages, ascent allocation and missing channels.
- Combined visual verification belongs to the design-parity integration so both workstreams are viewed together. The user's live Apple reference discrepancy remains open for post-release acceptance; these changes do not claim it is resolved.
