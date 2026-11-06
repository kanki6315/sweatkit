# Metrics evidence follow-up — TestFlight 0.1.0 (310.22.2)

## Acceptance status and recording identity

Investigation started from `fd7bd0961166d0e953a7541637cae1fb1b268abd` on 6 November 2026. This is code investigation, not TestFlight acceptance. Charlotte elevation, splits and cadence remain unreconciled. No elevation threshold or split/cadence algorithm tuning is justified by the evidence currently available.

The user confirmed the reference recording: **5 November 2026, 09:32 EST (14:32 UTC), Apple Watch Ultra**, showing **20 m ascent in SweatKit**. Existing acceptance notes identify approximately 09:32–09:56, 2.53 km, 23:29, Fitness 5 m gain and 116 spm / 119 bpm averages. The user confirms different splits but has not supplied the rows. Exact seconds, workout UUID, recording app, sport classification, primary source, Fitness split units and current cadence discrepancy remain inputs to establish, not inferred facts.

Follow-up: the user states **no activity-average cadence is given**. This agrees with the current summary implementation. Treat cadence as a missing comparator, not an established numerical mismatch on build 310.22.2. Adding average cadence would require a defined aggregation/coverage policy and is not part of this endpoint correction.

## Follow-up: average cadence summary

The user subsequently requested an activity-average cadence to compare with Fitness. Added `CadenceSummary` in Analysis and wired it through the prepared Detail presentation into the existing summary grid for cycling and on-foot activities. This is a new stream-derived display metric, not a claim to reproduce Apple's denominator or source processing.

Policy: mean of available measured/interpolated 1 Hz timer samples, including recorded zeroes, excluding paused seconds, missing samples and invalid values. On-foot units remain steps/min (no extra doubling); cycling uses rpm. Incomplete coverage is shown as the fraction of timer seconds with cadence. Unknown pause positions, no valid readings or no timer seconds give an unavailable reason. Long Health step aggregates remain unavailable under the existing importer; this display does not fabricate cadence for them.

The value is prepared once with the activity's detail and does not vary with the cursor. It is computed from the current stream rather than added to serialized `ActivityMetrics`, so no stored schema or algorithm-version migration is needed for this addition. No Model change. Existing endpoint stream version 3 remains required for the prior commit.

Verification for this follow-up: `Scripts/test-packages.sh SweatKitAnalysis SweatKitDetail` passed 293 Analysis tests and 77 Detail tests (`/tmp/sweatkit-cadence-tests.log`). New tests verify timer-only aggregation, zeroes, interpolation, missing/invalid/short channels, unknown pauses, empty timer, coverage and Detail preparation. A disposable simulator harness uses the checked-in real `walk.fit` through the production decoder, normalizer, detail preparation and `ActivityAnalysisView`; the fixture renders 90 spm. This is fixture/UI evidence, not Charlotte acceptance. Display uses compact `spm` with an expanded steps-per-minute VoiceOver label to avoid a wrapped unit in the existing grid.

The final iOS simulator build succeeded. Visually checked the summary on a Simlock-leased iPhone 17 in light/default text and dark/extra-extra-extra-large text: the cadence value/unit and label fit, and the grid adapts from three columns to two. Captures: `/tmp/sweatkit-cadence-summary.png` and `/tmp/sweatkit-cadence-summary-large-dark.png`; build log: `/tmp/sweatkit-cadence-build.log`. Simulator lease released after verification. No TestFlight build was uploaded. Charlotte data, partial-coverage UI with live Health data, and VoiceOver speech on a real device remain acceptance checks.

## Minimum evidence to reproduce

1. Fitness and SweatKit summaries plus every split row, including units and labels (duration versus pace). Include SweatKit source/primary-source details and build number. A transcription is sufficient for the first split comparison.
2. For elevation: timestamped native route altitude in metres for this workout, preferably with horizontal/vertical accuracy, workout start/end, source identity, and any source-reported elevation metadata. Retain the source's actual precision. No need to share unrelated activities.
3. For splits: the same workout's raw walking/running distance interval start/end/value/unit, timer/pause/motion-pause/resume events, and lap/segment intervals. A route-only GPX cannot establish Health distance or timer semantics.
4. For cadence: raw step-count intervals with their source, start/end/value, plus the exact SweatKit screen/time being compared. Preserve long intervals and overlaps; do not pre-average them. Workout average cadence is not equivalent to cursor cadence.
5. For an exact importer replay: the matching stored `HealthSnapshot` and source revision/primary selection. A snapshot contains the adapter's converted samples, so it cannot alone explain rejected intervals or discarded route accuracy. Pair with raw export/query evidence when investigating those stages.

### Export using available tools

