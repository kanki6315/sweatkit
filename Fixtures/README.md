# Fixtures

Real files that every package tests against. Tests reach them through `Fixtures` in `SweatKitTestSupport`, which finds this directory by walking up from the test file.

These are real recordings and hold real GPS tracks. Keep that in mind before pushing this repository anywhere.

## FIT files

Each file has one session, and every record has a timestamp and heart rate.

| File | What it is | Garmin activity | Records | Elapsed | Timer | Distance | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `fit/outdoor-ride.fit` | Outdoor road ride, Garmin bike computer | 24172582403 | 5,347 | 5,755.7 s | 5,335.7 s | 37.53 km | Power on 5,337 records, so 10 are without. 326 events and 8 laps: many pauses. |
| `fit/zwift-ride.fit` | Zwift ride, sub-sport virtual activity | 24906063494 | 2,409 | 2,408.0 s | 2,409.0 s | 18.74 km | Made-up GPS on every record. Stated timer time is 1 s longer than elapsed. |
| `fit/walk.fit` | Outdoor walk in the open | 24830689204 | 2,492 | 2,492.7 s | 2,490.3 s | 3.27 km | No power. 4 laps. |
| `fit/walk-pitlane.fit` | Walk along a pit lane, beside buildings | 24596962303 | 27,039 | 36,141.7 s | 27,034.1 s | 17.91 km | The stand-in for GPS drift under cover. 131 records have no position. About 2.5 hours paused. |

`SweatKitIngest`'s `FixtureDecodeTests` pins the counts above.

## Not covered yet

The spec's metric acceptance list also needs unmatched pause events, sparse power, an activity of exactly 30 seconds, a recording that ends on a stop, an activity with no stream and an indoor ride without speed. None of these four files is one of those, so those cases need synthetic streams or more recordings. There is also no 5-hour ride for the detail screen's 1-second target.

## Adding a fixture

1. Copy the file into `fit/` with a short lowercase name.
2. Add a case to `Fixtures.FIT` in `Packages/SweatKitModel/Sources/SweatKitTestSupport/Fixtures.swift`.
3. Add its row here and its counts to `FixtureDecodeTests`.
