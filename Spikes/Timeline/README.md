# Timeline spike harness

Throwaway app for trying the two custom components of the detail screen: `ActivityTimeline` and `StatsPanel` from `Packages/SweatKitTimeline`. It shows them over the real flyover map or a drawn backdrop, driven by the four shared FIT fixtures, with a frame-rate readout. Nothing here moves into the app.

**The zone colours are placeholders.** `DESIGN.md` leaves the effort palette "to be resolved during implementation", and it is not chosen yet. `PlaceholderPalette` in `Harness/ActivityLoader.swift` exists only so the harness has bands to draw. The package itself holds no colours for data: it draws the ones it is given.

## Run it on the iPhone

```sh
cd Spikes/Timeline
xcodegen generate
open TimelineSpike.xcodeproj
```

In Xcode, pick the iPhone as the run destination and press Run. The scheme builds Release, so frame rates are representative. Signing uses team `TDBAHN96B3` and bundle ID `com.arjunakankipati.sweatkit.timelinespike`.

`TimelineSpike.xcodeproj` is generated and ignored by git. Run `xcodegen generate` again after changing `project.yml`.

## What it does

- Decodes a fixture with `SweatKitIngest`, builds its 1 Hz stream, and turns that into the timeline's input: elevation, filled cumulative distance, stops and lap boundaries.
- Detects stops crudely: any stretch of 10 s or more that is paused or below the moving-speed floor from `SweatKitAnalysis`. Real stop detection belongs elsewhere.
- Builds the overlay from the stream. Power is banded by seven zones on 10 s smoothed power with an assumed 250 W threshold, heart rate by five zones with an assumed 165 bpm threshold, and speed or pace by five bands relative to the activity's own range. Cadence has no bands and is drawn in the neutral colour.
- Works out the stats at the cursor from the stream, with 3-second power as the mean of the last three seconds that have power.
- Works out a selected range's stats by running `SweatKitAnalysis` on the slice of the stream the range covers.
- Draws the route on `FlyoverMap` in the overlay's bands, from the same scrub binding as the timeline. The route gets no cleanup. The Zwift ride and the repeated ride have no usable route and use a drawn backdrop.

## Files

| File | Samples | What it is for |
| --- | --- | --- |
| Outdoor ride | 5,756 | Power, eight laps, eight stops |
| Zwift ride | 2,408 | No stops, no route |
| Walk | 2,493 | Pace in place of speed, no power |
| Pit-lane walk | 36,142 | Ten hours with 213 stops and long gaps. Twice the spec's 5-hour ride. |
| Ride repeated to 5 h | 18,000 | The outdoor ride end to end until it is 5 hours long, because the fixtures hold no 5-hour ride. This is the size the spec's frame-rate target names. |

## Controls

| Control | What it does |
| --- | --- |
| Options › File | Picks the activity |
| Options › Overlay | None, power, heart rate, speed or pace, cadence |
| Options › Axis | Distance or time |
| Options › Collapse stops | Closes up the detected stops |
| Options › Units | Metric or imperial |
| Options › Background | The map, or drawn bright, dark or mixed ground |
| Options › Show panels | Hides both components, to compare the map's frame rate without them |
| Sweep | Scrubs start to end in 20 s at a steady rate, measuring throughout |
| Measure | Starts and stops measuring by hand, for scrubbing, pinching and panning with a finger |

On the timeline itself: drag to scrub, pinch to zoom, move two fingers together to pan, hold a drag at either edge of a zoomed timeline to pan, and press and hold then drag to select a range. Press and hold without dragging, or the cross, clears the selection.

## The readout

The second line shows frame rates: now, worst over any quarter second while measuring, the longest single frame, and the count of frames over 25 ms. It comes from a `CADisplayLink` on the main thread asking for 120 Hz, copied from the flyover harness, so it catches main-thread stalls but can miss a slow map render. Turn on Settings › Developer › Graphics HUD as well.

The third line counts how often the timeline's chart has been drawn. Scrubbing moves only the cursor, so the count should stand still during a scrub and rise during a zoom or pan.

## Launch arguments

For repeatable screenshots, each option can be set at launch:

```sh
xcrun simctl launch booted com.arjunakankipati.sweatkit.timelinespike \
  -file walk -overlay heartRate -axis time -collapse YES -units imperial \
  -backdrop snow -scrub 0.35 -select 0.2,0.6
```

