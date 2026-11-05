# Map performance measurements

Filter Console or Xcode's console to subsystem `com.arjunakankipati.sweatkit`,
category `MapPerformance`. These info-level events also appear in Instruments'
logging instrument. No coordinates, route names, activity IDs, or raw error URLs
are recorded.

| Event | What it measures |
| --- | --- |
| `detail_open` → `detail_data_ready` | Activity input loading; begins when the detail task starts, not at the physical tap |
| `detail_map_ready` | Prepared route/timeline published to SwiftUI; includes preparation duration and cache hit |
| `detail_analysis_ready` | Separate background analysis presentation preparation |
| `map_attached` | Map coordinator acquired, with whether the retained map was reused |
| `map_first_render` | First render callback since attachment, including whether all visible tiles rendered |
| `map_first_complete_render` | First fully rendered callback since attachment |
| `region_start` / `region_settled` | Camera movement sequence, duration, camera distance, pitch, overlay count |
| `map_render` | Render-pass time and time since camera settled, correlated by region sequence |
| `map_loading_finished` / `map_load_failed` | MapKit loading lifecycle duration or error domain/code |
| `map_configuration` | Imagery/standard and terrain setting for the run |

Durations in map events are milliseconds. Detail events use Swift Duration units.
A value of -1 means no corresponding start/settled callback was observed.
A render before the camera settles is expected. `fully_rendered=false` does not
by itself identify network delay. MapKit owns tile fetching and caching; these
callbacks cannot separate network time from decoding or internal scheduling.
A reused, already-rendered map may not issue a new rendering callback until moved.
Continuous follow-camera region/render-pass logs are suppressed to avoid logging
at 60 Hz; initial rendering and loading lifecycle events remain available.

## Repeatable device check

Use a Release build on the same device, network, route, and map settings. Record
thermal state and Low Power Mode. Capture a Time Profiler / Animation Hitches
trace alongside logs; a display-link callback rate is not proof of GPU frame rate.

1. Launch and open an activity. Record data, preparation, attachment, first render,
   and first complete render timings. Launching again does not clear Apple's tile cache.
2. Zoom from overview into the same street, then stop touching the map. Record
   camera distance and the first fully rendered callback after settling.
3. Pan to an unseen adjacent area and repeat. Then revisit the first area.
4. Return to the feed and reopen within five minutes. Check `reused=true` and
   `cache_hit=true`. Compare with a first visit to another activity.
5. Repeat with Standard selected. Keep terrain and pitch comparable when drawing
   conclusions about imagery cost.
6. Play and scrub in follow mode. Verify marker/camera stay aligned and inspect
   actual frame hitches. The requested cadence is now 60 Hz, with a 30 Hz minimum;
   iOS may choose a lower rate under power/thermal constraints.
7. Change profile thresholds or activity data and reopen: preparation must miss
   the cache. Verify analysis still opens, including indoor/no-route activities.

Long preparation with fast rendering points to our data work. Short preparation
with a long settled-to-complete interval points toward MapKit's visible content
pipeline. Hitches during either need the Instruments trace to identify CPU/GPU
work. Compare repeated trials rather than attributing one slow callback to tiles.

Prepared data cache: two most recently used exact inputs, excluding recordings
above 100,000 samples. Input equality includes stream, profile, laps, and metadata;
comparison and preparation run on a separate actor. The detail screen clears it
on memory warnings. One idle MKMapView is retained for five minutes in NSCache,
which can evict under pressure and is also cleared on memory warnings. This is
view reuse, not a custom tile cache or an offline-download guarantee.
