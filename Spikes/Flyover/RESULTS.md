# Flyover gate results

**Status: both gates pass.** Run on the iPhone 18 Pro Max on 2026-11-04 from the Release build of the harness at commit `958e567`. MapKit stays the renderer.

MapKit is assumed as the renderer. These gates set the defaults of `FlyoverOptions` in `Packages/SweatKitFlyover`: realistic elevation on or off, gradient or band-run drawing, and how far to simplify. If the line looks wrong both with realistic elevation on and with it off, choosing another renderer is the user's decision.

## Gates

| Gate | Passes when | Result | Evidence | Decision |
| --- | --- | --- | --- | --- |
| Does a coloured route sit correctly on realistic 3D terrain? | The line follows the ground on the hilly and urban routes, with no floating or buried stretches | Pass | Satellite imagery with realistic elevation, follow camera, line above roads. Ride: the line follows the road through a wooded valley with no floating or buried stretches. Pit lane: the line lies on the tarmac beside the buildings and passes neither through nor over them. Judged by eye from screenshots. Weaker than the spec asks, because the ride is rolling rather than hilly (see below). | Keep `realisticElevation` on and the line `aboveRoads`. The flat fallback is not needed. |
| Does the coloured route hold frame rate while scrubbing? | 60 frames per second on the long ride, with imagery loaded | Pass | Follow camera at tolerance 2 m. Ride, gradient, 1,220 vertices: worst 60 fps, longest frame 16.7 ms, 0 hitches. Pit lane, both gradient and band runs, 1,548 vertices in 1,212 runs: worst 60 fps, 16.7 ms, 0 hitches. Over the whole session the user saw 60 fps nearly throughout, with one hitch. Main-thread readout only; the Graphics HUD reading was not recorded. | Default to band runs (see below). Keep simplifying at about 2 m. No vertex reduction is needed at this length. |

**Why band runs over a gradient.** Both drawings held 60 fps with 1,212 overlays on the pit lane, so speed does not choose between them. Band runs put every band edge exactly where the route says, by construction. A gradient's edges depend on how MapKit measures stop locations. In the pit-lane screenshots, band runs and the gradient with stops by vertex agree almost everywhere, but differ on the long straight segments at the top right, which suggests MapKit does not measure by vertex. Stops by length was not compared. The gradient stays available in case a much longer route needs fewer overlays.

**Not covered.** These were not tried, so they are still open when the app is built:

- Dim ahead, which redraws the line on every frame. The spec dims during playback, so measure it with the real playback in M2.
- Tolerance 0, and anything near the 5-hour ride in the performance target (about 18,000 samples).
- Reduce Motion, the end-of-route behaviour of the follow camera, and the standard map.
- The flat fallback with realistic elevation off.

**Crash.** The harness crashed once in `__pthread_kill` (an `abort()`) on the main thread. Its cause was not captured: there is no console output or backtrace. The user chose not to chase it in the throwaway harness. If it shows up in the app, get the console line and `bt` output before changing anything.

## How the fixtures differ from the spec's routes

The spec asks for a long hilly ride, a short urban ride and a walk under tree cover. These files only approximate them:

| Spec route | Stand-in | Gap |
| --- | --- | --- |
| Long hilly ride | `outdoor-ride.fit`: 37.5 km, 1.6 h, 5,347 records | Rolling rather than hilly: 177 m of ascent, altitude 166 to 231 m. Terrain placement errors show most on steep slopes, so a pass here is weaker evidence. It is also well short of the 5-hour ride the performance target names, about 18,000 samples. |
| Short urban ride | `walk-pitlane.fit`: a walk beside buildings | A walk, not a ride, and a pit lane rather than streets. It is the only file near buildings, so it is the one to check for lines buried in or floating over 3D buildings. At tolerance 0 it draws 26,908 vertices, the harshest vertex-count case available. |
| Walk under tree cover | `walk.fit`: 3.3 km in the open | No tree cover. It shows a short, flat route at walking scale. |

If a genuinely hilly ride is to hand, add it as a fixture and repeat the terrain checks on it before relying on a pass.

