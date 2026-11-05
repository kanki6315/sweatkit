# M1–M3 acceptance ledger

Updated 5 November 2026. The goal is the complete daily-use core defined in the MVP spec, ready for its two-week use checkpoint. Implementation is not acceptance. Nothing below certifies device performance or live source behavior.

## Evidence collected

- Baseline main (`79f4e1f`): all 14 package suites, **1,454 tests passed** using `Scripts/test-packages.sh`. Log: `/tmp/sweatkit-baseline-tests.log` (local, ephemeral).
- Added persistent Garmin bridge: **68 library tests passed**, including five new integration tests for checkpoints, repeated import, source removal/restoration, rejected import, interrupted import before metadata publication, tombstones and corrupt metadata. Log: `/tmp/sweatkit-library-tests.log` (local, ephemeral).
- iOS Simulator app build passed after import/feed/detail/profile and Garmin connection integration. Log: `/tmp/sweatkit-app-build.log` (local, ephemeral).
- Installed and launched the first integrated app on the iPhone 18 Pro simulator via `simctl`. This proves launch only. No rendered-state or interaction verification: computer-use access to Device Hub was denied by organization policy.

- Identity integration: 47 store tests and 72 library tests passed, including atomic merge/split validation and persisted concurrent-decision convergence. Logs: `/tmp/sweatkit-identity-integration.log`, `/tmp/sweatkit-identity-final.log`. App build passed. UI interaction remains unverified.
- Library mutations now serialize across sources to prevent an import racing a merge/split. The 500-file performance acceptance check must assess this; bounded file reading remains concurrent.

- Full regression after identity integration: **1,465 tests across all 14 packages passed** (`Scripts/test-packages.sh`, `/tmp/sweatkit-all-tests.log`). Final simulator build passed.
- Device checklist prepared in `Documentation/DEVICE-ACCEPTANCE.md`; no device checks are marked passed.

- Health snapshot/checkpoint coverage: **77 library tests passed**, including four new snapshot tests and one checkpoint recovery test. Logs: `/tmp/sweatkit-health-final-tests.log`. Simulator build passed (`/tmp/sweatkit-health-build.log`). No live Health data or permissions were accessed.
- Health originals, stream caches and checkpoint files are individually excluded from OS backup. **Shared metadata backup isolation remains unresolved:** the common database and identity candidate journal contain Health-derived summaries. Automatic approval review rejected excluding the entire library root because it would remove backup protection for non-Health data. That broad change was not applied. A narrower storage design or explicit user-approved backup policy is still required before claiming local-only Health persistence.

- Feed/detail integration: library **80 tests** pass, including complete-week aggregation beyond a feed page, alternative-channel offers, and partial Health/Garmin recording recovery. Detail **67 tests** pass. Log: `/tmp/sweatkit-m123-targeted.log` (local, ephemeral).
- Latest simulator compile including Health query cancellation passed: `/tmp/sweatkit-cancellation-build.log`. This is compile evidence only; no new simulator UI or physical-device checks were performed. The unsigned Release device artifact has also been rebuilt with these changes (`/tmp/sweatkit-m123-device-build.log`); signing, installation and device checks remain outstanding.

- Full regression for the feed/detail and Health cancellation checkpoint: **1,478 tests across all 14 packages passed** (`Scripts/test-packages.sh`, `/tmp/sweatkit-m123-regression.log`). No required interactive checks are inferred from this result.

## Implementation and remaining acceptance

