# SweatKit

A native iOS app for viewing one person's own rides and walks. Local-first, no server.

- `SweatKit - Activity App MVP Spec.md` is the contract. Its definitions and thresholds are what the tests check.
- `PRODUCT.md` and `DESIGN.md` govern anything a user sees.

## Layout

| Path | Holds | Depends on |
| --- | --- | --- |
| `App/` | The SwiftUI app target | Every package |
| `Packages/SweatKitModel` | Shared types: identities, recorded activity, analysis stream, athlete profile, metric and provenance. Also `SweatKitTestSupport`, which locates fixtures. | Nothing |
| `Packages/SweatKitIngest` | FIT decoding and building the 1 Hz analysis stream | Model, Garmin FIT SDK |
| `Packages/SweatKitIdentity` | De-duplication, links, decisions, tombstones | Model |
| `Packages/SweatKitAnalysis` | Metrics from the analysis stream | Model |
| `Packages/SweatKitRouteMatching` | Route detection, alignment, comparison | Model |
| `Packages/SweatKitGarmin` | Garmin Personal API client: token exchange, activity listing, original-file download. No sync logic. | Nothing |
| `Packages/SweatKitStore` | On-device persistence: originals by content hash, source records and revisions, activities and the feed query, stream files, derived results with provenance, the athlete profile. Persistence only: it never decodes, computes or merges. | Model |
| `Packages/SweatKitTrackCleanup` | Turns a stream's positions into a cleaned track for route matching and a simplified line for the flyover, each point keeping its sample index. | Model |
| `Packages/SweatKitFlyover` | The MapKit flyover view and its camera and drawing logic. Takes an already-prepared route. | Model |
| `Packages/SweatKitTimeline` | The detail screen's scrubbing timeline and stats panel. Takes already-prepared series and the same scrub binding as the flyover. | Model |
| `Packages/SweatKitLibrary` | The pipeline from an imported file to a stored activity: decode, store, build the stream, compute metrics, write the feed row, and recompute what goes stale. A layer above the leaf packages. | Model, Store, Ingest, Analysis, Sync, Identity |
| `Packages/SweatKitDetail` | Prepares one activity's stream for the detail screen: the coloured route, the timeline's series, stats at the cursor and over a range. A layer above the leaf packages. | Model, Analysis, TrackCleanup, Flyover, Timeline |
| `Packages/SweatKitSync` | Garmin reconciliation: quick sync, deep scan, backfill and deletion inference, behind interfaces for Garmin and for the library. No storage of its own. | Model, Garmin |
| `Packages/SweatKitPalette` | The colours of the data: power, heart-rate, pace and gradient ramps in band order, and the map line's casing. `DESIGN.md` records the values and how they were measured. | Nothing |
| `Spikes/` | The M0 probe tool and the device harnesses for the flyover and the timeline, with gate results in `RESULTS.md` and device checklists in each `README.md`. Throwaway: nothing depends on them. | |
| `Fixtures/` | Real FIT files shared by every package's tests | |
| `project.yml` | XcodeGen spec. `SweatKit.xcodeproj` is generated and not committed. | |

The spec's "Core" package is split into Model, Ingest and Identity so that each can be built and tested alone. Storage is `SweatKitStore` and the pipeline that feeds it is `SweatKitLibrary`. The app now has initial import, feed, detail, profile and Garmin connection screens, and Library contains the persistent Garmin sync adapter. Pipeline matching and persisted merge/split/title/primary/visibility decisions are implemented, with duplicate review and restoration screens. The HealthKit adapter and permanent-deletion flow do not exist yet. `Documentation/M1-M3-ACCEPTANCE.md` records remaining implementation and verification; these screens are not yet milestone-complete.

M0 is closed: all five gates passed. `Spikes/GarminPull/RESULTS.md` and `Spikes/Flyover/RESULTS.md` hold the evidence, the decisions, and what was left unmeasured.

## Commands

```sh
Scripts/test-packages.sh                    # swift test in every package
Scripts/test-packages.sh SweatKitAnalysis   # one package
xcodegen generate                           # after changing project.yml or adding a package
xcodebuild -project SweatKit.xcodeproj -scheme SweatKit \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

## Rules

- Leaf packages depend only on Model and never on each other. Anything two of them need goes in Model.
- Two kinds of package sit above the leaves and may depend on them: layers that join several, which today are `SweatKitLibrary` and `SweatKitDetail`, and packages built on one specific leaf, which today is `SweatKitSync` on `SweatKitGarmin`. The app depends on everything. Do not add another layer without saying why a leaf will not do.
- Model is the shared contract. Change it only by adding to it, and say so in the summary of the work, because other packages are built against it in parallel.
- Analysis, Route Matching and Identity are pure Swift: no interface, network, storage or FIT SDK code.
- Tests use Swift Testing. Fixtures come from `Fixtures` in `SweatKitTestSupport`; see `Fixtures/README.md` for what each file holds and how to add one.
- Missing is never zero, and unavailable is never zero. Use `Series` quality and `Metric.unavailable` instead of placeholder values.
- Expected values in metric and matching tests are worked out from the spec's rules, not copied from the implementation's output.