Vertex counts from decoding on the Mac (`drawn vertices · band runs`):

| Route | Tolerance 0 | 2 m | 5 m | 10 m | 20 m |
| --- | --- | --- | --- | --- | --- |
| Ride | 5,347 · 769 | 1,220 · 769 | 964 · 769 | 866 · 769 | 808 · 769 |
| Walk | 2,492 · 86 | 113 · 86 | 96 · 86 | 90 · 86 | 87 · 86 |
| Pit lane | 26,908 · 1,212 | 1,548 · 1,212 | 1,317 · 1,212 | 1,248 · 1,212 | 1,219 · 1,212 |

The band-run drawing adds one overlay per run, and twice that with dimming on.

## What to check on the device

Ticked items were checked in the 2026-11-04 run.

Before measuring: Release build (the scheme's default), Low Power Mode off, phone not hot, on Wi-Fi, and Settings › Developer › Graphics HUD on. Let imagery finish loading in overview before each frame-rate run, since the gate is "with imagery loaded".

### Terrain gate

For each route, with satellite and 3D elevation on, in overview and then follow:

- [x] Ride: pitch the map low and rotate around the steepest stretches. Does the line lie on the ground, or float above valleys or vanish into hillsides?
- [ ] Ride: zoom right in where the route crosses a bridge or passes under one.
- [x] Pit lane: near buildings, does the line pass through them or sit on their roofs?
- [ ] Walk: at walking scale, does the line sit on the paths?
- [ ] Repeat with 3D elevation off and the camera pitched. Does the flat fallback read well enough?
- [ ] Repeat with Above labels on. Does the level change how the line sits on terrain?
- [ ] Standard map with 3D elevation on: does the line sit on the terrain there too?

### Frame-rate gate

On the ride, overview and then follow, with the 60 s sweep and then a fast hand scrub:

- [x] Gradient, tolerance 2 m: worst fps, longest frame, hitches, and the Graphics HUD.
- [x] Band runs, tolerance 2 m: the same.
- [ ] Each of those with Dim ahead on. Dimming redraws the line on every frame.
- [ ] Tolerance 0 (5,347 vertices) for the strategy that did better, as a stand-in for a longer ride.
- [ ] Pit lane at tolerance 0 (26,908 vertices) as the worst case.
- [ ] If 60 fps is missed: raise the tolerance until it holds and note the vertex count. The floor is about one vertex per band run.

### Each switch, on any route

- [x] Drawing: gradient and band runs should look the same. If band edges are in different places, switch Gradient stops: the setting that matches band runs is how MapKit measures gradient locations, and becomes the default.
- [ ] Dim ahead: is the line faded exactly from the marker onwards in both drawings? A gap or overlap at the marker means `strokeEnd` is measured differently from what the package assumes.
- [ ] Camera follow: the camera sits behind the marker facing along the route, and turns smoothly through bends and switchbacks without whipping. Note whether the 600 m distance and 60° pitch feel right.
- [ ] Reduce Motion on (Settings › Accessibility › Motion): follow should stay in overview with only the marker moving.
- [ ] Standard map: the line and marker stay visible and coloured.
- [ ] Scrub to both ends: the marker reaches the first and last points, and follow mode does not spin at the end.

## Defaults set from the results

| Option | Default | Why |
| --- | --- | --- |
| `realisticElevation` | `true` | Terrain gate passed |
| `lineLevel` | `.aboveRoads` | Terrain gate passed at this level; above labels was not needed |
| `lineDrawing` | `.bandRuns`, was `.gradient` | Equal frame rate; band edges exact |
| `gradientLocations` | `.vertexIndex`, unchanged | Not settled. It only matters if the gradient is used, so check stops by length first if it is. |
| `dimsAhead` | `false`, unchanged | Not measured. The app turns it on during playback. |
| `followDistance`, `followPitch` | 600 m, 60°, unchanged | Looked right in the follow screenshots. Not tuned. |
| Simplification tolerance (Ingest) | About 2 m, as in the spec | Held 60 fps on both routes |
