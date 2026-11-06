# Routes acceptance follow-up

## Scope and recovered acceptance baseline

Worktree branch: `codex/acceptance-routes-cache-inspection`, based on `fd7bd09`.
The reported acceptance build is TestFlight 0.1.0 (310.22.2). Main and available
release tags lack Building history. Local acceptance harness project paths led
to uncommitted changes in `/Users/arjunakankipati/.codex/worktrees/3bb8/sweatkit`.
Only RoutesView, RouteCatalog, its developing-group regression, and the matcher
boundary-noise implementation/version/test were recovered into this branch.
The original worktree was read only and remains untouched. Other owners must
retain its unrelated accepted fixes when integrating; this branch does not
replace their source baseline or certify the exact uploaded binary provenance.

Recovered behavior includes two-to-four-outing groups, per-outing optional
reviews, list metadata and the neighbouring-cell detection fallback (algorithm
4/cache format 4). These are prior acceptance work, not new Charlotte tuning.
No distance or alignment threshold was loosened by this follow-up.

## Cache change

`ActivityLibrary.routes` has an optional asynchronous `cachedResult` callback.
It publishes only a matching persisted catalog after checking current sources,
visible rows and decisions, before the per-effort metrics refresh. Existing
callers retain their final-result behavior. Cancellation and recursive retries
carry through the callback. The follow-up introduces no additional cache format, Store, Model or matching
threshold change beyond the recovered acceptance baseline.

Routes distinguishes not-yet-loaded from a valid empty catalog. Counts appear
only after a result is available; validated cached rows remain visible during
“Updating routes…”. Changing the history window clears the old window's data.
Outdated requests cannot replace a newer request's catalog or error.

This addresses a verified code path that delays cache presentation. It does not
prove why the reported TestFlight build misses/rebuilds its cache, nor establish
cold-start latency on the user's library. Cache validation still queries the
visible feed and current metadata before publishing; it does not show unchecked
on-disk data or bypass hidden/deleted activity checks.

## Building-history inspection

The user approved a native detail page. Building-history rows now navigate to a
reference map and dated outings with title, available recorded distance and
source attribution. Frequent-route pages also link to this inspector.

Selecting an outing shows its actual cleaned GPS path over the reference with
solid/dashed, explicitly labeled lines. A Compare with picker selects another
frequent or developing group to examine separation. On-demand Library inspection
uses the production cleaning and matcher path; it reports detection gates,
exact cell overlap, use of the boundary-noise fallback, alignment measures and
failed checks. Explicit include/exclude decisions are reported separately.
Pairwise passing results are not claimed to resolve multi-route ambiguity or
explain historical decisions. The inspector cannot silently merge groups.

Loading, no usable GPS/failed track load with retry, and unavailable groups have
explicit states. Two-to-four-outing groups remain below the five-outing frequent
threshold. Geometry is available without network map tiles. Comparison selection
cancels old presentation tasks and resets the map to fit both tracks.

## Minimum Charlotte evidence

The user recalls August but not the activity IDs. Recovered acceptance notes
identify August 13/17 and August 14/18 as earlier pairs, with longer rides having
an extension; the year and correspondence to the current three short groups
remain unverified. Use the detail page to identify the actual outings.

Start with four original recordings: one representative outing from each
35.6, 35.9 and 36.0 km group and one roughly 41 km extension. Supply the dates,
source/activity IDs, which displayed group each belongs to, and which pair had a
known construction detour (and approximately where, if known). Original FIT is
preferred: timestamps, pauses and recorded GPS are needed to reproduce the
production cleaning/alignment path. Distance summaries or map screenshots alone
cannot identify a failed gate. More outings are needed only if these four do not
reproduce the split, or to validate a proposed change across each group's history.

Existing tooling:

- `Spikes/GarminPull` supports `swift run GarminPull download ID` using the
  existing authorized Garmin Personal API setup in its README; it retains and
  inspects original payloads. Do not put API keys in chat or committed files.
- The production Garmin client already supports original downloads.
- The app has no general route/FIT export UI in this checkout. A Health-only
  outing needs its actual workout route sample export; a Garmin FIT from a
  different outing is not an equivalent fixture.
- `Fixtures/README.md` lists four originals. Only one is an outdoor cycling
  recording (37.53 km); there is no real repeated Charlotte detour set.
- `Scripts/RouteValidation` currently uses synthetic straight tracks and a
  parallel-track variant. The Library integration tests use date-shifted copies
  of the real outdoor FIT. These test presentation, persistence and specific
  geometry cases, not Charlotte acceptance.

Once recordings are available, decode through the production ingest and cleanup
pipeline, compare each pair in both reference directions, record detection gates
and all alignment measures, and plot the actual deviations. Reproduce current
failure first, then add real regression fixtures for the minor variations and
41 km negative control before considering a rule change. Preserve reverse,
parallel-road, extra-lap, missing-section and meaningful-extension cases.

The displayed 35.6–36.0 km range differs by about 1.1%, below both the 10%
detection length tolerance and 3% aligned timed-section ratio limit if those
values represented the actual cleaned/aligned distances. They do not necessarily
do so. This makes blind distance-threshold increases unjustified. A 35 versus
41 km extension differs by about 17%; retain the detection/full-course safeguards.

## Acceptance still required

- Integrate with the remaining recovered acceptance changes; this branch contains
  only the Routes slice.
- Cold reopen with the real library: cached rows/counts appear during refresh,
  without falsely showing zero; measure time to first data.
