# SweatKit - Activity App MVP Spec

Nov 4, 2026 · @Arjuna

## Summary

A native iOS app that replaces Strava for viewing one person's own rides and walks. It merges Garmin and Apple Health activities into one library and shows each as a scrubbable 3D flyover with an effort-coloured route. It also compares efforts on repeated routes and tracks trends over time.

**Goals**

- View any activity from Garmin, Apple Health or a FIT file without opening Strava or Garmin Connect.
- Drag a timeline to see stats at any point on the route, in 3D.
- See where effort went: power colour on rides, pace colour on walks and runs.
- Compare efforts on routes done repeatedly, and see volume and performance trends.
- Stay local-first: no account and no server of its own. Data lives on the device, with a copy in the user's private iCloud.

**Non-goals for the MVP**

- Social features: followers, kudos, public segments, leaderboards.
- Recording activities. The Garmin computer, Zwift and Apple Watch keep doing that.
- Writing data back to Garmin Connect or Apple Health.
- Distribution to other people. The MVP is built for personal use on Garmin's Personal API tier.

**Assumptions**

- iPhone first, iOS 26 or later, because Liquid Glass needs it. The reference device for testing and performance targets is the iPhone 18 Pro Max.
- Sports with full support: cycling (outdoor and virtual), walking, running and hiking. Other sports show summary stats only.
- Metric units by default, switchable to imperial.

## Scope

The MVP covers viewing, analysing and comparing activities. Planning routes, AI features and sharing come later.

| Area | In the MVP | Later |
| --- | --- | --- |
| Sources | Garmin Personal API, Apple HealthKit, FIT file import | Garmin Starter tier with push sync |
| Activity detail | 3D flyover, timeline scrubbing, colour overlays, charts, laps | Video export |
| Analysis | Power and heart-rate zones, weighted power, load, power curve, splits | AI summaries |
| Route comparison | Auto-detected repeated routes, effort-against-effort comparison | Auto-detected shared sections such as a climb inside different rides |
| Trends | Volume, power curve over time, efficiency, records | Fitness and fatigue modelling, natural-language search |
| Routes | None | Route planning and course push to Garmin |
| Platform | iPhone, local storage, originals and decisions copied to private iCloud | iPad, Mac, Watch, widgets |

The work is staged. A daily-use core of library, activity detail and sync comes first and ends in a checkpoint. iCloud storage, analysis, route comparison and trends follow, so they do not delay finding out whether the core replaces Strava for viewing.

## Data sources and sync

Three sources feed one library. Each source's original data is preserved, and one normalised activity model derived from it is what the rest of the app reads.

| Source | Provides | How it syncs | Limits |
| --- | --- | --- | --- |
| Garmin Personal API | Activity summaries as JSON, and each activity's original file inside a zip | Foreground pull on launch and on pull-to-refresh; background refresh when iOS allows it | Pull-only with no change feed; access tokens last 24 hours or until the key expires or is deleted, with no refresh token; keys expire after 30, 90 or 180 days or 1 year; rate limits are not documented |
| Apple HealthKit | Workouts, GPS routes, heart rate, cycling power, cadence and speed | Anchored queries, with background delivery when iOS allows it | Quality depends on the app that wrote the data; many workouts have no route or power |
| FIT file import | Anything exported from Zwift, a Garmin device or a Garmin data export | Share sheet, Files picker, or a folder or zip for bulk import | Manual |

**What is preserved**

- Garmin delivers each activity's original file inside a zip. The file inside is the original: it is kept byte for byte, and its hash is the revision hash. The zip is only a container and is not kept.
- Imported files are kept byte for byte.
- HealthKit has no raw file, and its data can change or be deleted later. Each import stores a versioned snapshot of the workout, its samples, its route, its metadata and its source identifiers.
- The normalised stream is derived from either kind of original and can always be rebuilt.

**Garmin sync as reconciliation**

Garmin's activity search filters only by the activity's local start date and pages by offset. Its date range includes both end dates. It has no "changed since" filter, so sync is a reconciliation that runs at three depths. M0 exercised the listing, paging, sorting and download endpoints with a live key and confirmed the behaviour described here.

| Depth | Runs | Covers |
| --- | --- | --- |
| Quick sync | Every launch and pull-to-refresh | Activities with a start date in the last 30 days, plus anything newer |
| Deep scan | At most once a week, in the foreground | Every date range of history listed again and reconciled |
| Full reconciliation | On request, from settings | A full listing, plus a fresh download of every file or of the files the user picks |

A ride uploaded a week late is caught by a quick sync. One uploaded months late, or an edit to an old activity, is caught by the next deep scan.

**Identity and revisions**

| Source | Stable identity | A new revision is |
| --- | --- | --- |
| Garmin | Garmin plus the activity ID | A changed summary, or a changed file by the hash of the original inside the download |
| HealthKit | The workout's UUID | A changed route or sample set, by snapshot version |
| Imported file | The hash of the file's bytes, because there is no external ID | Not applicable; an edited file is a different record |

- A change becomes a new revision of the same record, never an additional record.
- Imports are idempotent. Repeating one changes nothing.
- An imported file that is byte-for-byte identical to a stored original is recognised as that record and adds nothing.
- A changed Garmin summary updates the metadata. The file is downloaded again when the summary's start, duration or distance changed, or when the user asks.
- Known limit: a file that changes at Garmin while its summary stays identical is not noticed until a full reconciliation downloads it again. Garmin's per-activity summary carries a last-update date that the listing does not. If that date moves when an activity is edited, a deep scan could check it at one request per activity and narrow this limit. M0 did not test that, so it is an open question for M3.

**Sync steps**

1. The user creates a Personal API key in Garmin Connect settings and pastes it into the app, with the expiry period they chose. The key is stored in the Keychain.
2. The app exchanges the key for an access token. Garmin's response states no lifetime, so the app treats the token as valid for the documented 24 hours, requests a new one 5 minutes before that, and requests one more if Garmin refuses the token early. A token also ends when its key expires or is deleted. A refused key therefore asks the user for a new key and is not retried.
3. The app lists the range for the chosen depth and compares each entry with the local record of the same identity.
4. New activities are downloaded and changed ones get a new revision.
5. Each activity succeeds or fails on its own. Failures are retried on the next sync, and the sync status says how many are outstanding.
6. Garmin emails a week before a key expires. The app cannot read a key's expiry from Garmin, so it counts from the period entered with the key, warns 7 days ahead and asks for a new key.

**First-sync backfill**

Garmin offers no snapshot of its listing. An old ride uploaded during the backfill, or a deletion, can shift offset pages, so the backfill does not rely on one long offset walk and does not claim snapshot consistency.

