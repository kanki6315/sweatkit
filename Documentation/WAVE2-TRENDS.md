# Wave 2 — Trends

Branch: `codex/wave2-trends`. Baseline verified with `git merge-base --is-ancestor 0b1f05a HEAD`; starting HEAD was exactly `0b1f05a`. No merge, push or release.

## Delivered contracts

- Additive Library files `TrendsHistory.swift` and `TrendsAggregation.swift`; no Model or Store schema changes, new package wiring, cloud payloads, or changes to the feed/Routes/Settings screens.
- `ActivityLibrary.trendsHistory()` returns compact local activity metadata, existing `ActivityMetrics`, cached power curves and explicit staleness. All metrics come from `ActivityAnalysis`; no alternate power or load formula. Old metrics are withheld until recomputation.
- Curves use 5, 15, 30, 60, 120, 300, 600, 1200, 1800 and 3600 seconds. Derived cache kind `trends.powerCurve.v1.<AlgorithmVersion.powerCurve>` carries the metrics input/profile/algorithm provenance. First access computes uncached curves off the main thread; subsequent queries read derived payloads, not full streams. Revised inputs invalidate the cache; deletion/visibility is resolved by the existing feed. The cache stays in the existing local derived database, outside backup/recovery payloads, including Health-derived curves.
- `TrendsAggregation.recordBadges(for:in:)` is a read-only feed integration hook. Pass visible historical summaries; it returns records first attained by that activity relative to preceding history of the same sport and indoor/outdoor setting. Equal performances retain the first attainment; deterministic identity order resolves simultaneous starts. ActivityFeedView is unchanged.
- `LibraryModel.trendsRevision` increments after successful reloads. Trends reloads on that revision; import, sync, visibility and threshold flows already call reload. Future writers must call `LibraryModel.reload()` after mutation. Filters only recompute the in-memory presentation off the main actor.
- RootView change is confined to the Trends tab content. Existing AppTheme, shared Settings presentation and navigation remain authoritative.

## Semantics and design choices

The screen follows board 08's section order: Volume, Power curve, Threshold power, Efficiency, Records, Load calendar. It uses neutral charts and grouped semantic surfaces, native pickers and the shared accent. Sport, date-window and indoor/outdoor filters apply throughout. Volume periods and calendar days expose their activities; records link directly to detail; power and efficiency expose eligible activity lists.

Volume tracks known sums and unavailable counts separately. Incomplete bars are omitted, labelled incomplete, and never plotted as zero. Empty periods describe the imported library, not proof of inactivity. Time is moving time, consistent with feed volume. The current period ends at query time; comparison periods are complete. Weekly prior-year comparisons use week number and week-based year (a nonexistent prior week 53 has no comparison). Monthly/yearly comparisons use calendar arithmetic. Period boundaries and daily grouping use the viewing device's calendar/timezone; DST days are not assumed to be 86,400 seconds.

All section windows intersect the global date filter. Rolling threshold history deliberately reads up to 90 days before each plotted date so its calculation has the required lookback. Estimates are 95% of the best eligible 20-minute power in the inclusive preceding 90 calendar days, excluding future activities. Missing estimates remain gaps; no threshold setting is changed automatically. Efficiency requires timer duration >=20 minutes, cycling, variability strictly below 1.10 and available cycling efficiency. The trend is ordinary least-squares regression, not a fitness model.

Records are best power, fastest Analysis-supported distances (by sport), longest cycling distance and most ascent by sport. Hidden and stale records do not qualify. Missing measurements cannot win records. Calendar dots mark any unavailable load in a day, even alongside available activities; days open their actual activities. Calendar cells use 44-point targets (80 points at accessibility sizes) and horizontal scrolling, so density differs from the illustrative board.

## Validation

