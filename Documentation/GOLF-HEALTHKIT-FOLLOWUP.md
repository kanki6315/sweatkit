# Golf HealthKit follow-up

Branch: `codex/golf-enhancement-discovery`. No release or upload performed.

## Release baseline recovered

TestFlight 0.1.0 (310.22.2) was built in `/Users/arjunakankipati/.codex/worktrees/3bb8/sweatkit`, whose HEAD is `3b7b61e` with uncommitted acceptance changes. The archive's app Info.plist confirms version `0.1.0`, build `310.22.2`, bundle `com.arjunakankipati.sweatkit`. `build/release/0.1.0-310.22.2/export-retry.log` records successful upload; the initial export log records a failed attempt.

There is no clean release commit to cherry-pick. Recovery commit `dbf8701` copies only the Golf label/store migration and adjacent-session duplicate fixes, with their existing tests, onto this branch. The live release worktree remains untouched. Its current files establish the recoverable implementation, not a byte-for-byte archived source manifest. Earlier investigation missed this because Golf is a `sourceSportName`, deliberately still `.other` for sport-family matching.

## Resulting behavior

The Golf detail extends the native recorded-summary list. It reads the selected primary Health original directly, bypassing normalized analysis metrics:

- Apple Health attribution and originating app, recorded start/end, elapsed and workout time, stated distance when present. Missing distance remains unavailable; GPS never supplies a replacement total.
- A separate, navigable map of original coordinates. Dots do not connect gaps, infer shots, or identify holes. No map is created on the scrolling summary.
- Point charts for retained heart rate, altitude, speed, distance, power, cadence or temperature channels when present. Original timestamps and values are preserved; non-finite/invalid values are omitted, genuine zeros retained, and no readings interpolated. Axes include the workout's unrecorded leading/trailing time.
- Source lap/segment intervals when present, explicitly not labeled as golf holes.
- Honest empty states for no route or measurement samples. Another source's data is never borrowed to fill gaps.

No new Health query, authorization type, permission prompt, adapter refresh, account or Arccos integration. This exposes data already retained by the importer; it does not claim access to every Health field. The existing adapter still scopes quantities to workout association and source, skips on-foot distance/step quantities for `.other`, and does not preserve arbitrary custom metadata or active-energy samples. Scores, course names, clubs and shots are not invented. Existing Golf snapshots work without refreshing Health; snapshots predating the accepted source-label fix remain subject to its original refresh requirement.

## Files and integration

- Baseline: `App/HealthConnection.swift`, Golf metadata hunk in `App/ActivityFeedView.swift`; Library snapshot/pipeline/feed/identity reconciliation; Store's additive V2 migration; Identity boundary-overlap policy; associated recovered tests. No shared Model contract changed.
- Enhancement: `App/ActivityDetailView.swift` adds the early Golf-only loading path and sections; `App/GolfHealthSections.swift` supplies the conditional native UI.
- `Packages/SweatKitLibrary/Sources/SweatKitLibrary/GolfHealthRecording.swift` prepares display values from a single stored Health snapshot. It adds a Library API, no new persistence schema.
- `GolfHealthRecordingTests.swift` covers empty data, sparse timestamps, invalid samples versus recorded zero, source isolation and latest revisions after reopen.
- `Scripts/GolfValidation/` builds a disposable harness around production ActivityDetailView with clearly labeled synthetic Health snapshots. No fixture behavior ships in App.

When integrating with the acceptance worktree, do not reapply baseline commit `dbf8701` if those fixes are already present. Apply the subsequent enhancement commit to the corresponding label/migration baseline. ActivityDetailView is shared with Playback: preserve that owner's identity reset and playback/camera changes around the small Golf branch. This branch intentionally does not bring over unrelated release-worktree Search, Routes, Trends, sync-banner, or MapKit scrolling changes.

## Verification

- HealthSnapshot + initial Golf preparation tests: 15 passed (`/tmp/sweatkit-golf-health-tests.log`).
- Final Golf preparation/original-selection tests: 4 passed (`/tmp/sweatkit-golf-recording-final.log`).
- Identity: 270 passed (`/tmp/sweatkit-golf-identity-tests.log`).
- Store: 53/54 passed in the full run; the stream-read performance test exceeded its time budget during concurrent builds. Both migration tests and that performance test passed in the isolated rerun (3/3, `/tmp/sweatkit-golf-store-final.log`). No threshold was changed.
- Simulator harness: populated/sparse, empty, light, dark and maximum accessibility text; map navigation/back. The initial test used an incorrect exact accessibility lookup for LabeledContent; the corrected run passed. Screenshots reviewed: native labels wrap at large text, sparse clusters remain separate, missing data remains explicit. No VoiceOver listening or live Health permission test was performed.
- Final unsigned generic-iPhone Debug build passed (`/tmp/sweatkit-golf-build-final.log`). Final simulator run passed all four modes in one XCTest (`/tmp/sweatkit-golf-ui-verified.log` and `.xcresult`), including the final direct-original load path. Evidence is committed in `Evidence/GOLF-HEALTHKIT-2026-11-06/`. The Simlock lease was released.
- Impeccable mechanical check returned no findings. Existing PRODUCT.md uses legacy skill metadata; it was not rewritten. `git diff --check` is clean.

## Real-device acceptance still required

Open an existing Golf round on the integrated build, compare source/time/distance with Health, and verify any actual route/HR samples. Check sparse or absent channels, back navigation, switching the primary recording, refresh/relaunch, Golf labels and absence of false adjacent-session duplicate prompts. Large real routes and MapKit tile/network behavior need phone checks; the synthetic harness does not certify those. No real golf dataset was supplied or inspected. No unresolved product choice blocks this narrow implementation; remaining evidence is a representative real round and device retest. iCloud remains deferred.

## Merge follow-up

The user authorized merging this branch into main. Current main `216c818` (Search, Playback and Metrics follow-ups) was integrated without conflicts in `fc1d4c8`. Inspection confirmed the activity-reset/cancellation path remains ahead of the Golf-only loader. The integrated unsigned iPhone build passed (`/tmp/sweatkit-golf-merge-build.log`), and all five focused Golf/adjacent-session tests passed (`/tmp/sweatkit-golf-merge-tests.log`). The simulator results above precede this integration; no new TestFlight acceptance is claimed.