- One request with ascending sort finds the start date of the earliest activity.
- History is then walked in bounded ranges of one calendar month of start dates, newest first. The months are local-time months, because Garmin's date filter matches each activity's local start date. A month rarely exceeds one page of 99, so most ranges need no offset paging.
- A range is complete only when two listings of it in a row return the same set of identities. If they differ, the range is listed again, up to three times, and is then left for the next deep scan.
- A month that needs more than one page is paged with a 10-entry overlap and still has to pass the two-listing check.
- Completed ranges are checkpointed, so the backfill resumes at the first incomplete range.
- The deep scan repeats the same range-by-range reconciliation over all history. That is what picks up an old ride uploaded after its range was completed.
- Tests insert and delete activities at the source during paging and confirm that nothing is missed or duplicated once the ranges settle.

**HealthKit sync**

- Read-only access to workouts, workout routes, heart rate, cycling power, cycling cadence, cycling speed, running power and running speed.
- Anchored queries track additions, changes and deletions, and the anchor is persisted.
- A route can arrive or change after its workout is saved. A workout is snapshotted again whenever its route or samples change.

**Deletions**

- **Removed at the source.** This is inferred only after a complete, successful listing of the range that should contain the activity. A failed or interrupted listing infers nothing. HealthKit reports deletions directly. The local activity is kept and marked "removed at source", and the user decides what to do with it.
- **Hidden in the app.** The activity leaves the feed, records, routes and trends. All of its stored data is kept, and it can be restored from settings.
- **Permanently deleted.** Its originals, snapshots, streams and derived results are erased from the device and from iCloud. This needs confirmation and cannot be undone.
- In both of the last two cases a tombstone keeps the source identity, so the next sync does not bring the activity back.

**Background refresh**

Foreground sync is the reliable path. iOS decides when background refresh runs, so it is treated as a bonus and nothing depends on it.

**De-duplication**

Garmin Connect also writes workouts to Apple Health, so the same ride can arrive from two or three sources.

Two records are merged automatically only when all of these hold:

- the sport family matches,
- start times are within 2 minutes,
- elapsed durations are within 5%,
- distances are within 5%, for outdoor activities only, because indoor distance differs widely between recorders.

A source identifier that links two records settles the match on its own, where one exists. The tolerances are starting values.

- Records that overlap in time but fail the test stay separate and are flagged as possible duplicates. The user merges them or keeps both.
- A merged activity has one primary record, which supplies every stream. The default primary is an original file, then HealthKit, and the user can switch it.
- The other records are preserved as alternatives. There is no automatic field-by-field merging in the MVP.
- When an alternative holds a channel the primary lacks, such as heart rate, the detail screen says so and offers the switch.

**Activity identity across devices**

Source identity stops duplicate source records. It does not by itself guarantee one activity when two devices merge the same records independently, so merges are stored as data.

- A "same activity" link joins two source records. A "keep separate" link forbids two source records from sharing an activity.
- A link is a record of its own. It holds the two identities, its kind, whether a user or the automatic rule made it, the time and the device.
- Link records are only ever added, never edited. An automatic link is named from its pair and kind, so two devices that make the same automatic merge write the same record.
- When a pair has more than one link, one of them is in effect, chosen in this order:
  1. A user-made link beats an automatic one.
  2. The later time wins.
  3. On equal times, "keep separate" beats "same activity".
  4. Then the higher device ID wins, then the higher record name.
- A merge and a "keep separate" made on the same pair at the same moment therefore resolve to separate on every device.

**Forming activities from links**

Separation is enforced across the whole group, not only between the linked pair. If A must stay separate from B, links A to C and C to B must not bring all three together.

1. Every source record starts as its own group.
2. "Same activity" links that are in effect are applied one at a time in a fixed order: user-made links first, then automatic ones, each set ordered by link name.
3. A link is applied only if the merged group would contain no pair whose link in effect is a "keep separate" link. Otherwise it is skipped and shown as a possible duplicate for review.
4. Every device applies the same links in the same order, so every device forms the same groups.
5. An activity's ID is the lowest identity among its members.

On one device the app does not create the conflict in the first place. A merge that would break a separation asks the user to lift the separation first.

**Decisions belong to the activity**

A title, a hidden state and any other user decision belongs to the activity, not to whichever record supplies its streams. Switching the primary source changes the data shown and nothing else.

**What a decision record holds**

- The field, the value, the time it was made and the device that made it.
- The member identities it applies to. A decision made on an activity applies to all of that activity's members at the time.
- Whether it is a direct decision or an inherited copy.
- Decision records are only ever added, never edited, so they cannot conflict in storage.

**How an activity's value is worked out**

1. For each member, take the winning decision among those that apply to it.
2. For a title or any other single-value field, the activity uses the winner among its members' decisions.
3. For hidden state, the activity is hidden if any member's winning decision is "hide".

The winner is the decision with the later time. On equal times a direct decision beats an inherited copy, then the higher device ID wins, then the higher record name.

The result depends only on which records exist, not on the order they arrived in. Every device therefore reaches the same answer once it has the same records.

**Merges and splits**

- A merge writes no decision. The rule above gives the merged activity the most recent title and keeps it hidden if either side was hidden.
- A split writes an inherited copy of every decision then in effect, once for each resulting part. Each copy applies to that part's members and keeps the original decision's time.
- A copy is not a new decision. A rename or hide made on another device, later than the original, still wins on every part it applies to.
- The primary choice is a decision like any other. If the chosen primary is no longer a member, the default order applies again.

**Deletion**

- Permanently deleting an activity writes a tombstone for every member's identity.
- Deletion wins over stale updates. A tombstone outlasts any later write from a device that had not seen it.
- Only a restore made after the tombstone reverses a hide, and sync never reverses a permanent delete.

**Cases the tests must cover**

- Three records where A and B are kept separate and both match C.
- A merge and a "keep separate" on the same pair, made on two devices at the same time.
- A renamed activity whose primary source is switched.
- A hidden activity that is merged with a visible one, and one that is split.
- The same merge made on two devices while both are offline.
- A split on one device while another device, offline, renames the activity. The same again with a hide in place of the rename.
- Two decisions on the same field with equal times.
- The same set of records delivered in different orders, which must give the same result.

**Virtual rides**

Zwift FIT files are marked as virtual and carry made-up GPS coordinates. They are imported with full power, heart-rate and cadence data, and they open on charts instead of the flyover.

## Data model and storage

The normalised activity model is canonical: every screen and metric reads it, and it is derived from the preserved originals. Each derived result records what it was computed from, so a change to its inputs triggers a recompute, not a re-import.