- Existing Library suite: **119 tests passed**, including 500-activity persistence/filtered paging, Health backup isolation and deletion regressions (`/tmp/sweatkit-trends-tests.log`).
- Analysis suite: **289 tests passed** (`/tmp/sweatkit-trends-analysis.log`).
- New Trends suite: **10 tests passed** (`/tmp/sweatkit-trends-focused2.log`): exact rolling boundary/future exclusion, missing/stale semantics, steady boundaries/ties, filters, period comparisons, DST/unavailable daily load, source revision/deletion, cache reopen/visibility/threshold invalidation, fastest-distance sport separation, simultaneous activity point identity, representative-year benchmark.
- Unsigned generic-iPhone build passed using `/tmp/sweatkit-trends-build`; simulator harness build passed using `/tmp/sweatkit-trends-sim`. Final production generic-iPhone build **passed** after removing the temporary harness (`/tmp/sweatkit-trends-production-build.log`). Durable result excerpts are in `Evidence/WAVE2-TRENDS/validation.txt`.

### Performance scope

Debug host benchmark over 365 synthetic compact summaries: **0.156727375 seconds** for four volume measures, rolling threshold history, curves, records, efficiency/regression and indexed daily load together. A prior test that repeatedly used Calendar matching for every day took 1.0397 seconds; the shared daily-load implementation now groups once by calendar day. Synthetic data exists only in tests. This measures aggregation, not SwiftUI rendering, disk query time, cold curve backfill, or phone performance. Cold historical curve backfill can exceed one second and presents a loading state. The spec's under-one-second rendered-year gate on the reference phone remains open.

## Capture evidence and remaining acceptance

Actual simulator captures are in `Evidence/WAVE2-TRENDS/`. Runtime: iOS 27.2, leased iPhone 18 Pro Max simulator through Simlock. Temporary launch-only harness imported the committed outdoor ride, Zwift ride and walk FIT files without changing dates or samples, selected All time, and opened Trends. Controlled read-error state is explicitly a harness injection. No fixture/harness data or launch flags ship in production. These captures are not live-device acceptance.

Capture inventory: `top`, `power`, `thresholds`, `records`, `calendar`, `empty` and `error` in light/dark; `top-large-dark`, `records-large-dark`, `calendar-large-dark` at accessibility-extra-extra-extra-large. Unavailable threshold setting, empty steady-ride efficiency and unavailable calendar load are visible with the unchanged FIT fixtures. Record rows and power ticks use numeric duration order and readable units. A second calendar pass constrains the weekday gutter and separates month/day labels.

The independent Impeccable review found and verified fixes for neutral record text/contrast, duration labels and numeric ordering, accessibility heading/control/record layouts and the shared-shell error/empty captures. The final calendar-only verdict marked the temporal anchors resolved. All five original material fixes are resolved; reviewer disposition: **ship within the reviewed simulator scope**, with device, interaction and dense-history gates still open. Remaining visual differences: explanatory copy increases vertical space; calendar targets and date labels are larger than the board; threshold estimates use separated dots to preserve unavailable gaps; prior-year volume comparisons use square marks rather than the board's short horizontal strokes; native tab/header spacing differs. Sparse fixture screenshots do not establish dense-history board parity.

Impeccable reported pre-existing PRODUCT.md metadata drift (legacy Register section/schema). It was not changed; optional `init` cleanup is separate from Trends.

## Integration and device gates

- No peer integration dependency or shared schema migration. Cloud must continue excluding derived caches and Health facts from copy/recovery. Record badge feed integration is an opt-in consumer of the read-only query.
- Verify full-year warm query + SwiftUI rendering under one second on physical reference iPhone; measure cold curve preparation separately. The host aggregation benchmark does not certify it.
- Exercise real-library filter changes, chart/period/day drill-down, detail/back navigation, recompute after threshold correction, source updates, hide/restore/delete and foreground reload on the integrated signed build.
- Verify VoiceOver chart traversal and calendar navigation, Increase Contrast, Reduce Transparency and maximum Dynamic Type on device. Native Charts supplies accessible marks, and calendar cells have spoken date/count/load labels; these are implementation facts, not a completed assistive-technology audit.
- Dense representative real history is still needed to accept board parity, overlapping chart labels, curve comparison and efficiency regression visually. The committed fixtures are sparse and cannot prove those states.
