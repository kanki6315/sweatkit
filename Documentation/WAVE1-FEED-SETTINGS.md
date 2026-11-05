# Wave 1 — feed, Settings and appearance

5 November 2026. Branch: `codex/feed-settings-wave1`. Implements the assigned portion of approved boards 01 and 09. No board, model/store contract, analysis, HealthConnection, detail/chart, project.yml or central acceptance-ledger changes.

## Delivered

- Newest visible activity gets a large preview; older entries use compact square snapshots. Week headings and recorded totals, sport/source attribution, date, headline, distance, moving time and ascent remain derived from the library. Headline power is explicitly **average**, not the board's illustrative weighted power.
- Coloured cached map routes and indoor/virtual sparklines use existing `ColourBanding` and `EffortPalette`. The map has a dark casing and neutral start marker. Sparklines preserve missing-data segments. Snapshot cache keys include source revision, profile, appearance and size. Profile saves refresh visible thumbnails. Compact maps are rendered square rather than cropping off parts of a wide route.
- Active filter indicator, readable filter summary, clear/reset actions, title search, sport/date/indoor/outdoor filters, pull-to-refresh, paging, FIT import and import outcomes remain. Import is in the feed action menu and Settings. Existing stale-result, import progress/cancellation, duplicate review, source status/pause and retry states remain.
- Settings groups Sources, Athlete profile, Sync and storage, and Display. Source screens preserve Garmin key setup/replacement, expiry notices, sync/reconciliation/pause and Health connect/review/refresh/pause. **Review Health access** remains reachable through Settings → Apple Health and directly in the enabled Health feed status, including the distance/steps/running-form permission upgrade.
- Profile, threshold history and editable power/HR zones retain validation and recalculation. Save is available inside each profile editor as well as the overview. Optional numeric fields retain visible labels after entry. Library review keeps hidden-activity restoration accessible; detail navigation keeps rename/hide access.
- `App/AppTheme.swift` owns the persistent `appearance.accent` preference and Electric Cyan, Neon Lime and Cobalt definitions. Light variants are deliberately darker for legibility; system semantic backgrounds and labels follow device appearance. Root applies tint to all tabs and presented navigation; Settings applies it locally for immediate preview. Effort colours never use the accent.
- Dynamic Type uses system styles. Metric rows reflow vertically; compact decorative thumbnails and Settings icons yield space at accessibility sizes. Native controls provide their standard accessibility and reduced-motion/material behavior.

## Verification and evidence

- XcodeGen generation succeeded without changing `project.yml`.
- Debug iOS Simulator builds succeeded, including the final production build with all temporary launch hooks removed. Build logs: `/tmp/sweatkit-feed-build.log`, `/tmp/sweatkit-feed-visual-build.log`, `/tmp/sweatkit-feed-final-build.log` (local and ephemeral).
- Existing `SweatKitDetail` tests: **71 passed**. Existing `SweatKitPalette` tests: **5 passed**. `/tmp/sweatkit-feed-tests.log`. These cover the reused colour rules; they do not prove UI interaction.
- `git diff --check` passed. Impeccable detector returned `[]`; this is not a SwiftUI accessibility certification.
- Simlock identity and instructions checked; exclusively leased **iPhone 17 / iOS 27.2**, device `DDDD5E4B-A8D0-49EA-B9BE-A9482502F45E`, lease `lse_91cfe3b6-a35a-4cd1-b954-c9f5397961ed`. No phone used.
- Imported the existing outdoor ride, Zwift ride and walk FIT fixtures through `LibraryModel.importFiles` in a temporary local launch harness. No fixture values, titles or dates were changed to imitate the boards. Fixtures occupy separate historical weeks, with the virtual ride newest.
- Temporary launch arguments selected Settings, the outdoor filter and a no-match title filter. Those hooks are removed from committed production source. This verifies state rendering and the real filter query, not tapping controls.
- Reviewed standard-size light/dark feed and Settings captures, outdoor-filter rendering, no-results recovery and maximum accessibility text-size captures. Final captures are under [Evidence/WAVE1-FEED-SETTINGS](Evidence/WAVE1-FEED-SETTINGS/).