| Entity | Holds | Notes |
| --- | --- | --- |
| Activity | Sport, start time and time zone, elapsed, timer and moving time, distance, ascent, summary stats, title, indoor flag | One per real-world activity |
| Source record | Source and external ID as the stable identity, revisions by content hash, original file or HealthKit snapshot, import date, primary flag, state | One or more per activity; state is active, removed at source, hidden or deleted |
| Timer events | Start, stop and pause times | From the file, or from the workout's pause events |
| Native stream | Every sample at its original timestamp, exactly as recorded | Never altered |
| Analysis stream | Per-second position, altitude, distance, speed, heart rate, power, cadence, temperature and gradient | Derived from the native stream; each value is measured, interpolated or missing |
| Lap | Start and end index, lap stats | From the device, or auto-split per km |
| Route | Name, reference line, sport, direction | A group of activities on the same course |
| Effort | Activity, route, alignment, alignment confidence, moving time, power, heart rate | One per activity on a route |
| Best effort | Activity, duration or distance, value | Feeds the power curve and records |
| Daily load | Date, total load, whether any activity's load is unavailable | Feeds trends |
| Athlete profile | Threshold power history, max heart rate, threshold heart rate, zones, weight, units | Thresholds are date-effective, so old activities keep their old zones |

**Stream rules**

These rules sit under almost every metric, so they are fixed here and versioned.

- The analysis stream is a 1 Hz grid over elapsed time, starting at the activity start. It is rebuilt from the native stream whenever a rule changes.
- The sample at second t describes the interval from t to t + 1. A duration is a count of samples, so every duration and window is a whole number of seconds. A native sample belongs to the grid second that contains its timestamp, and several native samples in one second are averaged.
- Every value in every channel is marked measured, interpolated or missing.
- Gaps of up to 5 seconds are filled and marked interpolated. Position, altitude, distance and heart rate are filled linearly. Power and cadence hold the last value.
- Nothing is interpolated across a pause boundary. The values on each side of a pause stand alone.
- Longer gaps are missing. Missing is never zero: a recorded 0 W while coasting is measured, and no reading is missing.
- A sensor dropout affects only its own channel, and it never shortens the activity. Only timer events create pauses.
- Paused spans stay in elapsed time and are excluded from timer time.
- Speed is taken from the recorded speed, then from the change in recorded distance, then from position. It is missing when none of these exists.
- Gradient is altitude change divided by distance over a 30 m window centred on the sample. It is missing, never zero or infinite, when altitude is missing or when the window covers less than 5 m of travel.

**Recomputation**

Every derived result records the revision of its inputs, the revision of the athlete profile it used, and the algorithm version. It is valid only while all three still match. This tracking is built in M1, before the features that rely on it.

| Action | What becomes stale |
| --- | --- |
| An algorithm version changes | Everything that algorithm produces, and everything computed from that |
| A source record gets a new revision, or the primary source is switched | That activity's analysis stream, summary, metrics, best efforts and route alignment; then records, route statistics and that day's load |
| A historical threshold is corrected | Zones, intensity and load for activities in the affected dates; then daily load. Streams and alignments are untouched. |
| Activities are merged or split | The streams, summaries, metrics, best efforts and alignments of the activities involved; then records, route statistics and daily load |
| An activity is hidden, deleted or restored | Records, route statistics, daily load and trends. A route that loses its reference effort needs a new one. |
| A route's reference effort changes | Every alignment and effort on that route, and the route's statistics |

**Storage on the device**

- Metadata lives in SwiftData. Originals, snapshots and streams live on disk in the app container.
- A 5-hour ride is about 18,000 samples, which is around 1 MB per stream file.
- The app works fully offline. iCloud is a second copy, not a dependency.

**Storage in iCloud**

Originals and the user's decisions are saved to the user's private CloudKit database. Derived data stays on the device and is recomputed there.

| Data | In iCloud | Reason |
| --- | --- | --- |
| Original files from Garmin and from import | Yes, as file assets | Hard to replace if Garmin access ends |
| Activity and source-record metadata for those files | Yes | Needed to rebuild the library |
| Source identities, "same activity" and "keep separate" links, and tombstones, for every source including HealthKit | Yes | Merges, hides and deletions must survive a restore. A HealthKit identity is the workout's UUID and carries no health data. |
| User decisions: titles, primary choices, hidden state, route names, reference efforts, manual route edits | Yes | Cannot be recomputed |
| Athlete profile and threshold history | Yes | Cannot be recomputed |
| HealthKit snapshots, samples, routes and summaries | No | Apple's App Review rules bar storing personal health information in iCloud |
| Streams, metrics, alignments, best efforts, daily load, thumbnails | No | Recomputed on each device from the originals |
| Garmin key | No | Stays in the Keychain |

**What a restore brings back**

| Activity | After a wipe and restore |
| --- | --- |
| From Garmin or an imported file | Fully rebuilt from the originals in iCloud |
| HealthKit-only, with the workout still in Apple Health | Read again from Apple Health, with its decisions re-attached by workout UUID |
| HealthKit-only, with the workout since deleted from Apple Health | Lost. The local snapshot was the only copy, and it is not in iCloud. |
| Hidden or permanently deleted, from any source | Stays hidden or deleted, because its tombstone is in iCloud |

The restore guarantee is therefore limited to Garmin and imported activities. Re-attaching HealthKit decisions assumes a workout keeps the same UUID on every device, which M4 verifies.

- The private database belongs to the user's Apple account. Nobody else can read it, there is still no server to run, and it counts against the user's iCloud storage.
- Source records are named from their stable identity, and automatic links from their pair and kind. Two devices that import or automatically merge the same activity therefore write the same records. Links and decisions made by the user are individually identified, add-only records, so each user action is kept as its own record.
- Stored originals never change, because a new revision is a new asset. Decisions are separate, add-only records resolved by the rule in the activity identity section, so they do not conflict in storage. A tombstone outlasts stale updates.
- Sync uses CloudKit's sync engine directly, not SwiftData's automatic CloudKit mirroring. Mirroring does not support unique constraints, which the identity rule depends on.
- A new or restored device downloads the originals and decisions, reads Apple Health again, and recomputes everything else in the background.
- The App Review rule matters only if the app is distributed, and Garmin heart-rate data may fall under it too. That is recorded as a risk.

## Activity feed

The home screen is a reverse-chronological list of every activity from every source.