`-file` takes `outdoor-ride`, `zwift-ride`, `walk`, `walk-pitlane` or `five-hours`. `-overlay` takes `none`, `power`, `heartRate`, `speed` or `cadence`. `-backdrop` takes `map`, `snow`, `forest` or `mixed`. `-scrub` and `-select` are shares of the activity from 0 to 1.

## Seen in the simulator

Run on the iPhone 18 Pro Max simulator, iOS 27.2, on 2026-11-05. Simulator frame rates say nothing about the device, so the numbers here are only a sanity check.

- Light and dark, over drawn bright ground, drawn dark ground and real satellite imagery: numerals, labels, units and axis labels are readable in all of them.
- The largest Dynamic Type size: the stats panel reflows to one column and scrolls, and a range's stats become one row that scrolls sideways. At the largest standard size the panel is three columns.
- Reduce Transparency: both panels become opaque, white in light and black in dark. Increase Contrast: labels and lines darken and the panels gain a border.
- Scrubbing, press-and-hold selection, pinch zoom, two-finger pan and edge pan all work with simulated touches.
- A sweep of the repeated 5-hour ride left the chart-redraw count unchanged. Zoomed in, where the chart follows the cursor and redraws every frame, the sweep still held about 60 fps.

Not seen anywhere yet: VoiceOver, haptics, Reduce Motion, and anything on a device.

## Device checklist

Run these on the iPhone 18 Pro Max from the Release build. Write down the readout's worst rate, longest frame and hitches for each numbered measurement, and the Graphics HUD reading beside it.

**Frame rate.** The spec's target is 60 frames per second while scrubbing a 5-hour ride, once imagery has loaded.

1. File "Ride repeated to 5 h", background "Mixed ground". Tap Sweep. Passes at worst 60 fps or better with 0 hitches, and with "chart redraws" the same before and after.
2. The same file. Tap Measure, scrub back and forth by hand for 20 seconds, tap Stop. Same pass mark.
3. The same file. Pinch in until about 10 km shows, then tap Sweep. The chart now follows the cursor and redraws every frame, so "chart redraws" climbs. Same pass mark.
4. The same file. Tap Measure, then pinch in and out and pan with two fingers for 20 seconds. Same pass mark.
5. File "Pit-lane walk (10 h)", axis "Time". Repeat 1 and 3. This is twice the target size, so a miss here is a note, not a failure.
6. File "Outdoor ride", background "Map". Wait for imagery, then repeat 1 and 2. This is the real case: the map, the marker, the timeline and the stats all move from one binding. Compare with "Show panels" off to see what the two components cost on top of the map.
7. Switch overlay, axis and "Collapse stops" during a scrub. None should stall the scrub.

**Touch.**

8. Scrub across a lap tick slowly, in both directions. One haptic tap as the cursor reaches the tick, and none as it moves on.
9. Press and hold, then drag. A haptic marks the start of the selection, the band follows the finger, and the five range stats appear above the chart. The cross clears it, and so does a press and hold without a drag.
10. Zoomed in, hold a drag near either edge. The timeline pans and the cursor stays under the finger. Does the speed feel right?
11. Start a pinch with one finger already down. The cursor should return to where it was before that finger landed.
12. Does one-finger scrubbing ever fight the detail screen's own gestures? The harness has no sheet under the timeline, so this is only a first impression.

**Look.**

13. Over real satellite imagery in light and dark, look for ground where the labels or the axis text get hard to read. The glass carries a neutral tint to help in Dark Mode over bright ground. Is it too heavy?
14. Does the overlay line read clearly against the elevation fill, especially the unbanded cadence line?
15. Are the stat numerals large enough at arm's length? They are `title3` in heavy weight so that eight fit in two rows of four.

**Accessibility.**

16. The largest Dynamic Type size: nothing is cut short, the stats panel scrolls, and a range's stats scroll sideways.
17. Reduce Transparency and Increase Contrast, in light and dark.
18. Reduce Motion: the range stats appear without animation.
19. VoiceOver on the timeline: it reads "Timeline" and the cursor's distance and time. Swiping up and down moves the cursor. The actions rotor offers "Start selection here", "End selection here" and "Clear selection". The zoom gesture zooms. The Audio Graph rotor describes the chart and plays the elevation and overlay.
20. VoiceOver on the stats panel: each stat reads its name and its value with the unit in words, and a missing value reads "No data".
