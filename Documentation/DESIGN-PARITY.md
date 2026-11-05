# Design parity implementation

5 November 2026. Branch `codex/design-parity`, including spec completion `d616ec5` (integrated as `7f8d071`). Approved boards under `Design/Boards` are unchanged. This pass uses those boards and the native/accessibility rules in `DESIGN.md` as its visual contract.

## Implemented

| Board | Changes |
| --- | --- |
| 01 Feed | Compact week totals alongside headings when space permits; tighter row metadata and thumbnail proportions; source and record/route chips; preserves full metadata through accessible fallback layouts. Spec integration supplies weighted-power headline and unavailable handling. |
| 02 Flyover | Neutral back control, circular playback control and directly reachable follow/overview action; precise existing stats, timeline and source attribution. Route context retains the full spec sentence and Compare destination. |
| 03 Analysis | Full-height sheet, source/date/route header, white grouped summary, named power/HR zones with actual resolved bounds, threshold label, bars/time/percent, compact lap table, kilometre splits, historical power overlay with 90-day/year/all-time selector. Compact playback leaves content visible; Expand timeline restores range selection, zoom and axis controls. |
| 04 Indoor | Shorter aligned chart panels and reduced repeated axis copy allow the third channel to sit above the floating timeline. Real effort colours and missing-value gaps remain intact. |
| 05 Routes | Compact thumbnail/metadata/history rhythm with visible contributing sources. Review actions and native search/sort remain available. |
| 06 Route | Four-column effort/best/latest/median summary at normal text size, adaptive layout at larger sizes, compact metadata and explicit source attribution. |
| 07 Comparison | Compact header/gap/chart composition, visible sources, hidden tab bar while comparing so the shared playback strip and summary have room. Title identifies comparison with best only when the selected baseline actually is best. |
| 08 Trends | Compact legends, distinct historical comparison marks and missing-day gaps, less explanatory copy before data, attribution in records/drilldowns/history. Calendar keeps accessible targets. |
| 09 Settings | Separate threshold/HR/weight summaries, real threshold suggestion and review/edit/effective-date/apply flow, and reachable deep scan. Suggestion comparison uses the displayed rounded watts so an applied suggestion does not immediately reappear unchanged. |

Historical power excludes the current activity, later activities, hidden records and stale results. Each duration takes the greatest available recorded power in the selected preceding window; the display labels the source(s) of those winning values. Loading clears the old curve, cancellation cannot replace a new request, and load errors do not masquerade as missing history. Historical processing runs off the main actor.

The threshold review preserves dated history before the chosen effective day, explains same-day replacement, saves through the existing profile/recomputation path and leaves the review open if save fails. It does not silently apply an estimate.

## Verification

Automated implementation verification on a Simlock-leased iPhone 18 Pro Max simulator, iOS 27.2:

- Light and dark integrated flows passed, including full split-table rendering, historical window selection, threshold Apply enabled on first presentation, sheet dismissal, suggestion disappearance and the saved 155 W fixture threshold after reopening Settings. Result: `/tmp/sweatkit-design-captures.xcresult`, log `/tmp/sweatkit-design-captures.log`.
- Final accessibility-size feed → detail → route comparison flow passed after fixing playback-speed wrapping. All adjacent playback controls remain visible. Result: `/tmp/sweatkit-design-large-final.xcresult`, log `/tmp/sweatkit-design-large-final.log`.
- Focused final historical-curve check passed in light and dark after adding duration-formatted axes. Both current and historical curves, source legend, selector and readable time units are visible. Result: `/tmp/sweatkit-design-axis.xcresult`, log `/tmp/sweatkit-design-axis.log`.
- 35 fresh downscaled captures are committed under `Evidence/DESIGN-PARITY/`. `historical-curve-{light,dark}.png`, `splits-table-{light,dark}.png`, `threshold-review-{light,dark}.png`, `threshold-applied-{light,dark}.png` and `detail-route-large.png` show substantive features beyond the initial viewport. Source progression: light/dark at `7e80402`; final large-text correction at `d8fa977`; final historical axis at `c4dd65a`. The singular Settings metadata correction in `d8fa977` does not change the earlier flow's behavior.
- Swift app/test compilation and `git diff --check` passed. Impeccable mechanical scan returned no findings; that scan does not certify native visuals.
- Earlier navigation-only runs passed but a stronger Apply assertion exposed a first-presentation sheet-state defect. The review now owns its draft state; the failing `/tmp/sweatkit-design-final.xcresult` is not passing evidence. Final results above include the fix.
- Simulator lease released after verification. No production Health, Garmin or CloudKit acceptance was performed.