- Each card shows a route thumbnail, title, sport, date, distance, moving time and ascent. Virtual and indoor activities show a small power or heart-rate sparkline in place of the map.
- The headline metric depends on the sport: weighted power for rides with a power meter, shown as average power until the analysis milestone, and average pace for walks and runs.
- Week headers carry totals for distance, time and ascent.
- Titles are generated from time of day, sport and locality ("Morning ride, Richmond Park") and can be edited.
- A source badge shows where the activity came from. Garmin requires attribution wherever its data is displayed.
- Filters: sport, date range, indoor or outdoor, and a title search.
- Pull-to-refresh runs a sync. A badge marks activities that set a record or belong to a repeated route.
- Thumbnails are rendered once with the map snapshotter and cached.

## Activity detail and flyover

The detail screen is a full-screen 3D map with a draggable timeline, and the timeline is the main control. Dragging it moves the marker, the camera and every stat together.

**Layout**

- The map fills the screen, in satellite imagery with realistic elevation. A toggle switches to the standard map.
- A glass stats panel floats at the top and shows values at the cursor.
- A glass timeline floats at the bottom.
- A pull-up sheet holds the deeper analysis: full charts, laps, zones, best efforts and the route comparison.

**Timeline**

- The base layer is the elevation profile. One overlay series is drawn on top: power, heart rate, speed or pace, or cadence.
- The x-axis switches between distance and time. Detected stops can be collapsed.
- Dragging scrubs. Pinching zooms. A long-press drag selects a range and shows stats for it: time, distance, ascent, average power and heart rate.
- Lap boundaries are tick marks with a haptic tap as the cursor crosses them.

**Stats at the cursor**

| Sport | Shown |
| --- | --- |
| Cycling | Distance, elapsed time, speed, 3-second power, heart rate, cadence, elevation, gradient |
| Walking, running, hiking | Distance, elapsed time, pace, heart rate, cadence, elevation, gradient |

**Camera**

- Overview mode fits the whole route with free pan, zoom and rotate.
- Follow mode is a chase camera behind the marker. Its heading is the bearing to a point 150 to 300 m ahead on the route, smoothed so that switchbacks do not whip the view.
- Pinch changes the follow distance and a drag orbits. A recentre button returns to the default view.
- Play and pause sit beside the timeline. Default playback finishes any activity in about 60 seconds, with 0.5x, 2x and 4x options.
- With Reduce Motion on, follow mode is replaced by overview mode with a moving marker.

**Route colouring**

| Overlay | Default for | Colour rule |
| --- | --- | --- |
| Power | Rides with a power meter | Seven zones from threshold power, on 10-second smoothed power so colours form readable bands |
| Heart rate | Rides without power | Five zones from threshold heart rate |
| Pace or speed | Walks, runs, hikes | Relative to the activity's own range, so fast and slow stretches stand out within one walk |
| Gradient | None | Descent, flat, and three steepness bands of climb |
| Plain | None | Single colour |

The palette is colour-blind safe and a legend chip names the current overlay. The whole route stays coloured, and the part ahead of the marker is dimmed during playback.

**Track cleanup**

Both reference videos show raw GPS, and one ends in a tangle where the recorder sat still. Before drawing, the app:

- drops points that imply an impossible speed,
- collapses jitter while stopped into a single point,
- simplifies the line to about 2 m tolerance for rendering, keeping a map from each drawn vertex back to its sample.

**Performance targets**

- Cached activity data, meaning the stats, the timeline and the route line, appears within 1 second for a 5-hour ride on the reference device.
- Map imagery loads separately and depends on the network, so it is outside that target. The route is drawn first and imagery fills in behind it.
- Scrubbing holds 60 frames per second once imagery has loaded.

**Activities without a usable route**

Virtual and indoor activities skip the map. The charts fill the screen and the timeline behaves the same way.

## Analysis metrics

Every metric is computed on the device from the analysis stream. The definitions below are the contract that the tests check, and the numbers in them are starting values.

**Time**

| Measure | Definition |
| --- | --- |
| Elapsed time | The activity's own start and end, as stated in the file's session record or the Health workout. The first and last samples are the fallback when those are absent. |
| Pause data, complete | Every stop inside the session has a matching start. A final stop at the session end, with nothing recorded after it, is the normal end of a recording and counts as complete. |
| Pause data, incomplete | Pause events are absent, or a stop inside the session has no matching start while samples or events continue after it. A later sensor sample does not prove the timer restarted. |
| Treated as unpaused | Pause events are absent and the stated timer time is within 1% of elapsed time. The activity is handled as having no pauses. |
| Timer time, complete pause data | Elapsed time minus the paused spans |
| Timer time, incomplete pause data | The timer time stated in the file or workout, shown as a summary figure only. Unavailable if none is stated. |
| Moving time, outdoor | Timer time minus seconds below 0.5 m/s on foot or 1.0 m/s on a bike. Seconds with missing speed count as moving. |
| Moving time, indoor or without speed | Equal to timer time |
| Activity with no stream | All three times come from the stated metadata, and moving time equals timer time |

**When pause positions are unknown**

A stated timer duration says how long the pauses were, not where they were. With incomplete pause data, any metric that needs to know which seconds were running is unavailable.

| Status | Metrics |
| --- | --- |
| Still available | Elapsed time, the stated timer time, distance, ascent, time in zones, recorded work, and average power and heart rate over the seconds that have them |
| Unavailable | Moving time, coverage, weighted power, intensity, variability, both kinds of load, the power curve, splits and best distances |
| Route comparison | Any comparison that includes this effort uses elapsed time for both efforts, and the moving-time option is disabled. The effort is left out of moving-time rankings and statistics, and is listed with its elapsed time. |

Sensor gaps are not pauses. A missing reading never shortens elapsed, timer or moving time.

**Zones**

| Zones | Definition |
| --- | --- |
| Power, seven zones | Share of threshold power: under 55%, 55 to 75%, 75 to 90%, 90 to 105%, 105 to 120%, 120 to 150%, over 150% |
| Heart rate, five zones | Share of threshold heart rate: under 81%, 81 to 90%, 90 to 94%, 94 to 100%, 100% and over |
| Gradient, five bands | Descent under -2%, flat from -2% to 2%, climbs of 2 to 5%, 5 to 8%, and over 8% |
| Boundaries | A value exactly on a boundary belongs to the higher zone |
| Threshold heart rate | Set in the athlete profile. Until the user sets it, it defaults to 90% of max heart rate. |

**Power, cycling only**

| Metric | Definition | Available when |
| --- | --- | --- |
| Power coverage | Share of timer seconds with measured or interpolated power | Pause data is complete, or the activity is treated as unpaused |
| Average power | Sum of power divided by the number of seconds that have power; zeros included | Any power exists; coverage is shown beside it when under 90% |
| Weighted power | Take the mean of each valid 30-second window, raise it to the fourth power, average those over the valid windows, and take the fourth root | At least 90% of the possible windows are valid and there are at least 5 minutes of power |
| Intensity | Weighted power divided by the threshold power in effect on the activity date | Weighted power is available and threshold power is set |
| Load from power | Timer hours x intensity squared x 100 | Intensity is available |
| Variability | Weighted power divided by average power | Weighted power is available and average power is above zero |
| Work | Sum of power over the seconds that have it, in kilojoules | Any power exists; labelled "recorded work" when coverage is under 98% or pause data is incomplete |
| Power curve | Best mean over the valid windows of each duration | At least one valid window of that duration exists |

