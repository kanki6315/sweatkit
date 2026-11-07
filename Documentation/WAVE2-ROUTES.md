# Wave 2 — Routes

Implementation branch: `codex/wave2-routes`. Started from `0b1f05a`; `git merge-base --is-ancestor 0b1f05a HEAD` passed before edits. No merge, push or release is part of this task.

## Delivered boundaries

- Routes replaces only the Routes placeholder in `RootView`. Settings, AppTheme and the other tab contents stay with their existing owners. Two additive lines in `LibraryModel` hold/call the background refresh task; its implementation is in `LibraryModel+Routes.swift`.
- `ActivityLibrary.routes()` queries the complete visible library, reads current primary streams, cleans tracks, constructs moving clocks under Analysis thresholds, calls the existing detection/alignment implementation, and returns repeated groups and review cases. It runs after library reload and on opening Routes. There is no production fixture mode.
- Route names, chosen references, manual membership and merges are durable user intent. The route page offers rename, reference selection, removal and merge. Merge verifies every source effort covers the destination course in the same direction/sport family; explicit merging writes inclusion decisions for those efforts. Unresolved parallel/ambiguous matches are reviewed rather than automatically merged. Removed activities do not immediately rejoin the same group.
- Groups retain their original seed identity when the reference is hidden or deleted. A remaining visible effort becomes the reference; changing the reference rebuilds all alignments. Source-revision and row changes during computation cause a fresh query. Identity aliases preserve decisions across merged activities.
- Rankings, best/latest/median times and comparisons use the 25 m inset timed section. Unknown pause positions remove an effort from moving rankings and force elapsed time for both comparison efforts. Tied times share a rank. Charts keep missing samples as gaps.
- Comparison offers best, previous or a chosen baseline, moving/elapsed clocks, paired power/heart-rate charts on the 10 m distance grid, the time gap, and two markers driven by one elapsed/moving clock. Playback is 30×; scrub pauses playback. Overview works with Reduce Motion; optional follow uses a pitched camera. Summary labels distinguish timed-section measurements from whole-activity power/heart-rate/efficiency.
- `RouteCatalog.membership(of:)`, `LibraryRoute.rank(of:)`, `best`, `median`, `ranked`, and `RouteEffort` expose membership/ranking data for later feed/detail badges. This branch does not edit those screens.

## Persistence and Cloud contract

Model changes are additive: `RouteDecision` and `RouteDecisionExport` in `SweatKitModel/RouteDecision.swift`. No shared database schema rewrite.

`RouteDecision` has a UUID, stable route seed `SourceIdentity`, a timestamp and one value: name, reference effort, included/excluded activity, or source route to merge. Optional `anchors` capture identity-only scope when the user edits a route. Anchors reconstruct the edited group when the local group cache or original reference is unavailable; they **never** bypass eligibility/alignment. They contain no coordinates, streams, dates of workouts, metrics, or inferred confidence.

Cloud should use the opaque kind **`sweatkit.route-decisions.v1`**:

```swift
let payload: Data = try await library.exportRouteDecisionPayload()
// Store/transport as opaque bytes in Cloud's extensible user-decision contract.
try await library.applyRouteDecisionPayload(payload)
// After recovered originals/source records are ready:
let refreshed = try await library.routes()
```

The payload is sorted-key JSON encoding `RouteDecisionExport(version: 1, decisions: ...)`. Applying is an additive UUID union, ordered by timestamp then UUID for deterministic last-writer resolution. Reapplying is idempotent. Unknown versions and conflicting reuse of a UUID throw without replacing local intent. Cloud must retain opaque payloads it does not understand; it must not decode route geometry or synthesize route decisions. Typed equivalents are `routeDecisions()` and `applyRouteDecisions(_:)`.

- `route-decisions-v1.json` contains only user intent and its identity scope; it may be recovered/synced.
- `LocalMetadata/route-groups-v1.json` holds recomputable identity hints for local grouping. Its parent is excluded from OS backup. Do not upload it.
- Geometry, alignments, comparison grids and route metrics remain in memory and are rebuilt from local streams. Health-derived geometry is never copied to the decision payload. Health snapshots and streams keep their existing locality rules.
- Grouping is currently rebuilt rather than incrementally cached. Large real libraries need performance measurement. Background warming is cancellation-aware and failures remain retryable from Routes.

The Library orchestration now needs `SweatKitRouteMatching` and `SweatKitTrackCleanup`. The minimal dependency entries are included in `Packages/SweatKitLibrary/Package.swift` so this branch builds independently. Cloud owns final combined package/project wiring: retain these entries when integrating. No app entitlement or project.yml change is needed here; the app already depended on both leaves. No new architectural layer was introduced.

## Validation evidence

