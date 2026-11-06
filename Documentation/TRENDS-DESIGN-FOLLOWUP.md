# Trends acceptance follow-up

## Agreed direction

Human-led Impeccable session for TestFlight 0.1.0 (310.22.2). The user selected:

- Tap a Volume bar to retain its period, show dates/totals and a separate View activities action. Horizontal dragging browses history.
- Select power directly on the graph, retain selection after lift, replace the duration menu with a duration readout and clear control. Show both windows together, each with its own source activity link.
- Refine activity-list hierarchy and period details while preserving values, power ranking and navigation.

This is an Operate surface in the existing native, neutral SweatKit design. No palette, app navigation, metric formulas or unrelated screens are redesigned.

## Baseline and ownership

Branch: `codex/acceptance-trends-design`, created from `fd7bd09`.
The accepted Trends implementation was not in this commit: it was found in the uncommitted acceptance worktree at `/Users/arjunakankipati/.codex/worktrees/3bb8/sweatkit`. Its TrendsView, TrendsPresentation and TrendsTests changes were carried into this branch before refinement. These preserve named period details, contributions, comparison-window independence, source navigation and descending-power ranking. Integration must reconcile those same baseline changes rather than apply both copies blindly. Other acceptance worktree files are untouched.

## Implementation

- Volume uses a tap overlay alongside native horizontal chart scrolling. The selected period updates comparison totals and an explicit preview below the chart. Previous/Next buttons offer a route to empty/incomplete periods without precise chart gestures. Clear restores the current-period overview.
- Returning from details retains inspection; filter or library revision changes reset it. Source links have full-row hit targets.
- Power keeps a persistent selection separate from Charts' transient clearing on finger-up. A tap also selects directly. Supported durations snap in logarithmic space, retaining the existing duration contract. Clear removes source readouts; VoiceOver can adjust the duration without the removed picker.
- Recent power candidates are retained with the exact same six-week boundary, hidden/stale/future exclusions and filtered history as their plotted curve. Each readout resolves its own best source, including unavailable windows. Persistent presentation cache schema advances to 3.
- Activity rows emphasize selected watts or period contribution, use quieter metadata and omit duplicate distance in distance-period detail.

## Verification

- Host: **18 TrendsTests passed**, including exact six-week source membership, comparison-window independence, cache invalidation and missing/stale semantics. Command: `swift test --package-path Packages/SweatKitLibrary --filter TrendsTests`.
- iPhone 17 / iOS 27.2, leased through Simlock: **light and dark journeys passed** in `/tmp/trends-design-final.xcresult`; **maximum Dynamic Type power journey passed** in `/tmp/trends-design-large-final.xcresult`. The former bundle also contains the superseded large-text visibility assertion failure; the separate final rerun passed after scrolling the readout into view. These are simulator checks, not TestFlight acceptance.
- Exercised Volume tap/preview/period detail, power tap and drag followed by lift, recent source activity and back with retained selection, ranked list and back, clear, and maximum-text chart selection/list navigation. The test harness enters the production TrendsView in a NavigationStack; the wider app shell and other tabs are not this test's scope.
- Visual review: settled light/dark screenshots of the preview, period detail, power inspection/list and cleared state; maximum-text power chart/readout/list. Files are in `Evidence/TRENDS-DESIGN/`. At maximum text size the content scrolls vertically; window labels and values stack, chart axes use fewer labels, and the estimate moves below the chart.
- UI checks exposed and fixed full-row source hit testing and selection being reset on detail return. An early test used the wrong Back selector for ActivityDetailView; corrected to its existing explicit Back control.
- `git diff --check` passed. Impeccable's mechanical detector returned no findings; this is not an accessibility certification.

`Scripts/TrendsValidation/prepare.py` creates a disposable harness from unchanged committed outdoor ride, Zwift ride and walk FIT files. It does not fabricate activities, shift dates, inject a personal threshold profile, or ship fixture behavior in the app. The UI assertions are date-sensitive: the original October 2026 recording is in the recent window on this acceptance date (6 November 2026). The large-text tap coordinate is calibrated to the captured iPhone 17 plot; test positioning must be adapted for other devices.

## Remaining acceptance

These changes require review of the rendered first pass with the user. Simulator/host checks do not close TestFlight acceptance. Physical-device checks remain: one-handed tap/scrub/lift/source interaction, chart scrolling without accidental selection, VoiceOver duration adjustment and clear, larger real-history ranges, source/back navigation, Dynamic Type and real-library performance. No release, upload or merge is authorized by this subtask.

## Files and integration

- `App/TrendsView.swift`: selection, source links, preview and list presentation, accessibility-size chart layout.
- `Packages/SweatKitLibrary/Sources/SweatKitLibrary/TrendsPresentation.swift`: comparison/recent source candidates and cache schema.
- `Packages/SweatKitLibrary/Tests/SweatKitLibraryTests/TrendsTests.swift`: window/source regressions.
- `Scripts/TrendsValidation/{prepare.py,Harness.swift,UITests.swift}`: reproducible disposable harness and focused journeys.
- This handoff and `Documentation/Evidence/TRENDS-DESIGN/`: review evidence.

No Model/Store schema or metric formula changed. No merge, push, release or upload. Open product input: user review of this first rendered pass; the two interaction choices are already confirmed.
