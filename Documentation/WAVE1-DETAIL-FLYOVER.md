# Wave 1 — Detail, flyover and timeline

Implementation on `codex/wave1-detail-flyover`, based on `0c77d0a`. Approved boards 02–04 and the existing `26d9e12` camera fix were inspected. The boards were not edited. No Model/Store schema, Health adapter, timing calculation, LibraryModel, theme, root navigation or project spec changes are included.

## Implemented

- Outdoor map extends behind the safe areas. The activity title, date/sport, back/options controls and cursor stats share one floating panel. Primary stats and supporting values have separate hierarchy. Numeric slots accommodate ten-hour durations and extreme pace values. At accessibility text sizes the stats scroll within a bounded panel and analysis opens at the large detent.
- Playback, axis/series choices, overlay legend and timeline share one bottom panel. A drag on its handle opens analysis; the labelled Analysis button is the accessible alternative. Analysis hides both underlying floating panels and embeds a flat timeline, preserving the shared cursor and range selection. Controls inherit tint and semantic system colors.
- Indoor/virtual/no-route activities open on recorded charts with cursor stats, colored power samples, the same timeline and access to deeper analysis. No synthetic GPS is displayed.
- Analysis starts with a responsive summary, then zones, individual power curve, recorded laps, eligible best distances, and full charts. Weighted power, average power, intensity, variability, work/recorded work, load source and missing eligibility reasons come from the existing Analysis API. Power-coverage notes remain explicit. The single-activity power curve is prepared off the main thread with the other presentation data. Historical curves and route ranks are deliberately absent because those features do not exist yet.
- Running stride length, ground-contact time and vertical oscillation remain present when recorded. All charts share one cursor; original gaps remain separate series.
- On-foot pace charts default to a disclosed 30 min/km ceiling (48.28 min/mi, the identical speed boundary). Slower recorded points are marked by triangles at the limit. A Full pace range switch restores the entire recorded range, and cursor values always use the unmodified source sample. Zero speed is undefined pace; missing samples remain gaps. This is display clipping, not a new moving-time rule, deletion, interpolation or smoothing of recorded data. The small timeline still uses its existing relative speed series and is not subjected to reciprocal near-zero pace inflation.
- Native edge-back uses the navigation controller’s own recognizer, scoped to this detail screen. Its delegate gives the edge gesture priority over MapKit panning and restores the original delegate/enabled state when the screen disappears. A control test failed without this integration and passed with it; a gesture starting at the actual screen edge is used consistently.
- The timeline cursor is neutral white with a dark edge per DESIGN.md. Package presentation APIs add optional `floating` parameters (default true) and expose the existing `FloatingPanel` modifier so the app can compose a single pane. No competing theme system was introduced.

## Verification

All verification here is **simulator or Mac**, not a live phone acceptance pass.

- Final scoped package suite: Detail **74**, Timeline **116**, Flyover **27** tests passed. `/tmp/wave1-scoped-final-tests.log`.
- New tests cover an 800 min/km recorded value without mutation, missing/zero speed, metric/imperial scale boundaries, power-curve eligibility and five-hour preparation/display bounds.
- Five-hour synthetic detail plus full analysis preparation: **0.130 s** on this Mac. Existing long FIT preparation: **0.200 s**; range calculation **0.140 s**; 362 cursor reads **0.00045 s**. These are informational timings under concurrent build/test load, not the reference-phone one-second/60 fps gates.
- Final production simulator build passed with Xcode 27.2 (`/tmp/wave1-detail-production-final.log`). The temporary fixture harness builds the actual app views and local packages, replacing only its app entry point with a fixture picker. Its copies are under `/tmp/detail-harness`; it does not alter production launch behavior.
- Simulator: **iPhone 18 Pro Max, iOS 27.2**, leased through Simlock, device `C43E0A03-1B1D-49F4-8BC8-D30D67F14772`.
- Real fixtures: `outdoor-ride.fit`, `zwift-ride.fit`, `walk.fit`, `walk-pitlane.fit`. The UI flow opens each, drags the timeline, starts/pauses playback, presents analysis, drags the sheet upward and dismisses it. Native edge-swipe back and reopening are checked separately.
- Synthetic running fixture explicitly contains an 800 min/km near-stop and a missing sample, plus stride/contact/oscillation channels. Full-range testing asserts the toggle is on and captures the restored 800 min/km axis, rather than treating a tap as proof. These synthetic values never enter production data.
- Accessibility-size M captures verify reflow and reachable Analysis/Done controls. The stats panel intentionally scrolls at that size. VoiceOver audio descriptions, Reduce Motion/Transparency, increased contrast and physical touch behavior still need the phone checks below.
- Camera pacing and idle retention from `26d9e12` were left unchanged. Camera regression tests pass; opening, scrubbing and reopening real map fixtures work in the simulator. No physical camera smoothness or frame-rate claim is made.

Initial UI attempts exposed a native edge-back regression; their failed bundles are not passing acceptance evidence. The final gesture control is `/tmp/wave1-detail-edge-control.xcresult`. The no-integration control `/tmp/wave1-detail-native-edge.xcresult` fails. A stock system-navigation control `/tmp/wave1-detail-stock-gesture.xcresult` passes. The final complete theme suites and selected captures are listed below.

