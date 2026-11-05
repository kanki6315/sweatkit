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
- Health originals, stream caches and checkpoint files are individually excluded from OS backup. **Historical gap, now addressed in implementation:** automatic review rejected whole-root backup exclusion and that broad change was not applied. The merged storage design excludes Health/local derived metadata while retaining a non-Health recovery manifest, originals and user decisions. Host tests cover migration and eligible-file-only restore; actual OS-backup behavior remains unverified. See `HEALTH-STORAGE.md`.

- Feed/detail integration: library **80 tests** pass, including complete-week aggregation beyond a feed page, alternative-channel offers, and partial Health/Garmin recording recovery. Detail **67 tests** pass. Log: `/tmp/sweatkit-m123-targeted.log` (local, ephemeral).
- Latest simulator compile including Health query cancellation passed: `/tmp/sweatkit-cancellation-build.log`. This is compile evidence only; no new simulator UI or physical-device checks were performed. The unsigned Release device artifact has also been rebuilt with these changes (`/tmp/sweatkit-m123-device-build.log`); signing, installation and device checks remain outstanding.

- Full regression for the feed/detail and Health cancellation checkpoint: **1,478 tests across all 14 packages passed** (`Scripts/test-packages.sh`, `/tmp/sweatkit-m123-regression.log`). No required interactive checks are inferred from this result.

- Synthetic scale regression: **500 distinct Health snapshot imports**, reopen from disk, complete cursor pagination, sport-filtered weekly totals and source retention passed in 69.6 seconds on the development host (`swift test --package-path Packages/SweatKitLibrary --filter LibraryScaleTests`, `/tmp/sweatkit-scale-tests.log`). This covers persistence at 500 activities; it does **not** prove representative FIT import throughput or smooth device browsing.

- Parallel implementation integration: all 14 suites passed (**1,499 tests**, `/tmp/sweatkit-integrated-regression.log`). After six added cross-layer deletion/locality tests, the affected Library suite passed **104 tests** (`/tmp/sweatkit-integrated-library-final.log`); the remaining packages are unchanged. The synthetic 500-activity case passed in 154.6 seconds within that concurrent suite; this is not a representative-file or device-throughput benchmark.

- Final app integration builds passed for iOS Simulator and unsigned physical iPhone (`/tmp/sweatkit-m123-final-simulator.log`, `/tmp/sweatkit-m123-final-device.log`). Through a Simlock lease, the app installed/launched on iPhone 18 Pro / iOS 27.2; `launchctl` subsequently confirmed PID 39678 remained running. The lease was released. This certifies install/launch only, not rendering or touch flows.
- Integrated Health callback completion passed 100 concurrent-race rounds and reentrant completion using production code (`Scripts/check-health-delivery.swift`). Foreground/background Health scheduling and observer registration are implemented; no actual permission-backed delivery was observed. See `HEALTH-DELIVERY-ACCEPTANCE.md`.

## Implementation and remaining acceptance

