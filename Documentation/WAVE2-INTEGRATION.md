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

Production schema promotion is outstanding. Apple's CLI rejects production schema validation; managed browser policy denied access to CloudKit Console. This is a deployment blocker for TestFlight iCloud testing, not a failed unit test. See `CloudKit/README.md`.

Still required: production schema promotion, signed-device cloud transport and two-device/wiped-device restore, Health UUID reattachment, the user's Health reference run, elapsed/timer/moving split agreement, real repeated-history false-merge review, phone camera/performance, comprehensive accessibility and full design parity. Feature implementation and passing integration tests do not close these gates.

## Signed build handoff

Release source: `5b02064` on main. `release.sh --no-upload --skip-tests` completed archive and App Store IPA export for **0.1.0 (309.20.37)** from a clean detached checkout. Tests were skipped inside the release script only because the full package, tooling and integrated UI suites had already passed. Artifacts and release log are retained in `build/release/0.1.0-309.20.37/`. No TestFlight upload or release tag was made.

The exported app passes `codesign --verify --deep --strict`. Entitlements confirm Production CloudKit, the intended container, production push, HealthKit and Health background delivery. Signed build/provisioning is therefore verified; production schema promotion and live cloud behavior remain separate outstanding gates. The temporary release checkout and simulator lease were released after preserving artifacts.