| Requirement | Current evidence / remaining work |
| --- | --- |
| Persistent FIT import and feed | App now opens Application Support library, accepts multiple files, retains security-scoped access, reports per-file outcomes, supports cancellation and paged search/sport/setting filters. File-picker journey and relaunch need UI verification. |
| Complete feed | Cached route thumbnails/indoor sparklines, full-filter weekly totals (independent of pagination), date range filters, source badges, removal/stale indicators and a recalculation action are implemented. Locality remains missing. Thumbnail rendering, scrolling, date filtering and recalculation UI need interaction verification. Record and route badges depend on later milestones. |
| 500-file library | Store has paging tests; a representative 500-file import, relaunch and browsing-performance check is still required. |
| Corrupt/truncated imports | Existing pipeline tests pass; app error presentation and unchanged-library checks through Files remain unverified. |
| Athlete profile | Settings edits optional thresholds, weight, units and date-effective power history; saves and recomputes. Existing staleness tests pass. Form and correction journey need UI verification. |
| Detail assembly | Prepared route, palette, cursor stats, timeline, range stats, axis/stop controls and map/camera options connected. Analysis sheet with gap-preserving charts, lap selection, zones, shared scrub state, playback speeds and no-GPS/indoor analysis presentation are implemented. Chart preparation tests cover extrema, gaps, five-hour point reduction, lap partitioning and stationary pace. Visual/gesture verification remains outstanding; lap boundaries currently use recorded starts, and explicit lap-end handling needs review. |
| Detail performance | No current app measurement of cached 5-hour load under 1 s or on-device scrubbing. Existing component gates are not evidence for the assembled screen. |
| Garmin adapter | Atomic JSON checkpoints/summaries and real pipeline integration implemented and tested. Reads corrupted metadata as an explicit error; never resets progress silently. |
| Garmin app setup/recovery | Keychain storage, key validation, foreground refresh, pause/resume and typed outcome messages implemented. Live key/token/network/rate-limit recovery and account history not yet exercised. Launch/background scheduling, full-reconciliation controls, user-entered key expiry period and the seven-day expiry warning remain. |
| Garmin reconciliation | Existing planner suite passes. Need end-to-end bridge + planner tests for late uploads, interrupted backfill, changing listings, deletions and restart, plus live-account validation. |
| HealthKit | Implemented initial read-only onboarding and anchored workout/route/quantity changes, durable anchors plus pending IDs, routes and sample snapshots, revision/rebuild support, summary-only display, explicit deletion retention and refresh/recovery messages. Snapshot and checkpoint tests pass; live Health queries, permission changes, route/sample update timing and partial permissions remain unverified. Active anchored/sample/route queries now stop on task cancellation and resume the waiter once; late callbacks are ignored. Live pause/resume behavior remains unverified. |
| De-duplication | Identity now runs in the import pipeline. Add-only links/decisions/tombstones persist in an atomic journal; affected feed rows and metrics replace in one store save. Merge/split, primary, rename, hide/restore and review screens are implemented. Integration tests cover merge/split, restart, originals retained, and a third recording respecting keep-separate. Health/Garmin overlap and partial-recording integration tests pass: overlapping full recordings merge, partial recordings stay separate for review, and keep-separate survives restart/reimport. Alternative-channel notices are implemented and tested. Real source identifier mapping, permanent deletion and visual verification remain. |
| Concurrent decisions | Persisted-pipeline test passes for an offline split concurrent with rename/hide, exchanging add-only records in reversed order and confirming both libraries converge to two hidden, correctly named activities. |
| Device build/checklist | Unsigned Release build for physical iPhone succeeds, including HealthKit entitlement configuration and read usage text. Device checklist is prepared. Signing/provisioning, installation and actual device checks remain; existing flyover and timeline checklists remain applicable. |

## Required final journeys

1. FIT import → persisted, filtered feed → full detail → relaunch → same activity and originals.
2. Garmin and HealthKit overlapping recordings → exactly one activity with attribution and deterministic primary source.
3. Partial recording inside a full recording → review flag, no automatic merge; keep-separate remains respected through a third record.
4. Late Garmin upload, interrupted backfill and source changes → resumed reconciliation without gaps or duplicates.
5. Denied Health reads, expired Garmin key/token, network failure and storage failure → actionable recovery without reinstall or data loss.
6. Profile correction → only affected results stale → recalculation → correct zones and values.
7. Reference device: representative library browsing, five-hour cached load, scrubbing, accessibility, dark casing and light-mode chart readability.

## Next implementation sequence

Verify/harden HealthKit and complete remaining identity/deletion cases, then complete the remaining feed/detail flows and source controls. Add cross-layer acceptance tests before device validation. Keep M4 iCloud, M5-specific rollout, routes UI and trends outside this goal.

## HealthKit API references

- Apple authorization guidance: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- Apple route queries: https://developer.apple.com/documentation/healthkit/hkworkoutroutequery
- Apple anchored queries: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
- The installed SDK's `HKHealthStore.h` confirms authorization completion reports that prompting completed, not that reads were granted. Empty query results never infer deletion or denied access.

### Physical-device compile evidence

`xcodebuild -project SweatKit.xcodeproj -scheme SweatKit -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData/Device CODE_SIGNING_ALLOWED=NO build` passed. Log: `/tmp/sweatkit-device-build.log`. Artifact: `DerivedData/Device/Build/Products/Release-iphoneos/SweatKit.app`. This artifact is unsigned and cannot be installed as-is. It is not evidence of on-phone performance or permission behavior.