| Requirement | Current evidence / remaining work |
| --- | --- |
| Persistent FIT import and feed | App now opens Application Support library, accepts multiple files, retains security-scoped access, reports per-file outcomes, supports cancellation and paged search/sport/setting filters. File-picker journey and relaunch need UI verification. |
| Complete feed | Cached route thumbnails/indoor sparklines, full-filter weekly totals (independent of pagination), date range filters, source badges, removal/stale indicators and a recalculation action are implemented. Revision-specific locality lookup and generated-title updates are implemented; explicit user titles survive updates and backup restore. Offline lookups retry without blocking import. Thumbnail rendering, scrolling, date filtering and recalculation UI need interaction verification. Record and route badges depend on later milestones. |
| 500-file library | Store has paging tests; a representative 500-file import, relaunch and browsing-performance check is still required. |
| Corrupt/truncated imports | Existing pipeline tests pass; app error presentation and unchanged-library checks through Files remain unverified. |
| Athlete profile | Settings edits optional thresholds, weight, units and date-effective power history; saves and recomputes. Existing staleness tests pass. Form and correction journey need UI verification. |
| Detail assembly | Prepared route, palette, cursor stats, timeline, range stats, axis/stop controls and map/camera options connected. Analysis sheet with gap-preserving charts, lap selection, zones, shared scrub state, playback speeds and no-GPS/indoor analysis presentation are implemented. Chart preparation tests cover extrema, gaps, five-hour point reduction, lap partitioning and stationary pace. Visual/gesture verification remains outstanding; recorded lap ends now delimit lap statistics, preserving gaps and trailing unlapped samples. Tests cover explicit intervals. |
| Detail performance | No current app measurement of cached 5-hour load under 1 s or on-device scrubbing. Existing component gates are not evidence for the assembled screen. |
| Garmin adapter | Atomic JSON checkpoints/summaries and real pipeline integration implemented and tested. Reads corrupted metadata as an explicit error; never resets progress silently. |
| Garmin app setup/recovery | Keychain storage, key validation, foreground refresh, pause/resume and typed outcome messages implemented. Live key/token/network/rate-limit recovery and account history not yet exercised. Foreground launch/return sync, optional quick background refresh, full-reconciliation controls, user-entered key lifetime and seven-day warnings are implemented. See `GARMIN-ACCEPTANCE.md` for test and live-check boundaries. |
| Garmin reconciliation | Real planner → ZIP/FIT → persistent library tests pass for quick/deep late uploads, interrupted backfill, changing listings, safe deletion inference and restart. Live-account validation remains. |
| HealthKit | Implemented initial read-only onboarding and anchored workout/route/quantity changes, durable anchors plus pending IDs, routes and sample snapshots, revision/rebuild support, summary-only display, explicit deletion retention and refresh/recovery messages. Snapshot and checkpoint tests pass; live Health queries, permission changes, route/sample update timing and partial permissions remain unverified. Foreground refresh, background-launch observer registration and opportunistic background refresh are implemented. Active anchored/sample/route queries stop on task cancellation and resume the waiter once; late callbacks are ignored. Delivery completion follows durable anchor/pending capture, with foreground recovery after failure. Live pause/resume behavior remains unverified. |
| De-duplication | Identity now runs in the import pipeline. Add-only links/decisions/tombstones persist in an atomic journal; affected feed rows and metrics replace in one store save. Merge/split, primary, rename, hide/restore and review screens are implemented. Integration tests cover merge/split, restart, originals retained, and a third recording respecting keep-separate. Health/Garmin overlap and partial-recording integration tests pass: overlapping full recordings merge, partial recordings stay separate for review, and keep-separate survives restart/reimport. Alternative-channel notices are implemented and tested. Permanent deletion now commits tombstones before erasing recordings, preserves shared originals and recovers after interruption. Garmin cached/pending summaries are pruned through the existing bridge; concurrency and retry tests cover stale in-flight writes. Real source identifier mapping and visual verification remain. |
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

Exercise complete simulator journeys and the reference-device checklist using the integrated build. Resolve issues found during those checks. Representative FIT-library performance and live-source/permission validation remain. Keep M4 iCloud, M5-specific rollout, routes UI and trends outside this goal.

## HealthKit API references

- Apple authorization guidance: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- Apple route queries: https://developer.apple.com/documentation/healthkit/hkworkoutroutequery
- Apple anchored queries: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
- The installed SDK's `HKHealthStore.h` confirms authorization completion reports that prompting completed, not that reads were granted. Empty query results never infer deletion or denied access.

### Physical-device compile evidence

`xcodebuild -project SweatKit.xcodeproj -scheme SweatKit -configuration Release -destination 'generic/platform=iOS' -derivedDataPath DerivedData/Device CODE_SIGNING_ALLOWED=NO build` passed. Log: `/tmp/sweatkit-device-build.log`. Artifact: `DerivedData/Device/Build/Products/Release-iphoneos/SweatKit.app`. This artifact is unsigned and cannot be installed as-is. It is not evidence of on-phone performance or permission behavior.