**Window rules**

- Windows run over timer time, with paused spans removed and the series joined.
- A 30-second window starting at second s covers the interval from s to s + 30, which is samples s to s + 29. The first window is samples 0 to 29, and it is complete at a timer time of 30 seconds.
- A window's mean is the sum of its present values divided by the number of present values. Missing seconds are left out of both, and are never counted as zero.
- A 30-second window is valid when at least 24 of its seconds have power. Invalid windows are left out of the weighted-power average.
- A power-curve window is valid when it sits inside one unbroken timer span and at least 95% of its seconds have power. A window shorter than 20 seconds must be complete.
- All windows and durations are whole seconds, as set by the stream rules.

**Heart rate**

| Metric | Definition | Available when |
| --- | --- | --- |
| Heart-rate coverage | Share of timer seconds with measured or interpolated heart rate | Pause data is complete, or the activity is treated as unpaused |
| Load from heart rate | Each second scores (heart rate / threshold heart rate) squared. Load is the sum over timer time, divided by 3,600, times 100. One hour at threshold is 100. | Heart-rate coverage is available and at least 90% |

**Which load an activity gets**

1. Load from power, when intensity is available.
2. Otherwise load from heart rate, when it is available.
3. Otherwise load is unavailable. It is never estimated from partial data.

A ride with sparse power, a ride under 5 minutes and a ride with no threshold power set all fall through to heart rate. The last case also prompts the user to set a threshold.

**Other**

| Metric | Definition |
| --- | --- |
| Ascent and descent | Summed by peak and valley. A climb runs from a low point to the next high point and ends once the altitude has fallen back by the threshold; a turn smaller than the threshold neither ends it nor counts. Descents mirror this. The threshold is 3 m, 1.5 m for cycling, and none for a virtual activity, whose altitude is computed and has no noise. Barometric altitude preferred over GPS. |
| Time in zones | Seconds per zone from measured and interpolated values; missing seconds are reported as their own bucket |
| Efficiency, cycling | Weighted power divided by average heart rate, when both are available |
| Efficiency, on foot | Average speed divided by average heart rate, over the seconds that have both. Always speed, never pace, so a higher value always means more output per heartbeat. |
| Splits | Pace, heart rate and ascent per km, for walking, running and hiking |
| Best distances | Fastest 1 km, 5 km and 10 km by timer time, for walking and running |

The elevation thresholds are provisional. They were fitted to four recordings, where they bring ascent within 2 to 17% of the figure each file states, and within 11 m in every case. They are to be checked against a larger set of activities before they are relied on.

**Rules across all metrics**

- Unavailable is its own state. It is shown as a dash with the reason one tap away, never as zero.
- A metric whose denominator is zero or missing is unavailable.
- A total that includes an activity with an unavailable value says so.
- Weighted power, intensity and load are the app's own metrics, defined here. They belong to the same family as common commercial power metrics, but no equivalence is claimed until these rules are settled and validated.
- Threshold power is entered by the user. The app suggests an update when 95% of the best 20-minute power in the last 90 days beats the current value.

**Acceptance**

Each metric has fixture files with expected results worked out independently under these rules. The fixtures cover pauses, missing and unmatched pause events, sensor dropouts, sparse power, a short activity, an activity of exactly 30 seconds, a recording that ends on a stop, an activity with no stream, an indoor ride without speed and irregular recording intervals. Comparison with another tool is a sanity check only, because other tools use different pause and smoothing rules.

## Repeated-route comparison

The app groups activities that follow the same course into a route automatically, then lets any two efforts on it be compared point for point. No setup is needed: a commute or a regular loop becomes a route the second time it is done.

Matching has two separate steps. Detection finds activities that plausibly share a course. Alignment then works out which point on one effort corresponds to which point on the route, and an activity joins a route only if alignment succeeds.

**Step 1: detection**

1. Resample each cleaned track to one point every 25 m and record the 50 m grid cells it passes through.
2. Pick candidates: same sport family, total distance within 10%, start and finish each within 200 m.
3. Shortlist candidates that share at least 85% of their grid cells.

Detection is cheap and deliberately loose. Cell overlap ignores order, so it cannot tell two laps from three, or an out-and-back from a one-way trip. It only nominates candidates.

**Step 2: alignment**

1. Each route has a reference line, taken from its first activity.
2. Each point of the candidate is mapped to a position along the reference line, in order. Route distance may only move forward, and each point searches a limited window ahead of the previous match.
3. Five measures are taken from the mapping, as listed below.
4. The outcome is join, review or reject.

| Measure | Meaning | Needed to join automatically |
| --- | --- | --- |
| Proximity | Share of points within 30 m of the reference line | At least 90% |
| Ends | How close the mapping gets to each end of the reference line | The first mapped point is within 25 m of the start, and the last is within 25 m of the end |
| Coverage | Share of the reference line's length that was mapped | At least 95%, with no unmapped stretch longer than 50 m |
| Length ratio | Distance travelled against the length of the reference line | Within 3% |
| Side offset | Average sideways distance from the reference line over any 200 m stretch, with its sign | No stretch more than 10 m to one side |

| Outcome | When |
| --- | --- |
| Join | All five measures pass, and the activity aligns with no other route |
| Manual review | The ends and coverage pass, and proximity is between 70% and 90%; or a stretch sits consistently to one side; or the length ratio fails; or the activity also aligns with a second route |
| Reject | Proximity is under 70%, or the ends or coverage fail |

- Proximity alone is not confidence. A road 20 m away passes a 30 m test, so a consistent offset to one side is treated as the signature of a parallel course.
- Where GPS accuracy cannot tell two courses apart, the app asks. It does not guess.
- The ordered mapping handles places visited twice. On an out-and-back or a lapped circuit, the same spot maps to different route distances on each pass.
- A reversed ride fails alignment, so it becomes a separate route. A climb and its descent are not comparable.
- An activity with no match waits as a possible new route until a second one aligns with it.

**Cases the tests must cover**

- Parallel roads within 50 m of each other.
- Two laps against three laps of the same circuit.
- An out-and-back against a one-way trip on the same road.
- A figure-of-eight.
- A detour under 50 m, which joins, and a longer detour or a missed turn with a return, which does not. A start 1 km into a known route must not join either. A start 20 m late joins and is timed over the timed section.
- GPS drift under trees and between tall buildings.

