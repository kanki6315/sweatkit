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
| `Fixtures/` | Real FIT files shared by every package's tests | |
| `project.yml` | XcodeGen spec. `SweatKit.xcodeproj` is generated and not committed. | |

The spec's "Core" package is split into Model, Ingest and Identity so that each can be built and tested alone. Storage and the Garmin and HealthKit adapters do not exist yet.

## Commands

```sh
Scripts/test-packages.sh                    # swift test in every package
Scripts/test-packages.sh SweatKitAnalysis   # one package
xcodegen generate                           # after changing project.yml or adding a package
xcodebuild -project SweatKit.xcodeproj -scheme SweatKit \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

## Rules

- Packages other than Model never depend on each other. Anything two of them need goes in Model.
- Model is the shared contract. Change it only by adding to it, and say so in the summary of the work, because other packages are built against it in parallel.
- Analysis, Route Matching and Identity are pure Swift: no interface, network, storage or FIT SDK code.
- Tests use Swift Testing. Fixtures come from `Fixtures` in `SweatKitTestSupport`; see `Fixtures/README.md` for what each file holds and how to add one.
- Missing is never zero, and unavailable is never zero. Use `Series` quality and `Metric.unavailable` instead of placeholder values.
- Expected values in metric and matching tests are worked out from the spec's rules, not copied from the implementation's output.