The Impeccable mechanical scan returned no findings (`/tmp/wave1-detail-design-scan.json`); visual and behavioral evidence is listed independently. Impeccable also reported legacy PRODUCT.md metadata. Its `init` workflow can refresh that separately; no product/design-context migration was mixed into this task.

## Final result bundles and captures

- **Five UI tests passed in light and dark**: `/tmp/wave1-detail-accepted-light.xcresult`, `/tmp/wave1-detail-accepted-dark.xcresult`; logs use the same names with `.log`. These cover detail flows, native edge-back/reopen, large text, running/pace charts, and stock-navigation restoration. Map pans do not navigate away from detail.
- Summary alignment was then refreshed with `testSummaryCapture` in `/tmp/wave1-detail-summary-light.xcresult` and `/tmp/wave1-detail-summary-dark.xcresult`. The final display-only cursor clock floors fractional seconds to match the stats panel's grid second.
- The harness's two app-view copies were compared with the final repository sources. Packages are referenced directly. No debug navigation instrumentation is present in production files.
- Selected screenshots below are downscaled to 660 px wide for review; native-resolution originals remain in the result bundles. Outdoor captures are from the verified reopen flow, after the route has rendered. The full bundles also include initial opening, pan/scrub and sheet captures.

| Surface | Light | Dark |
| --- | --- | --- |
| Outdoor detail | [Capture](Evidence/DetailFlyover/outdoor-light.png) | [Capture](Evidence/DetailFlyover/outdoor-dark.png) |
| Analysis | [Capture](Evidence/DetailFlyover/analysis-light.png) | [Capture](Evidence/DetailFlyover/analysis-dark.png) |
| Indoor detail | [Capture](Evidence/DetailFlyover/indoor-light.png) | [Capture](Evidence/DetailFlyover/indoor-dark.png) |
| Pace scale | [Limited](Evidence/DetailFlyover/pace-limited-light.png), [full 800 min/km range](Evidence/DetailFlyover/pace-full-light.png) | Full bundle |
| Running form | Full bundle | [Capture](Evidence/DetailFlyover/running-form-dark.png) |
| Accessibility-size analysis | [Capture](Evidence/DetailFlyover/large-text-analysis-light.png) | Full bundle |

## Board comparison and limits

The implemented composition follows boards 02–04: full-screen outdoor terrain, one header/stats pane, one bottom control pane, a deeper flat analysis sheet, and indoor charts with the same cursor. Light/dark screenshots were visually inspected against the tracked boards. Actual route geography, metrics, chart shapes, durations and missing threshold labels differ from the illustrative boards by design. Real unavailable values are shown explicitly. The summary reflows by text size rather than forcing three columns. Standard sheet navigation and controls retain native behavior.

This does **not** certify pixel-for-pixel parity or all accessibility/device acceptance. Physical camera feel, private Health recordings and smaller-screen large-text behavior remain open. There are no fabricated route-history rows, all-time records or 90-day comparison curves.

## Integration needs

No cross-boundary API/schema changes are required. Task 2's inherited tint/theme should flow into the controls. Integrate its RootView/feed changes with these detail files and rerun the actual feed → detail → analysis → back path; the fixture harness verifies the detail views independently of that wiring. Task 1's corrected Health distances/timing should flow through the existing DetailInput without adaptation.

## Exact phone retest checklist

1. Install the integrated build; open the 5 November 2026 09:32–09:56 Charlotte Apple Watch walk/run. Refresh Health access/snapshots using task 1's flow if required. Compare recorded totals to Fitness, separately from cursor values; do not compare a single cursor pace with workout average pace.
2. In light and dark, scrub through ordinary motion, the extreme near-stop, a known pause and a missing sample. Confirm the default pace scale is readable, the limit explanation/triangles are visible, Full pace range exposes the original extreme, and cursor values are unchanged. Repeat in imperial units.
3. Scrub and select ranges with distance/time axes and collapsed stops. Verify marker, camera, distance, time, pace, HR, cadence, elevation and gradient stay on the same second. Missing values must remain missing. Check running-form units m/ft, ms and cm/in and gaps against readable Health samples.
4. Open a short urban route, a long route and a tree-covered walk. Test overview/follow, pan/zoom/orbit, playback at 0.5×/1×/2×/4×, fast reverse scrubs, exit/reopen and foreground/background. Judge the existing camera easing on hardware; measure warm cached five-hour load and scrubbing FPS after imagery loads. Do not close the earlier camera acceptance finding based on simulator screenshots.
5. Pull analysis from the handle and use its button; test medium/large detents, swipe dismissal, Done, lap selection, shared cursor, native edge-back and reopen. Confirm no stacked glass or duplicate top stats. Open Zwift and a genuinely route-less recording and repeat.
6. Set/miss thresholds and use a sparse recording: verify load/power eligibility labels, starter-zone disclosure, recorded-work label and power coverage. Ensure a missing value is never reported as zero and no historical comparisons appear.
7. Enable accessibility text sizes, VoiceOver, Reduce Motion, Reduce Transparency and Increase Contrast. Scroll all stats, adjust the timeline with VoiceOver, reach playback/options/Analysis/Done, check large numerals and bright/dark terrain contrast, and confirm Reduce Motion uses overview with a moving marker.