This is implementation verification, not the physical-device acceptance that the user explicitly deferred.

The harness contains real FIT fixtures plus an explicitly test-only shifted/time-scaled derivative for route comparison. Its explicit test profile (100 W, 170 bpm, 72 kg) enables metrics and the threshold-suggestion flow. These values and fixture injections exist only under `Scripts/IntegrationValidation`, not in production behavior.

## Native differences retained intentionally

- System navigation, sheets, segmented controls and text scaling use iOS rather than copying browser chrome.
- Real route terrain, noisy recordings and sparse history differ from the boards' illustrative terrain and dense history. No synthetic user metrics or route memberships are added to production.
- At accessibility sizes, content reflows/scrolls instead of shrinking to board typography. A full expandable timeline is retained alongside the compact analysis playback strip.
- Color encoding follows the committed effort palettes; the neutral timeline cursor follows DESIGN.md even where the illustrative board uses cyan.

Physical Health/Garmin/cloud acceptance, camera feel, performance milestones, full accessibility acceptance and dense real-library review remain deferred until the new TestFlight build.


## Integrated release validation

Both workstreams are merged on main. Release source `7a2955c` includes the spec changes, final large-text control correction and readable historical duration axes. Later evidence-only commits do not change production code.

- Full package suite: **1,576 tests passed**, `/tmp/sweatkit-spec-design-packages.log`.
- Release tooling: **6 tests passed**, `/tmp/sweatkit-spec-design-release-tests.log`.
- Final signed archive and IPA export: **0.1.0 (309.21.15)**; `codesign --verify --deep --strict` passed. Tests were skipped inside the release script because the separate suites and integrated simulator verification had passed.
- Earlier builds 309.21.10 and 309.21.12 were superseded before upload by the final large-text/axis corrections. They were not uploaded.
- The elapsed-versus-moving source comparison, live Health/Garmin/iCloud behavior, phone performance, full accessibility acceptance and daily-use checkpoint remain deferred for the user’s next acceptance session.

TestFlight upload succeeded on 5 November at 16:20 EST. Apple reported that the uploaded package is processing; processing completion and tester availability are not yet verified. Release tag `ios/v0.1.0-309.21.15` identifies `7a2955c`. Final artifacts and upload evidence are retained in `build/release/0.1.0-309.21.15/`.

## Feed header refinement — 5 November 2026

Follow-up to the TestFlight screenshot: Activities uses the native inline-large title so the title and trailing controls share a row. Filter precedes the neutral profile button; search sits separately beside the bottom tabs. Background work is grouped, with inline, Dynamic-Type-scaled spinners and expandable Health/sync controls. Status/error text stays visible.

Feed rows now use full-width 2:1 featured thumbnails with actual date/time badges, square compact thumbnails, larger week summaries, and a separate trailing metric column. Metadata no longer sits below the entire metric block. Activity rows retain navigation through explicit selection without a disclosure chevron consuming map width. Record/route badges sit with the corresponding text, and accessibility sizes stack the metric below that text. The Activities tab uses the cycling symbol from the board.

