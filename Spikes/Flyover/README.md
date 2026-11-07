# Flyover spike harness

Throwaway app for the two M0 flyover gates in the spec. It drives the real `SweatKitFlyover` package with crude routes built from the shared FIT fixtures, and shows a frame-rate readout. Nothing here moves into the app. Record what you see in [RESULTS.md](RESULTS.md).

## Run it on the iPhone

```sh
cd Spikes/Flyover
xcodegen generate
open FlyoverSpike.xcodeproj
```

In Xcode, pick the iPhone as the run destination and press Run. The scheme builds Release, so frame rates are representative. Signing uses team `TDBAHN96B3` and bundle ID `com.arjunakankipati.sweatkit.flyoverspike`. The first launch may need the developer certificate trusted under Settings › General › VPN & Device Management.

From the command line instead:

```sh
xcodebuild -project FlyoverSpike.xcodeproj -scheme FlyoverSpike \
  -destination 'platform=iOS,name=<your iPhone name>' -allowProvisioningUpdates build
```

`FlyoverSpike.xcodeproj` is generated and ignored by git. Run `xcodegen generate` again after changing `project.yml`.

## What it does

- Decodes `outdoor-ride.fit`, `walk.fit` and `walk-pitlane.fit` from `Fixtures/fit/` with Garmin's FIT SDK when a route is picked. `zwift-ride.fit` is left out because its GPS is made up.
- Colours the ride by seven power zones on 10 s smoothed power with an assumed 250 W threshold, and the walks by five bands of 10 s smoothed speed relative to the walk's own range. Records with no reading get a grey band.
- Simplifies with Douglas–Peucker at the tolerance on the slider, always keeping the first vertex of each band so band edges stay put. Because of that, the band count sets a floor on vertices: on the ride, 769 band runs mean about 800 vertices at any tolerance above 10 m.
- Does no other cleanup, so the tangles where the recorder sat still are drawn as recorded.

## Controls

| Control | What it does |
| --- | --- |
| Slider | Scrubs. Measuring runs while your finger is on it. |
| Sweep | Scrubs start to end in 60 s or 15 s at a steady rate, measuring throughout. Repeatable, unlike a hand drag. |
| Route | Ride, walk or pit-lane walk. |
| Tolerance | Simplification tolerance in metres, 0 to 30. 0 draws every GPS point. Applied when you let go. |
| Drawing | One gradient polyline, or one polyline per band run. |
| Gradient stops | Whether gradient colour stops are placed by vertex index or by length along the line. Only one of these will line up with the band-run drawing; see RESULTS.md. |
| Camera | Overview fits the route; follow is the chase camera. With Reduce Motion on, follow stays in overview. |
| 3D elevation | Realistic elevation on or off. |
| Standard map | Standard map instead of satellite imagery. |
| Dim ahead | Fades the route ahead of the marker. |
| Above labels | Draws the line above map labels instead of above roads. |

## The frame-rate readout

The top line shows drawn vertices, GPS points, records and band runs, then frame rates: now, worst over any quarter second while measuring, the longest single frame, and the count of frames over 25 ms.

It comes from a `CADisplayLink` on the main thread asking for 120 Hz. MapKit renders the map on its own thread, so the readout catches main-thread stalls (overlay redraws, camera and marker updates) but can miss a slow map render. Turn on Settings › Developer › Graphics HUD as well, which shows the frame rate of the Metal layer the map draws into.

## Follow-map render margin

The follow map renders at 1.5 times the viewport's width and height, clipped to
its center (25% extra on each edge). This gives MapKit surrounding terrain to
load before it enters view; it is not a guaranteed tile-prefetch API. Camera
distance scales with the render surface to preserve scale near the marker.
Overview, including Reduce Motion, uses the normal viewport.

When checking this on a phone, run both 60 s and 15 s sweeps on the ride, with
satellite imagery and realistic elevation enabled. Compare cold-cache tile
pop-in, frame times, memory and thermal behavior against the previous build.
Also check reverse scrubbing, overview/follow transitions, reopening the detail,
and rotation. The compass and Apple attribution must stay inside the crop.
The extra render area is bounded at 2.25 times the visible area, but its device
performance and network benefit still need measurement.

Verification: the iOS simulator harness builds and the 27 host-side flyover
logic tests pass. On an iPhone 17 Pro simulator (iOS 27.2), follow mode renders
with the compass and Apple Maps/Legal attribution inside the crop. A 15 s ride
sweep still showed unloaded terrain and frame hitches; this is not evidence of
seamless playback or a measured performance improvement. Device A/B validation
remains open.