**Running and control**

- Matching runs in the background after each import and over the whole library on first launch.
- Virtual rides match the same way, because Zwift's coordinates are consistent between rides.
- The user can rename a route, merge two routes, remove an activity from a route and pick a different reference effort.
- Every threshold here is a starting value to tune against real history.

**Route page**

- The route on a map, the number of efforts, and the best, latest and median moving time.
- A dot chart of every effort by date, switchable between moving time, average power, average heart rate and efficiency.
- The list of efforts, sortable by date or time.

**Full efforts only**

This release compares full efforts only. An activity belongs to a route only if it covers the reference line from end to end, within the tolerances above.

- An activity that starts late, finishes early or takes a detour longer than 50 m does not join the route. It stays an ordinary activity.
- Detection and alignment agree on this. The start, finish and distance gates in detection, and the ends and coverage rules in alignment, all admit full efforts only.
- Being on the same route means the course matches. It does not make wind, traffic or stops equal, which is why efficiency is shown beside time.
- Partial efforts need a separate matching path and a rule for where their clock starts. They are listed under future improvements.

**Timed section and clock origin**

A full effort may begin up to 25 m after the reference start and stop up to 25 m before its end, so it may never touch either end exactly. Times are therefore measured over a timed section that every full effort is guaranteed to cover.

- The timed section runs from 25 m after the start of the reference line to 25 m before its end.
- An effort's clock starts when it crosses the 25 m mark and stops when it crosses the mark 25 m before the end.
- Each crossing time is interpolated between the samples on either side of the mark. A first or last mapped point that sits exactly on a mark supplies the time directly.
- Route times, rankings, the time-gap chart and the ghost marker all use the timed section.

**Comparing two efforts**

Any effort can be compared against the best, the previous one, or one picked from the list. Two different axes do two different jobs.

| Job | Axis | How |
| --- | --- | --- |
| Paired charts and the time gap | Route distance | Each effort is interpolated onto a 10 m grid of route distance. The gap at each grid point is the difference in time since the start of the timed section. |
| Ghost marker on the flyover | Time | Both markers run on one clock, the time since each effort entered the timed section. The distance between them on the map is the real gap at that moment. |

- Aligning the charts by distance means a stop at a traffic light does not shift everything after it.
- Aligning the ghost by distance would put both markers in the same place at all times, so it uses time.
- The clock is moving time by default, with elapsed time as an option. The charts, the gap and the ghost always use the same choice, and both efforts always use the same clock. If either effort lacks reliable pause positions, elapsed time is used for both and the moving-time option is disabled.
- Scrubbing the timeline in a comparison moves the clock, so both markers move together.
- A summary table gives the difference in moving time, weighted power, average heart rate, speed and efficiency.

Efficiency is shown beside time because wind and traffic change times while output per heartbeat is less affected.

**In the activity detail**

An activity on a known route shows one line, such as "7th time on this route, 2nd fastest, 1:12 behind best". Tapping it opens the comparison against the best effort.

**Out of scope for the MVP**

Detecting a shared section inside otherwise different rides, such as the same climb, is the natural next step. It reuses the same detection and alignment on part of a ride and is listed under future improvements.

## Trends

The Trends tab shows how much is being done and how output is changing over time. Every view filters by sport, date range and indoor or outdoor.

| View | Shows | Detail |
| --- | --- | --- |
| Volume | Distance, time, ascent and load per week, month or year | Bars per period, with the previous period and the same period last year for comparison. A period that includes an activity with unavailable load says so. |
| Power curve | Best power for each duration in a chosen window | Last 6 weeks against last 90 days, this year or all time; the estimated threshold power is marked |
| Threshold power | Estimated threshold power over time | A line from rolling 90-day best 20-minute power |
| Efficiency | Weighted power per heartbeat on steady rides with a power meter | One dot per ride with a trend line. It compares output per heartbeat on comparable efforts and is not a fitness score. A steady ride lasts at least 20 minutes with variability under 1.10. |
| Records | Best power per duration, fastest distances, longest ride, most ascent | All-time and this year; a new record adds a badge in the feed |
| Calendar | Daily load as a heat map | Tapping a day opens its activities; days with unavailable load are marked |

**Limits**

- The efficiency trend covers only rides with power in the MVP, because steadiness is defined through variability. Walks and runs are compared on the route page, where the course is the same.
- Trends are only as deep as the imported history. If the Garmin Personal API does not reach far back, a Garmin data export imported as a zip fills the gap.
- Fitness and fatigue modelling is deferred and listed under future improvements.

## Design

The map and the charts are the content, and Liquid Glass is used only for the controls that float over them.

**Principles**

- Glass is for the floating layer: the stats panel, the timeline, the tab bar, toolbars and sheets. List rows and chart backgrounds are not glass, and glass is never stacked on glass.
- Standard tab views, navigation stacks, toolbars and sheets are used so they pick up Liquid Glass from the system. Custom glass is limited to the stats panel and the timeline.
- Colour is reserved for data. Zone colours carry meaning; everything else is neutral with one accent.
- Stats use large, fixed-width digits so they do not jitter while scrubbing.
- Text over satellite imagery is tested against bright ground such as snow and sand, and dark ground such as forest.
- Reduce Transparency, Increase Contrast, Reduce Motion, Dynamic Type and VoiceOver are supported from the first build, including audio descriptions of charts.

**Screens**

| Screen | Purpose | Main elements |
| --- | --- | --- |
| Activities | Browse everything | Feed, filters, sync status |
| Activity detail | Explore one activity | Map, stats panel, timeline, analysis sheet |
| Routes | Browse repeated routes | Route list with effort counts and best times |
| Route page | Follow one route | Map, dot chart, effort list |
| Comparison | Two efforts side by side | Time-gap chart, paired charts, ghost flyover |
| Trends | See the long view | Volume, power curve, efficiency, records, calendar |
| Settings | Set up the app | Sources, athlete profile, units |

The tab bar has three tabs: Activities, Routes and Trends. Settings opens from a profile button.

## Architecture

The app runs on the device and has no backend of its own. The user's private iCloud database is its only remote store. Data flows one way, from three sources through one ingest pipeline to the screens.

| Layer | Parts |
| --- | --- |
| 1. Sources | Garmin Personal API (pull, a FIT file per activity) · Apple HealthKit (workouts, routes, samples) · FIT file import (share sheet, Files, zip) |
| 2. Ingest | Source adapters (one per source, one protocol) → Normalise (one 1 Hz stream format) → De-duplicate (merge overlapping records) |
| 3. Store | Originals (files and Health snapshots; the source of truth) · Activity database (metadata and derived results) · Stream files (per-second samples) |
| 4. Analysis, in the background | Metrics (zones, load, power curve) · Route matching (routes and efforts) · Trend engine (daily load, records) |
| 5. Screens | Activities (feed and filters) · Activity detail (flyover and timeline) · Routes (effort comparison) · Trends (volume and power) |

