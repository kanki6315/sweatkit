# Wave 2 integration

5 November 2026. Integration branch: `codex/integrate-wave2`. Preserves main through `280357d`, including marketing-site changes.

- Trends `ecbd0a3`, merge `ed9463f`.
- Routes `2dc7911`, merge `32e4233`.
- Cloud `064d859`, merge `5cf2aef`.
- The LibraryModel merge conflict retained both route refresh and cloud scheduling. RootView retains all feature tabs and lifecycle sync; Library retains both sets of package dependencies.

## Completed integration

Route actions export as one stable, immutable CloudDecisionEnvelope per explicit decision, under `sweatkit.route-decisions.v1`. Route queries union local decisions with supported recovered envelopes, with UUID conflict rejection. Unknown envelope versions are retained without interpretation. Export/replay carries only typed user intent and identity anchors, not geometry or Health facts. The Model additions were supplied by Routes and Cloud; integration adds no Model schema change.

Cloud recovery now notifies LibraryModel to reload the feed, Trends revision and route catalog, without recursively scheduling cloud sync. Route edits refresh the shared model and schedule copying. Routes observes the shared reload revision so profile/threshold/recovery changes cannot leave it relying only on feed-row hashes.

The feed shows truthful record labels and route rank/membership from existing read-only APIs. Historical badge preparation runs off the main actor, invalidates on reload/paging and suppresses stale task results. Detail offers a route comparison link when matching is available. These are derived local views and never enter cloud exports.

## Validation

- Full package suite: **1,572 tests passed**, including Library 148, RouteMatching 284 and Cloud 7. `/tmp/sweatkit-wave2-integrated-tests.log`.
- New integration regression covers route-action cloud restore/re-export, idempotence, local and cloud UUID conflict rejection, and retaining unknown future versions. Existing regression coverage includes source revision, threshold changes, visibility, deletion and cache rebuild.
- Release tooling: **6 tests passed**, `/tmp/sweatkit-wave2-release-tooling.log`.
- Combined unsigned physical-iPhone Release build passed, `/tmp/sweatkit-wave2-integration-build.log`. Final UI identifiers were subsequently compiled by the integration harness and the successful signed archive.
- **Three integrated simulator UI tests passed:** populated light flow (`/tmp/sweatkit-wave2-ui-third.xcresult`), populated dark flow and large-text feed → detail → comparison (`/tmp/sweatkit-wave2-ui-final.xcresult`). Earlier first/second runs failed due to ambiguous or incomplete test selectors for the date picker and are not passing evidence.
- The flows traverse real RootView tabs: feed → Routes → route → comparison/scrub/back → Trends/date filter → feed → detail → analysis/back → indoor detail/back → Settings → iCloud. Large-text flow verifies the new route comparison link.
- Simlock-leased iPhone 18 Pro Max simulator, iOS 27.2. Reproduce with `python3 Scripts/IntegrationValidation/prepare.py /tmp/integration-harness`, XcodeGen and Simlock. Only the temporary entry point injects a fixture library; no production fixture mode is added. Data includes real ride/walk/Zwift FIT files plus the route harness's explicitly test-only time-scaled Health derivative for repeated-route comparison. Live source adapters are absent from the harness, hence Settings' “Opening library…” source text is not live sync evidence.
- 23 downscaled actual app captures in `Evidence/WAVE2-INTEGRATION/`; original screenshots are in the result bundles. Screenshots demonstrate rendering, not live-cloud or physical-device acceptance.

## Nine-board visual comparison

Approved targets were not changed. Light/dark captures cover all nine surfaces, with sparse fixture data rather than the boards' illustrative history.

| Board | Integration result and remaining difference |
| --- | --- |
| 01 Feed | Real record/route labels, thumbnails and weekly groups work. Native header/row spacing remains looser; source attribution and record labels differ from compact board chips. |
| 02 Flyover | Floating stats/timeline and route-comparison entry are connected. Native controls, cursor styling and route camera differ; phone camera feel remains open. Large-text stats intentionally scroll inside a bounded area. |
| 03 Analysis | Shared timeline, real summary and analysis work. Default medium sheet is shorter/less dense than reference; detailed historical comparison and source-defined segment presentation remain follow-up work. |
| 04 Indoor | Real power/HR charts and shared timeline render without a map. Chart labels/axis density and neutral-versus-effort treatment differ from reference. |
| 05 Routes | Real grouping, counts, thumbnail and navigation work. Sparse one-route history cannot establish dense-list parity; inherited review-state captures cover the separate ambiguous-course case. |
| 06 Route | Terrain, history, rankings and effort navigation work. Two efforts do not establish dense-history label behavior; native panel spacing differs. |
| 07 Comparison | Paired data, shared scrub clock and navigation work, including from detail. Native slider/segmented controls and tab-bar overlap reduce visible summary space relative to the board. At large text lower charts require scrolling. |
| 08 Trends | All sections are implemented; filters and navigation work. Sparse history, explanatory copy and calendar targets produce lower density than the board. Full-year phone rendering and dense-history comparison remain open. |
| 09 Settings | Shared appearance and cloud destination work. Threshold suggestion/review flow, source/deep-scan status presentation and grouping still differ from target. Simulator capability states are not live-account evidence. |

## Cloud deployment and live gates

