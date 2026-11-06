# Playback and camera follow-up — TestFlight 0.1.0 (310.22.2)

Branch: `codex/acceptance-playback-camera`. This is a code follow-up, not acceptance of an uploaded build. No release, upload or merge is part of this work.

## Behavior

- Overview **1×** traverses the full elapsed sample grid in approximately 30 wall-clock seconds. **0.5×** takes about 60 seconds; **0.25×** about 120 seconds. **Recorded time** advances one recorded second per wall-clock second. The speed menu explains the overview baseline.
- The clock and stats remain activity elapsed time. Recorded pauses and missing sensor spans keep their place. Timer duration, moving duration, distance-axis selection and collapsed stops do not change playback speed. The last available sample is the endpoint, rather than an invented sample at the metadata end time.
- Pause stops advancement; scrubbing pauses and preserves the chosen position; Play at the end restarts at zero. Backgrounding and leaving detail pause. Dropped frames retain elapsed wall time so long recordings still finish on schedule. Empty/single-sample playback is disabled. Indoor/missing-route playback still drives charts.
- Pan, pinch, rotation and tilt suspend automatic camera updates while playback continues. **Resume follow** restores the default chase camera at the current marker. Manual mode also keeps the marker moving and survives scrubbing. Reduce Motion converts follow to overview, while leaving manual camera control available.
- A new activity reload resets cursor, selection, stats, camera and playback. Cached maps reapply the requested camera on presentation. Cancellation guards stop a previous activity's load from publishing into the next activity.

## Changed areas

- `App/ActivityDetailView.swift`: timing integration, speed/camera controls, replay and activity reset.
- `Packages/SweatKitFlyover`: elapsed-grid timing, manual camera mode and gesture observation, focused unit tests.
- `Scripts/PlaybackValidation`: disposable harness using three unchanged real FIT files; no synthetic activity/profile values.
- Camera/playback clauses in the MVP spec updated to the agreed behavior.

Activities map loading/scrolling, Search, Routes, Trends, metric calculations, Golf, iCloud and Model contracts are outside this change. `FlyoverMap.swift` is also involved in map loading work, so integrate its camera-only hunks carefully with the owner of that work.

## Evidence

Package checks: SweatKitFlyover 30 tests and SweatKitDetail 76 tests passed. These include mathematical timing boundaries and existing preparation/cursor regression tests; they do not establish physical-device acceptance.

Production simulator build: passed, including the final cancellation and camera changes (`/tmp/sweatkit-playback-build-final.log`).

On a Simlock-leased iPhone 18 Pro / iOS 27.2, the playback UI flow passed: real ride completion within the 36-second UI-check tolerance for the ~30-second default, replay, pause, analysis scrubbing, opening the walk at 0:00, and indoor completion. Result: `/tmp/sweatkit-playback-ui-rerun.xcresult`; exported screenshots: `/tmp/sweatkit-playback-evidence`. The initial camera check explicitly skipped because MapKit remained on its fallback. The rendered ride controls, walk reset and indoor finish screenshots were visually inspected. Camera retries using satellite, standard map, and active playback all stayed on the fallback and explicitly skipped; final result: `/tmp/sweatkit-playback-camera-playing.xcresult`. That bundle reports zero failures but one skipped test: it is **not** evidence that camera gestures passed. The callback/manual-mode code compiles, and the pure Reduce Motion/manual-mode test passes; pan/pinch/rotation/tilt, resume and manual-camera scrubbing still require rendered-map verification. Map loading behavior was not changed.

## Remaining physical-device acceptance

On the user's library, check a short activity, a long activity, an activity with pauses, and an indoor/missing-route activity. Confirm ~30-second overview completion, both slower speeds, pause/replay, scrub-to-resume, and selecting another activity at its correct route, stats and time zero. Check pinch, rotation and two-finger tilt during playback, camera persistence while scrubbing, Resume follow, Reduce Motion, large Dynamic Type, and frame pacing. Check light/dark overlays over bright and dark imagery.

The fixture catalog has no exactly 30-second recording, no-stream recording or five-hour ride. Request real recordings if those cases need data-level acceptance; do not substitute fabricated data. No unresolved product decision is required for this branch; speed labels reflect the user's follow-up preference. Physical-device/TestFlight acceptance remains open.