Each layer feeds the one below it. Every screen is derived from originals kept on the device.

Analysis results are cached in the database and recomputed from the preserved originals whenever a rule changes.

| Concern | Choice | Reason |
| --- | --- | --- |
| Interface | SwiftUI on iOS 26 | Liquid Glass and system components |
| Map | MapKit, with a wrapped map view for the flyover. The route is drawn as one line per run of the same colour band. | Direct camera control. M0 confirmed terrain placement and frame rate. Band runs put every colour edge exactly where the data says, and held the same frame rate as a single gradient line. |
| Charts | Swift Charts, with a custom canvas for the timeline | The timeline must redraw at 60 frames per second while scrubbing |
| FIT parsing | Garmin's FIT SDK for Swift | The official decoder, added as a Swift package; its licence limits redistribution |
| Local storage | SwiftData for metadata, files for originals and streams | Small database, cheap recompute |
| iCloud storage | CloudKit private database, through CloudKit's sync engine | Originals and decisions survive a lost device, with no server to run |
| Recomputation | Input, profile and algorithm revisions on every derived result | Stale results are found, not guessed |
| Background work | Swift concurrency with actors, and background app refresh for sync | Ingest and analysis stay off the main thread |
| Secrets | Keychain | Holds the Garmin key |

- The code is split into Swift packages: Sources, Core (model, parsing, storage), Analysis, Route Matching, and the app itself.
- Analysis and Route Matching are pure Swift with no interface or network code. They are tested against a fixed set of real FIT files.
- Every source implements one protocol. The Garmin Starter tier can later replace the Personal tier without changes downstream.

## Milestones

The build starts with two spikes that settle the biggest unknowns, each with a pass condition and a decided fallback. It then builds a daily-use core and stops at a checkpoint before anything else is added. No dates are set.

| Milestone | Delivers | Done when |
| --- | --- | --- |
| M0 Spikes | A Garmin client with a throwaway probe, and the flyover map component with a throwaway device harness | Every gate below has a recorded result and a decision. Complete: all five passed on 4 November 2026. |
| M1 Library | File import, handling of corrupt and unreadable files, preserved originals, native and analysis streams, a minimal athlete profile, revision tracking, feed | 500 imported files browse smoothly and survive a relaunch; the stream-rule fixtures pass; correcting a threshold marks the right results stale; a corrupt or truncated file is rejected with a clear message and leaves the library unchanged. The feed headline for rides is average power for now. |
| M2 Activity detail | Flyover, timeline, zone calculations for the overlays, charts, laps | Cached data for a 5-hour ride appears within 1 second on the reference device; scrubbing is smooth once imagery has loaded; a Zwift ride opens on charts |
| M3 Sync | Garmin reconciliation, HealthKit, de-duplication, deletions, and recovery from denied Health permission, an expired key or token, and failed requests | A new ride appears once after a refresh; a ride uploaded a week late is caught by a quick sync and one uploaded months late by a deep scan; a backfill that is interrupted, or disturbed by uploads and deletions at Garmin, settles with no gaps or duplicates; a partial recording inside a longer ride is flagged, not merged; two records kept separate are not joined through a third; an offline split concurrent with a rename or a hide settles the same way on both devices; denied Health access, an expired key and a failed sync each say what happened and how to recover, and sync resumes afterwards without a reinstall or data loss |
| Checkpoint | Two weeks of daily use in place of Strava for viewing | A decision on whether the core replaces the existing workflow, and on the order of what follows |
| M4 iCloud | CloudKit copy of originals, decisions and profile | A wiped device restores every Garmin and imported activity from iCloud and recomputes it; hidden and deleted activities stay that way; two devices that import and merge the same ride end with one activity; HealthKit workout UUIDs are confirmed to match across devices |
| M5 Analysis | Weighted power, load with eligibility rules, power curve, records | Every metric fixture passes; the feed headline switches to weighted power |
| M6 Routes | Detection, alignment, route page, comparison with ghost marker | Every alignment test case passes, with the parallel-road case sent to review; known repeated routes in real history group correctly, with no false merges in a manual review |
| M7 Trends | Volume, power curve, threshold power, efficiency, records, calendar | A full year of history renders each view in under 1 second |
| M8 Polish | Accessibility, empty states, and polish of the recovery flows built in M1 and M3 | No open issue blocks daily use |

**M0 decision gates**

All five gates passed on 4 November 2026. The evidence, and what was left unmeasured, is in `Spikes/GarminPull/RESULTS.md` and `Spikes/Flyover/RESULTS.md`.

The flyover gates ran on the iPhone 18 Pro Max. They call for three representative routes: a long hilly ride, a short urban ride and a walk under tree cover. The routes to hand were a 1.6-hour rolling ride, a 10-hour walk beside buildings and a short walk in the open, so the terrain result is weaker than intended.

| Question | Passes when | If it fails | Result |
| --- | --- | --- | --- |
| Does the Personal API return the original file with per-second power, heart rate and GPS? | A ride from the Garmin computer downloads with all three channels intact | File import becomes the main path for rides; the API is used for listing and summaries | Passed. The download is the original file, byte for byte, with every channel. |
| How deep is the history, and what are the rate limits? | Full history lists and downloads, or the limits are measured and written down | Backfill from a Garmin data export; throttle sync to the measured limit | Passed. History listed back to 7 September 2019, the earliest activity Garmin returned, and that file downloaded. No limit was signalled at 11 requests 3 seconds apart, so the real limit is still unknown and sync stays paced. |
| Do Zwift rides appear in the Personal API? | A Zwift ride is listed and its file downloads | Zwift rides come from file import or Apple Health | Passed. Zwift rides are listed as virtual rides and download as the original file. |
| Does a coloured route sit correctly on realistic 3D terrain? | The line follows the ground on the hilly and urban routes, with no floating or buried stretches | Use a pitched camera over satellite imagery without realistic elevation. If that reads poorly, evaluate another map renderer before M2 starts. | Passed by eye on the rolling ride and beside buildings. Not yet checked on steep ground. |
| Does the coloured route hold frame rate while scrubbing? | 60 frames per second on the long ride, with imagery loaded | One line per zone band and stronger simplification, then fewer drawn vertices until it holds | Passed. 60 frames per second on the ride and on the 10-hour walk at 2 m simplification, up to 1,548 drawn vertices. A 5-hour ride and dimming ahead of the marker are not yet measured. |