Read-only exports confirmed the container exists, but development and production initially contained only Users. The additive RecoveryRecord schema was validated, installed in development and verified by re-export. `CloudKit/schema.ckdb` records that exact schema. No user activity data was uploaded.

The user promoted the schema through CloudKit Console. A fresh read-only production export on 5 November confirmed RecoveryRecord with envelope BYTES and original ASSET (`/tmp/sweatkit-wave2-cloud-production-deployed.ckdb`). Production schema deployment is now verified. The earlier CLI/browser limitation is no longer a deployment blocker. See `CloudKit/README.md`.

Still required: signed-device cloud transport and two-device/wiped-device restore, Health UUID reattachment, the user's Health reference run, elapsed/timer/moving split agreement, real repeated-history false-merge review, phone camera/performance, comprehensive accessibility and full design parity. Feature implementation and passing integration tests do not close these gates.

## Signed build handoff

Release source: `5b02064` on main. `release.sh --no-upload --skip-tests` completed archive and App Store IPA export for **0.1.0 (309.20.37)** from a clean detached checkout. Tests were skipped inside the release script only because the full package, tooling and integrated UI suites had already passed. Artifacts and release log are retained in `build/release/0.1.0-309.20.37/`. The signed archive was subsequently uploaded on 5 November using Xcode’s archive export with destination `upload`, without rebuilding or rerunning tests. `upload.log` reports **Upload succeeded**, **EXPORT SUCCEEDED**, and that Apple has begun processing the package. Processing completion and tester availability have not been verified. Release tag `ios/v0.1.0-309.20.37` identifies source `5b02064`.

The exported app passes `codesign --verify --deep --strict`. Entitlements confirm Production CloudKit, the intended container, production push, HealthKit and Health background delivery. Signed build/provisioning is therefore verified; production schema is separately verified, while live cloud behavior remains an outstanding gate. The temporary release checkout and simulator lease were released after preserving artifacts.


## Original MVP remaining work after TestFlight upload

Audit on 5 November against `SweatKit - Activity App MVP Spec.md`, current source and user-reported acceptance. Passing fixture tests and simulator screenshots are not physical-device acceptance.

### Implementation and presentation

- **M5 feed headline:** cycling still uses average power in FeedRules and ActivityFeedView. Switch eligible rides to weighted power, including feed cache versioning/recomputation and truthful unavailable handling.
- **On-foot splits:** split calculations exist, but ActivityAnalysisView does not present the required kilometre table with pace, heart rate and ascent.
- **Known-route context:** detail links to comparison and shows rank, but lacks the full occurrence ordinal and time-behind-best sentence required by the spec.
- **Source attribution:** feed sources exist; complete consistent source attribution across detail, Routes and Trends as required by the spec.
- **Approved design parity:** all nine surfaces have remaining differences documented above. Specific functional presentation gaps include the activity-versus-historical power-curve overlay and designed Settings threshold review flow. Threshold estimation and the Trends prompt to review a higher estimate already exist; these are not missing analysis engines. Source-defined segment presentation is a later enhancement, separate from the original kilometre-split requirement.

### Acceptance still open

- **HealthKit and timing:** retest the Apple Watch reference activity (2.53 km, 23:29, 116 spm in Fitness), distance/gradient/cadence and newly added running metrics; reconcile elapsed, timer and moving time in summary/splits. Importer fixes are implemented, phone confirmation is outstanding.
- **M1/M2 performance:** 500 representative files on the phone; corrupt/truncated import leaving the library unchanged; cached five-hour ride under one second, smooth scrubbing/dimming, steep terrain and playback-camera feel.
- **M3 recovery:** live late-upload/deep-scan and interrupted-backfill checks, expired/revoked credentials, partial/denied Health permissions and delayed samples/routes, network recovery, no duplicate imports. Overlap/partial-recording and keep-separate-through-a-third-record cases remain untested with the user's library; permanent deletion needs a disposable record.
- **Checkpoint:** two weeks of daily use replacing the existing viewing workflow.
- **M4:** signed-device cloud copy, two-device convergence, wiped-device restore, offline deletion/tombstones, retry behavior and stable Health UUID reattachment. Production schema and signing are complete; transport/restore acceptance is not.
- **M6:** manual review of genuine repeated routes in real history, with no false merges; large-library matching performance.
- **M7:** each Trends view renders a full year in under one second on the phone. Host aggregation timing alone does not meet this gate.
- **M8:** full VoiceOver, Dynamic Type, contrast/transparency, Reduce Motion and empty/error recovery review; dense real-history visual comparison against the boards.

Already user-accepted: library contents, basic map/scrub, analysis/reopen, indoor behavior, offline use, units and hide/restore. These are not being reopened wholesale. The user has no intentional overlapping recordings and does not know their HR threshold; those checks remain unverified rather than failed.

### Suggested next parallel work

1. Analysis and spec completion: weighted-power feed, kilometre splits, route context and timing semantics.
2. Design completion: nine-board parity, consistent attribution, historical overlay and Settings threshold review.
3. Device acceptance: Health reference retest, live sync/recovery, two-device cloud, performance and accessibility evidence. Coordinate shared devices and keep acceptance fixes isolated from the two implementation branches.

Future-spec features (AI, route planning/course push, video export, partial-route matching, fitness/fatigue modelling and additional platforms) are not v1 blockers.