Verification: production views in the disposable IntegrationValidation harness, iPhone 17 / iOS 27.2, light, dark, and accessibility-medium text. The focused XCTest run passed header alignment and control order at standard sizes, filter/date-sheet access, Settings open/dismiss, and featured activity detail/back navigation in all three variants. Result: `/tmp/sweatkit-feed-parity/verified.xcresult`. Fresh captures: `Evidence/FEED-HEADER/{light,dark,large}.png`. Build and diff whitespace checks passed. Two earlier test runs were superseded after correcting menu dismissal and selecting a visible activity at large text sizes.

Remaining reference differences: native tab-bar dimensions/materials are retained. The app shows actual provider status rather than inventing the board's combined relative sync timestamp. Fixture dates, source badges, terrain, metrics and records differ from illustrative board content. This pass covers Activities, not a new acceptance pass for every screen or physical-device sync behavior.

### Bottom search follow-up

The search button now sits separately to the right of the three tabs, with no search field or button in the Activities header. iOS 27 uses the explicit prominent tab role; iOS 26 retains the search role. Search owns its search field, and both activity surfaces share query/sport/date/setting filters. Tab changes dismiss active search. The existing native Close control exits text entry before switching tabs.

Focused `testBottomSearch` passed in light, dark, and accessibility-medium on iPhone 17 / iOS 27.2: bottom control exists, header search is absent, typing produces no-match results, clearing restores activities, and Close → Activities restores the header controls. Result: `/tmp/sweatkit-feed-parity/search-verified.xcresult`. The test is retained in `Scripts/IntegrationValidation/UITests.swift`. `Evidence/FEED-HEADER/{light,dark,large}.png` now contains the passing bottom-search layout. iOS 26 fallback compiles but was not exercised on its runtime in this follow-up.

### Flyover alignment follow-up — 5 November 2026

Stat values and units now share the label's leading edge; the invisible width reservation covers the complete value/unit group so shorter values no longer indent independently. Primary figures use the board's larger hierarchy. Secondary gaps are tighter so all five cycling stats fit at standard text size on iPhone 17. Large text retains a bounded, scrollable stats viewport to keep navigation inside the safe area.

Playback speed and camera controls use neutral pills. The bottom-panel refinement below supersedes the initial clock and Analysis arrangement. Route comparison context moves from the top stats panel to the lower panel when available. Back uses a plain neutral style.

Verified with a disposable production-view integration harness on a Simlock-leased iPhone 17 / iOS 27.2. Light, dark, and accessibility-medium checks passed Play/Back reachability and opening Analysis; final screenshots were visually inspected. Result: `/tmp/sweatkit-flyover-alignment/final.xcresult`. Captures: `Evidence/FLYOVER-ALIGNMENT/{light,dark,large}.png`. Build, whitespace check, and mechanical layout scan passed.

The actual terrain, measurements and native controls remain different from the illustrative board. At large text sizes stats scroll within the upper panel. No release or physical-device validation was performed.

### Bottom panel refinement — 5 November 2026

The series selector now owns its colour ramp and the route-colour picker. When route and chart metrics differ, the route label/ramp appears inside the same selector. The standalone legend row is removed. Playback displays elapsed / total on one baseline, omits zero hours, and uses a simple speed pill without redundant menu arrows. At larger text sizes the clock moves above the controls if the full row cannot fit. The separate Analysis row is removed: tapping or swiping up on the grabber opens analysis, with the existing Activity options menu action retained.

Final production-view harness checks passed in light, dark and accessibility-medium on iPhone 17 / iOS 27.2. Checks include scrubbing to 95% of the route, Play/Back reachability, and opening Analysis through the grabber. Captures at 1:20:46 / 1:26:20 were visually inspected; the large-text clock reflows without truncation. Updated captures remain in `Evidence/FLYOVER-ALIGNMENT`. Result: `/tmp/sweatkit-flyover-alignment/bottom-final.xcresult`; build, whitespace and mechanical layout checks passed. Not released.
