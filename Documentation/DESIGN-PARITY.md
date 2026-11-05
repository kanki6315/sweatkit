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