| Capture | What it establishes |
| --- | --- |
| `feed-light.png`, `feed-dark.png` | Actual imported activity hierarchy, real week totals, coloured power sparkline, compact older map row, system appearance |
| `settings-light.png`, `settings-dark.png` | Native sheet, source/profile grouping, real disconnected/recovery messages, semantic surfaces |
| `feed-outdoor.png` | Active outdoor filter and real route thumbnail |
| `feed-empty.png` | Clean installation of final production build, real empty library and import entry point |
| `feed-no-results.png` | No-match title query, active-filter indicator and reset controls |
| `feed-accessibility.png`, `settings-accessibility.png` | Largest accessibility text size, wrapping and vertical growth; lower content requires scrolling |
| `comparison-light.jpg`, `comparison-dark.jpg` | Board 01 / app feed / board 09 / app Settings side by side, scaled to equal widths |

## Comparison and limits

The approved composition is implemented with native navigation and forms. System navigation/search consumes more top space than the drawn board. Real fixture dates create more week headers than its illustrative same-week dataset. Settings uses explicit profile/zone editor links instead of invented current threshold values. Long real recovery messages increase source-row heights. No records, route membership, threshold suggestion, cloud sync status or fabricated last-sync timestamp is displayed. No ZIP import is advertised: the retained importer supports FIT files.

Computer Use access to `com.apple.dt.Devices` was blocked by organization policy. Simlock install/launch, appearance, text-size controls and screenshots worked. **Tap/swipe navigation, profile persistence through UI, VoiceOver traversal, Reduce Transparency, Increase Contrast, live Garmin recovery and live Health permission upgrades are not certified by these captures.** The unsigned simulator reports a real Garmin Keychain-read recovery state; it is not evidence of a problem with the signed phone build. Existing phone acceptance is preserved in code, not re-certified here.

## Integration points

- Other screens inherit `AppTheme` tint through Root; use `.tint`/semantic foregrounds for controls and `EffortPalette` for data. Avoid separate accent preferences.
- Any future in-app profile editor should post `AppTheme.profileDidChange` after a successful save/recompute if the feed remains mounted, so previews refresh.
- Future record/route membership badges require real model fields; none are inferred from titles or distances. Future weighted-power headlines need an explicit metric kind/label. Source owners should supply trustworthy sync timestamps/status rather than having the view infer them. Cloud controls remain absent until implemented.
- No source or shared-schema change was required. Root changes are limited to tint preference and application.

## Exact phone retest checklist

1. Install the signed integration build over the existing phone library. Open Activities offline; compare count/history and open an older activity. Confirm cached previews remain available, then reconnect and pull to refresh.
2. Check light and dark appearance. Select each accent in Settings → Display, dismiss, switch tabs, relaunch and confirm persistence. Enable Increase Contrast and Reduce Transparency; verify labels and controls remain legible.
3. Test sport, indoor/outdoor, date-range and title filters separately and together. Check filled filter icon/summary, clear/reset, no-results recovery and week totals. Load older pages. Import a valid FIT twice and a corrupt file; inspect outcomes and cancellation.
4. Open newest and older activities. Rename and hide one through existing detail controls. Restore it through Settings → Sync and storage → Review duplicates and hidden activities. Confirm title, count and totals update.
5. Switch metric/imperial and Save profile. Confirm feed distances/ascent/pace and week totals update. Open threshold/zone editors; save valid values, reject non-increasing boundaries, reset automatic zones, and verify a visible thumbnail changes when zone boundaries change. Relaunch to verify persistence.
6. On a device with the prior Health schema, open Settings → Apple Health → Review Health access. Approve intended read categories, including distance, steps and running form. Refresh existing workouts; verify the upgrade notice clears and actual accessible samples populate without duplicates. Repeat with a denied category and confirm honest missing data and reachable recovery. Do not treat enabled/requested state as proof that read access was granted.
7. Exercise Garmin with the existing key, then an expired/invalid key in the intended test setup. Verify expiry/recovery text, replace-key flow, refresh and pause. Confirm no activity loss or duplicate revisions.
8. At maximum Dynamic Type, scroll the full feed and all Settings editors. Verify no clipped values, reachable Save/Done/back actions and readable field labels. Use VoiceOver to inspect activity titles, metrics, filters, source actions and zone boundaries.

Impeccable also reported legacy PRODUCT.md metadata. It was left unchanged within this screen-only scope; a separate `init` pass can migrate it.

No merge, push or TestFlight upload performed.