- Existing Library suite: **119 tests passed**, including 500-workout scale and identity/storage regressions. `/tmp/sweatkit-routes-library-test.log`.
- Route Matching suite: **284 tests passed** across detection, alignment, timed sections, comparisons and geometry cases. `/tmp/sweatkit-routes-matching-test.log`.
- New route integration suite: **10 tests passed** (`/tmp/sweatkit-routes-focused-test.log`). Covers parallel-road review and manual removal, reverse-direction rejection, unknown-pause rank exclusion/elapsed fallback, ties, changed/hidden reference, merge exclusions, identity merges, opaque export idempotency/conflicts, decision anchors after local-cache loss, and analytical nonzero ghost separation (20 versus 25 m/s gives 150 m separation after 30 s).
- Real `outdoor-ride.fit` is imported through the production pipeline; a date-shifted Health test snapshot of that recording is grouped, reopened, renamed, revised to lose GPS, restored, recomputed, hidden/restored and deleted. This validates real fixture geometry and persistence, **not** a genuine second outdoor ride or live Health queries.
- Production simulator Debug build passed. Unsigned physical-iPhone Release build passed; it is a compile/link check, not a device test. Isolated outputs: `/tmp/sweatkit-routes-app-build`, `/tmp/sweatkit-routes-release-build`.
- Final simulator UI run: **7 tests passed, 0 failures** in `/tmp/sweatkit-routes-ui-final-verdict.xcresult`: six fixture tests (light, dark, accessibility-M text, empty, error and explicit parallel-course review) plus the production-root smoke test. This run includes the final two review fixes; committed captures come from this result bundle. Tests navigate list → route → comparison → back, change the shared-clock slider and assert its value changes, and start/pause playback. The review test keeps a synthetic parallel course separate and verifies the route-empty result. The error case deliberately corrupts the harness's own decision file and checks the retry control.
- Simulator: Simlock-leased iPhone 18 Pro Max, iOS 27.2. Captures are actual production views in a separate harness. They are not board renders. The harness imports the real FIT plus an explicitly test-only derivative with timestamps scaled to 90% to produce visible time gaps/ghost separation. No derivative ships in the production app. A separate synthetic 2 km straight-course pair, 14 m apart, exercises the review card; it is also confined to the harness.
- The first UI run passed; a subsequent styling pass exposed an effort-row hit-area regression. Adding an explicit rectangular hit area fixed it. An overly transparent slider in the first miniature-chart attempt also failed the value-change assertion; retaining the fully native visible slider and disabling chart hit testing fixed it. Earlier failed `ui-final` and `ui-review` result bundles are not acceptance evidence.

Reproduce the harness with `python3 Scripts/RouteValidation/prepare.py /tmp/routes-harness`, then `xcodegen generate --spec /tmp/routes-harness/project.yml`. Read Simlock instructions and lease a device before the simulator build/test. Use a separate derived-data path and the lease's device-set arguments as specified by Simlock. For the optional production-root test, first install the production simulator app with Simlock, then append `ProductionRootTests.swift` to the temporary harness’s `UITests.swift` before testing. `Harness.swift` and `UITests.swift` are test-only; the prepare script copies the current app into a temporary directory and adds a fixture-library setter only to that copy.

## Captures and remaining acceptance

Committed captures in `Documentation/Captures/WAVE2-ROUTES/` are reduced to 660 px wide; native-resolution originals and their manifest are at `/tmp/sweatkit-routes-final-captures/`. Logs and result bundles under `/tmp` are local/ephemeral.

| Surface/state | Evidence |
| --- | --- |
| Routes list | [Light](Captures/WAVE2-ROUTES/routes-light.png), [dark](Captures/WAVE2-ROUTES/routes-dark.png), [large text](Captures/WAVE2-ROUTES/routes-large.png) |
| Route page | [Light](Captures/WAVE2-ROUTES/route-light.png), [dark](Captures/WAVE2-ROUTES/route-dark.png), [large text](Captures/WAVE2-ROUTES/route-large.png) |
| Comparison | [Light](Captures/WAVE2-ROUTES/comparison-light.png), [dark](Captures/WAVE2-ROUTES/comparison-dark.png), [large text](Captures/WAVE2-ROUTES/comparison-large.png) |
| Scrubbed, nonzero gap | [Light](Captures/WAVE2-ROUTES/scrub-light.png), [dark](Captures/WAVE2-ROUTES/scrub-dark.png) |
| Paired charts and summary | [Light](Captures/WAVE2-ROUTES/charts-light.png), [dark](Captures/WAVE2-ROUTES/charts-dark.png) |
| Review action | [Review](Captures/WAVE2-ROUTES/routes-review.png), [kept separate](Captures/WAVE2-ROUTES/routes-review-separated.png) |
| Production tab | [Routes with shared tabs and Settings control](Captures/WAVE2-ROUTES/production-routes-empty.png) |
| Empty/error | [Empty](Captures/WAVE2-ROUTES/routes-empty.png), [error](Captures/WAVE2-ROUTES/routes-error.png) |

The fixed boards were not altered. The independent Impeccable review requested eight material fixes. The final implementation adds terrain behind native controls, rounded overlapping panels, Detail/Palette effort colors and a legend, both comparison charts in the default first viewport, current route distance, a real-data miniature timeline, aligned formatted summaries, geographic thumbnails with a local outline fallback, visible ordinary-size metric selectors, faster-is-higher history, best/latest/median annotations, and accessible statistics. A follow-up identified median-label collision and unstable comparison columns; both were corrected and recaptured. Final independent reviewer disposition: **ship for the scored fixes**. All eight requested fixes are resolved; the final check confirmed that the median label stays inside the plot across light/dark/large text and comparison statistics retain stable columns between initial and scrubbed states, with accessibility stacking preserved. No material regressions were identified in that fix batch. This is a scoped review disposition, not full-surface or live-device acceptance.

The fixture harness omits RootView, but the optional `ProductionRootTests.swift` separately launches the installed production bundle, opens the real Routes tab, captures its empty state and opens Settings. That smoke test passed; it does not certify an integrated populated feed → route → comparison journey.

Live gates remain: genuine repeated-history grouping with manual false-merge review; offline navigation with networking actually disabled (local matching/persistence uses no network, but MapKit imagery does); the populated combined navigation flow; live Health revisions/deletions; signed physical-device playback/camera smoothness, large-library latency, full VoiceOver and Increase Contrast/Reduce Transparency; and Cloud transport/recovery integration. Follow-camera heading currently uses the reference's 200 m look-ahead directly, so physical smoothness needs particular attention. Package tests and fixture screenshots do not close these gates.

Pre-existing Impeccable context drift: PRODUCT.md uses an older schema and deprecated Register field. Neither was changed by this task; an explicit `init` pass owns that migration.