- Empty catalog, invalid/corrupt cache, all-history switch, import/revision,
  hide/delete/restore, profile changes and interrupted refresh.
- Building-history detail navigation, actual overlays/evidence, large text,
  VoiceOver, offline geometry and missing-route states on the real library.
- Charlotte pairwise evidence and real-fixture regression coverage; ~41 km stays
  separate. No matching fix is claimed yet.

No release, upload, main merge, Cloud transport change, or activity MapKit
scrolling change is part of this work.

## Review and integration map

Changed files:

- `App/RoutesView.swift`: recovered acceptance list/review UI, early cached
  presentation and request generation guards, navigation into inspection.
- `App/RouteInspectionView.swift`: group detail, dated outing selection,
  overlaid paths, reference-group picker and matching evidence.
- `Packages/SweatKitLibrary/Sources/SweatKitLibrary/RouteCatalog.swift`:
  recovered developing-group catalog; validated cache callback; metric refresh
  for both frequent and developing groups.
- `Packages/SweatKitLibrary/Sources/SweatKitLibrary/RouteInspection.swift`:
  on-demand production-track inspection API; inspection output is not persisted
  and route decisions are not written.
- `Packages/SweatKitLibrary/Tests/SweatKitLibraryTests/RouteCatalogTests.swift`:
  recovered developing-group regression plus cache/inspection regressions.
- `Packages/SweatKitRouteMatching/Sources/SweatKitRouteMatching/Detection.swift`,
  `RouteMatcher.swift`, `SweatKitRouteMatching.swift`, and
  `Tests/SweatKitRouteMatchingTests/BoundaryNoiseTests.swift`: copied unchanged
  from the earlier acceptance worktree. This is the pre-existing algorithm 4
  boundary-noise fallback and tests, not a newly tuned Charlotte fix.
- `Scripts/RouteValidation/Harness.swift`, `UITests.swift`: developing-group
  fixture and light/dark/large-text navigation checks; review navigation updated
  for the recovered per-outing review layout.
- This handoff document and rendered evidence captures.

Shared contracts: no SweatKitModel or Store edits. Library adds a Sendable
inspection result and an optional cache callback; existing routes callers remain
source compatible. The recovered optional `RouteCatalog.developingRoutes` field
and cache format 4 must be retained. LibraryModel, Trends, activity details,
Identity/Golf migration, and sync/Cloud files are deliberately outside this diff.
When combining the original acceptance changes, deduplicate these recovered
Routes/matcher hunks rather than overwriting either worktree wholesale.

Code verification: all 18 RouteCatalog tests and all 286 RouteMatching tests
passed in this worktree. The real-FIT regression uses shifted copies of one
recording; the extension diagnostic test deliberately changes a reference
signature. Neither substitutes for genuine Charlotte detour/extension fixtures.
Logs are `/tmp/sweatkit-routes-8e06-library.log` and
`/tmp/sweatkit-routes-8e06-matching.log` (ephemeral local evidence).

The review-navigation check also exposed a recovered UI issue: the intermediate
candidate page held a captured list after Keep separate. It now derives choices
from the current catalog and offers Review complete / Back to Routes after the
last choice is resolved. The regression checks that the optional review is gone
and the confirmed route remains. This is route review, not Identity duplicate
review; no duplicate policy or sync behavior changes.

Impeccable context reported the pre-existing deprecated Product Register and old
PRODUCT.md schema. Those files were not migrated; an optional explicit `init`
pass owns that maintenance.

## Simulator evidence

Final inspection run: **4 tests passed, 0 failures** on a Simlock-leased iPhone
18 Pro Max / iOS 27.2: light, dark, accessibility-M text, and the updated
Keep separate → Review complete → Routes flow. Bundle:
`/tmp/sweatkit-routes-8e06-ui-verified.xcresult`; log:
`/tmp/sweatkit-routes-8e06-ui-verified.log`.

The existing populated route → comparison/scrub/playback flow, empty state and
refresh error state each passed in the preceding run
(`/tmp/sweatkit-routes-8e06-ui-final.xcresult`). That earlier bundle also contains
an XCTest app-termination failure for the light inspection case and the stale
review assertion which exposed the candidate-page issue. Those failures were
rerun successfully in the final four-case bundle. An initial interrupted run
used swipes inside the interactive map; corrected tests scroll at the list margin.
Do not treat either earlier bundle as an entirely passing suite.

Rendered captures from the final passing run were visually inspected. These are
explicitly synthetic UI tracks, not the user's Charlotte recordings. They are
resized to 660 px wide; full-resolution originals remain in the result bundle.

| Surface | Light | Dark | Large text |
| --- | --- | --- | --- |
| Outing history | [Light](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/history-light.png) | [Dark](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/history-dark.png) | [Large text](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/history-large-text.png) |
| Overlaid paths | [Light](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/overlay-light.png) | [Dark](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/overlay-dark.png) | [Large text](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/overlay-large-text.png) |
| Matching evidence | [Light](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/evidence-light.png) | [Dark](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/evidence-dark.png) | [Large text](Captures/ACCEPTANCE-ROUTES-FOLLOWUP/evidence-large-text.png) |

Reproduce with `python3 Scripts/RouteValidation/prepare.py /tmp/<unique-harness>`
and XcodeGen, then follow Simlock instructions to lease a simulator before
running the RouteScreens tests. No production fixture injection, signed-device
acceptance, or TestFlight release was performed. Leases were released after use.