Apple documents **Health → profile picture/initials → Export All Health Data**, then choosing how to save/share the XML export: [Apple Health export instructions](https://support.apple.com/en-ca/guide/iphone/iph5ede58c3d/ios), checked 6 November 2026. Save it locally first. The system export is broad; the investigation only needs the selected workout element, associated route file if present, and relevant source-matched distance/step records overlapping its exact interval. Keep nested workout metadata, events, statistics, timestamps and units intact. Do not submit the entire Health history merely to identify one workout.

The repository currently has no user-facing Health snapshot export or Health XML import. Do not describe Files import (FIT) or iCloud recovery as a Health diagnostic export. If the user supplies a local export path, inspect its schema and select the confirmed workout before extracting a minimal bundle. Do not assume that XML exports retain condensed quantity-series entries, workout associations, accuracy, or UUIDs needed to reproduce HealthKit queries exactly. Record absent fields explicitly; request a targeted on-device diagnostic only if the export proves insufficient. No new export UI is included in this change.

## Audited calculation path

| Stage | Observed behavior | Implication for comparison |
| --- | --- | --- |
| Health queries (`App/HealthConnection.swift`) | Quantities are constrained to the workout association AND the workout's source. `HKQuantitySeriesSampleQuery` reads individual entries. | A time-window XML subset is a candidate set, not proof those records passed the live workout-association predicate. Other sources can exist in Health without being imported. |
| Route altitude | Route points need nonnegative horizontal accuracy; altitude also needs nonnegative vertical accuracy. Altitude is stored in metres. Accuracy magnitude and altitude sensor provenance are not retained in `NativeSample`. | No accuracy-weighted smoothing or barometer/GPS selection occurs here. Apple Fitness's altitude processing cannot be inferred from its displayed total. |
| Health summary | Saves start/end, `workout.duration`, total distance and timezone offset. No stated ascent or average cadence is copied. | SweatKit ascent is recomputed, not a display of Fitness's reported gain. |
| Health distance (`HealthQuantityConversion`) | Accumulates nonnegative interval totals at interval boundaries; shared boundaries emitted once. Any invalid or overlapping interval causes the entire channel to be omitted. | Need raw interval boundaries, overlaps and omitted-channel evidence. Workout distance is not spread across the route. |
| Grid (`StreamNormaliser`) | 1 Hz from workout start, elapsed rounded up; subsecond observations averaged per channel. Linear altitude/distance filling across at most five missing seconds, never across known pause boundaries. | Grid values and native values are different evidence layers. Preserve both; integer grid time can differ from reported fractional time. |
| Elevation (`ElevationAnalysis`) | Peak/valley hysteresis, 3 m on foot, 1.5 m cycling, zero virtual. Counts extension of an established climb; exact-threshold reversals count. Missing altitude is skipped without resetting extrema; paused altitude still contributes. | This is a reversal threshold, not a smoothing window. A 3 m threshold does not cap total noise gain at 3 m. Missing gaps/paused movement must be inspected, not presumed to cause the 15 m discrepancy. |
| Time (`TimeAnalysis`) | Timer excludes known paused grid seconds. Outdoor on-foot moving time additionally excludes speed below 0.5 m/s; missing speed counts as moving. Unknown pause positions make moving time and splits unavailable. No events plus stated timer within 1% of elapsed is treated as unpaused. | Fitness's displayed time must be identified before comparing it to moving/timer/elapsed. |
| Splits (`SplitAnalysis`) | Fixed kilometre boundaries; distance at second t assigns that whole timer second. Exact boundary enters the next split. Missing distance carries prior split membership. Final partial split uses its actual distance. HR averages present timer seconds; ascent goes to the second the climb is counted. | No fractional crossing interpolation. Mile pace display does not turn boundaries into mile splits. UI filters zero-distance terminal splits. |
| Health cadence | Short step intervals (duration >0 and ≤5 s) become steps ×60/duration. Longer aggregates omitted. Invalid/overlapping intervals reject the channel. The normalizer can hold cadence across short bounded gaps. | Presence/absence and gridded aggregation can differ from a workout average. No confirmed factor-of-two defect in this path. |
| FIT cadence | Integer plus fractional cadence, doubled on foot from strides/min to steps/min; cycling remains rpm. Enhanced altitude preferred to ordinary FIT altitude. | Compare original source files before assuming Health and FIT representations are identical. Enhanced altitude alone does not establish sensor provenance. |
| Detail (`PreparedDetail`, `AnalysisPresentation`, `ActivityAnalysisView`) | Cursor cadence reads the selected grid second. Summary exposes elapsed, timer, moving, distance and ascent; no workout-average cadence field. Chart decimation preserves endpoints/extrema. | A chart/cursor cadence reading is not the Fitness workout average. Elevation profile is not elevation gain. |
| Persistence (`Pipeline`, `HealthSnapshot`) | Original Health snapshot is versioned; derived provenance records input revision, profile fingerprint and combined algorithm version. Feed can fall back to Health's stated distance when computed distance is absent. | Capture primary source and revisions; a fallback feed total does not establish distance samples or split availability. |

## Reproduction plan after data arrives

Match recording identity before arithmetic. Report source-stated totals separately from recomputed values. Preserve original input outside committed fixtures unless explicitly approved.

For elevation, record raw sample count, accepted/rejected count, interval/gap distribution, raw positive-delta sum (diagnostic only), native peak/valley result and normalized 1 Hz result under the unchanged 3 m rule. List counted climb seconds and gains, including pauses and gap crossings. Compare their sum to SweatKit's exact stored result and the rounded Fitness 5 m reference. Do not substitute a new threshold to match the reference.

For splits, tabulate each 1000 m crossing and neighboring distance samples, elapsed/timer/moving counts, paused spans, per-split duration and pace. Compare units first. Reconcile sums including any zero-distance terminal bucket and final partial distance. Keep recorded laps/segments separate from computed kilometre splits.

For cadence, inspect interval duration, source/overlap rejection, unit conversion, per-second measured/interpolated/missing coverage and cursor positions. A duration-weighted source-interval average and a grid average can be reported as explicitly labeled diagnostics; neither is automatically Apple's workout-average denominator.

Unconfirmed hypotheses: altitude filtering/provenance differences; counting noise during pauses or across gaps; split unit/time-definition differences; distance sampling and whole-second boundary allocation; stale source revisions; comparing cursor cadence to workout average. None is a diagnosed cause of this recording's discrepancy.

## Focused verification and handoff

The four checked-in real recordings are Garmin/Zwift FIT fixtures (`Fixtures/README.md`), not this Apple Watch workout. Existing tests cover threshold reversals, missing/paused altitude, timer split allocation, pause semantics, short/long Health intervals, overlap rejection and FIT cadence conversion. Synthetic regression inputs are labeled test observations, not substitutes for Charlotte evidence.

No simulator/device access, release, upload or merge is part of this investigation. Golf and Playback should review the shared normalizer/version change described below when integrating; no Health adapter, Model, Detail or UI file is changed by this branch.

### Validated defect: samples admitted past a fractional workout end

The contract excludes samples at or after the actual activity end. Previously `Grid.second` checked only the rounded grid length. With end = 2.5 s, heart-rate observations 120 at 2.25 s, 180 at 2.5 s and 240 at 2.75 s produced **180** in second 2. Only the first observation is within the workout, so the expected value is **120**. The new `fractionalEndExcludesSamplesAtAndAfterTheActualEnd` test failed before the fix with that exact mismatch.

`Grid` now retains the actual end and requires sample timestamps in `[start, end)`. The elapsed grid still has three seconds for that example. Pause-event allocation, rounding, elevation thresholds and cadence/split calculations are unchanged. `StreamRules.version` increases from 2 to 3; `PipelineVersions.current` consumes it so existing streams and dependent results become stale and are rebuilt. This affects any imported source with an endpoint observation in the rounded final second, not only Health. It does not establish the cause or magnitude of the Charlotte differences.

Changed files: `StreamNormaliser.swift`, `StreamRules.swift`, `StreamGridTests.swift`, `StreamRulesTests.swift` within SweatKitIngest; Library's `FeedRulesTests.swift` version expectation; plus this evidence note. No shared Model contract additions. Integration should preserve stream version 3 (or a later combined version if another branch also changes stream rules) and ensure recomputation completes before comparing metrics on device.

### Check evidence

- Analysis: 290 tests in 31 suites passed (`Scripts/test-packages.sh SweatKitAnalysis SweatKitIngest SweatKitLibrary`, Analysis portion; `/tmp/sweatkit-metrics-package-checks.log`).
- Before fix: the focused fractional-end regression failed as expected (`/tmp/sweatkit-metrics-endpoint-before.log`). The initial multi-package command also saw this intentionally failing Ingest test; it is not a passing aggregate run.
- After fix: `swift test --package-path Packages/SweatKitIngest` passed all 170 tests in 14 suites, including all four real FIT fixtures and the new endpoint regression (`/tmp/sweatkit-metrics-ingest-after.log`).
- The initial full Library run was interrupted to free the build lock for focused post-fix verification. Do not count it as passed. Compiler cache access required an escalated run after the initial sandbox attempt failed before compilation.
- Post-fix Library: `swift test --package-path Packages/SweatKitLibrary --filter 'Health|Version|Recomput'` ran 56 tests in 12 suites. 55 passed, including `aChangedStreamRulesVersionRebuildsFromTheDecodedActivity`; one failed because `PipelineVersionsTests` still pinned stream version 2. Updated that expectation to 3; this is a test contract adjustment, not another production change (`/tmp/sweatkit-metrics-library-after.log`).
- After updating the expectation, `swift test --package-path Packages/SweatKitLibrary --filter PipelineVersionsTests` passed all 6 tests (`/tmp/sweatkit-metrics-versions-after.log`). No production changes followed the 55 passing Library tests.
- `git diff --check` passed. Logs are local transient evidence, not committed private recordings.

Remaining real-device acceptance: identify the exact Health workout and source revision, capture Fitness/SweatKit split rows and native samples, let stream-version recomputation finish in an integrated build, then compare the same recording again. Explicitly retest route/stat start positions after activity changes and the existing passed source/navigation behavior during integration, because a stream rebuild can alter final samples. No claim is made that these device checks have passed.