One line per zone band was the fallback for frame rate, and it is now the default for a different reason. Both drawings held 60 frames per second, and band runs put every colour edge exactly where the data says. Stronger simplification and fewer drawn vertices remain the fallback if a longer ride misses the target. None of this affects terrain placement, which is why the two are separate gates.

## Risks and open questions

The two largest risks were what Garmin's Personal tier really returns and how well MapKit draws a coloured route on 3D terrain. Both were tested in M0 and passed, with the limits noted in the table. FIT import keeps the app useful if Garmin changes.

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Garmin starts stripping fields from downloads, as press reports said it might | Missing channels in synced rides | M0 found the download identical to the original, with every channel; fall back to file import from the device or a Garmin data export if that changes |
| Garmin does not document Personal-tier rate limits, and M0 met none at a low request rate | A backfill or deep scan is throttled part-way | Paced requests that stop on the first refusal and wait as long as Garmin says; resumable backfill; bulk import of a Garmin data export |
| Garmin's endpoints behave differently from the published reference | Sync rules need rework | M0 confirmed listing, paging, sorting and download with a live key, and the differences it found are in this spec. Behaviour when activities are edited or deleted at Garmin is first seen in M3. |
| Garmin changes terms or adds fees | Sync stops | Sources sit behind one protocol; import always works; originals are already stored |
| Keys expire and tokens last 24 hours | Sync silently stops | Expiry warning and a clear re-entry flow |
| The Garmin FIT SDK licence grants use for internal purposes and limits redistribution | A blocker if the app is ever distributed | Fine for personal use; read the licence in full, or write a decoder, before distributing |
| Apple's App Review rules bar storing personal health information in iCloud | A blocker for iCloud storage if the app is ever distributed | Not enforced on a personal build; Health data is kept out of iCloud; decide how Garmin heart-rate data is treated before distributing |
| iCloud storage is full or unreachable | Originals exist on one device only | The app works offline; sync status shows what is not yet copied |
| A coloured route does not sit correctly on steep terrain | Flyover looks wrong | Passed in M0 on rolling ground and beside buildings; check a steep route in M2; the fourth gate's fallback still applies |
| A coloured route is slow on long rides, or when the part ahead of the marker is dimmed | Flyover stutters | Held 60 frames per second in M0 up to 1,548 drawn vertices; measure a 5-hour ride and dimming in M2; the fifth gate's fallback still applies |
| Detailed 3D imagery covers only some regions | Flat-looking flyover elsewhere | Terrain elevation still applies; standard map toggle |
| Health workouts from other apps lack routes or power | Thin detail screens | Show what exists; never invent data |
| Duplicate detection merges records that are not the same activity | Lost or distorted activities | Strict automatic rule; anything ambiguous waits for review; originals are always preserved |
| GPS cannot separate two courses that run side by side | Different routes grouped together | Side-offset check; ambiguous cases go to manual review |
| Threshold power or threshold heart rate is wrong | Zones and load are wrong | Prompt at setup; suggest updates from history; corrections recompute the affected dates |

**Open questions**

- [ ] What do Garmin's Personal API terms, shown when a key is created, say about storage, including iCloud, and about AI processing?
- [ ] How much walking and running detail matters compared with cycling?
- [ ] Is 7 September 2019 the first activity on the Garmin account? It is the earliest one the API returned.
- [ ] Does Garmin's last-update date on an activity move when the activity is edited? If it does, a deep scan can use it to catch a changed file whose summary is unchanged.

Settled by the assumptions and removed from this list: personal use only, iPhone first, iOS 26, metric units by default, iCloud storage through CloudKit, the iPhone 18 Pro Max as the reference device, and SweatKit as the app name.

## Future improvements

These are deliberately outside the MVP. The architecture leaves room for each.

- **Fitness and fatigue modelling.** Long-term load trends such as fitness, fatigue and form. This is deferred because the model needs more design. It has to settle how the lines start, how incomplete history is told apart from the model's own slow response, and how activities with unavailable load are treated.
- **Route planning and course push.** Plan a route in the app and send it to Garmin Connect so it syncs to the bike computer. This needs Garmin's Courses API, which is in the Starter tier and not the Personal tier. A possible interim is exporting a course file to the Garmin Connect app, which is untested.
- **AI summaries.** A short written recap of each activity and each week, using Apple's Foundation Models on the device or on Private Cloud Compute. The numbers are computed in code and the model only words them. If the app is distributed, Garmin's terms require explicit, withdrawable consent before AI processing.
- **Search.** Plain-language questions over the library, such as "longest ride above 200 W this year".
- **Video export.** Render the flyover with its stats to a shareable video.
- **Partial efforts and shared sections.** Match an effort that covers only part of a route, and detect the same climb or stretch inside different rides. Both need a separate matching path and a rule for where the comparison clock starts.
- **Efficiency trend on foot.** Extend the efficiency trend to walks and runs once a steadiness rule exists for them.
- **More platforms.** iPad, Mac, Apple Watch and widgets.
- **Push sync.** Move to the Garmin Starter tier so new rides arrive without opening the app.

## Sources

Garmin's key, token, endpoint and tier details are from its official pages, opened on 4 November 2026, and were checked against a live key in M0 the same day. Tier pricing and the reports of stripped fields are from press coverage of the 21 October 2026 relaunch.

**Garmin, official**

- [Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/)
- [Personal API FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq/)
- [Personal API endpoint reference](https://developer.garmin.com/gc-developer-program/personal/swagger-docs/)
- [Connect Developer Program overview](https://developer.garmin.com/gc-developer-program/overview/)
- [FIT Swift SDK](https://github.com/garmin/fit-swift-sdk) and its [licence](https://github.com/garmin/fit-swift-sdk/blob/main/LICENSE.txt)

**Press**

- [DC Rainmaker: Garmin revamps and opens up Connect Developer API program](https://www.dcrainmaker.com/2026/10/garmin-connect-api-revamps-connect-developer.html)
- [the5krunner: Garmin Personal API key](https://the5krunner.com/2026/10/22/garmin-personal-api/)
- [Sahha: Garmin API access in 2026](https://sahha.ai/blog/garmin-connect-api-reopened-fees/)

**Apple, official**

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), section 5.1.3, on health information and iCloud

**Not yet read**

- Garmin's Personal API terms and conditions, which are shown when a key is created.
- Apple's guidance on [reading route data](https://developer.apple.com/documentation/healthkit/reading-route-data) and [background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), which the HealthKit and background-refresh rules here should be checked against.
- Apple's CloudKit sync engine documentation, which the iCloud design here should be checked against.
