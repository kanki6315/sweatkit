# Playback follow-up validation

Prepare a disposable app with `python3 Scripts/PlaybackValidation/prepare.py /tmp/sweatkit-playback-harness`, then generate its project with XcodeGen. Run the SweatKit scheme's UI tests on a simulator leased through Simlock, following `CLAUDE.md` and the installed Simlock instructions.

The harness uses production `ActivityDetailView` and unchanged `outdoor-ride.fit`, `walk.fit`, and `zwift-ride.fit`. It adds no synthetic activity or profile values and does not access the production library. The preparation helper reuses the route harness's project scaffolding only.

Checks cover overview finish, replay, pausing via chart scrubbing, switching from ride to walk at time zero, indoor playback without a map, and manual camera takeover/resume during playback, scrubbing while in manual mode, pinch and rotation. The camera check uses the standard-map option and 0.25× overview speed. Camera checks explicitly skip if MapKit stays on its route fallback. Screenshots are retained in the xcresult bundle. These are simulator checks, not TestFlight acceptance.

Physical-device acceptance still needs pinch, rotation and two-finger tilt, manual camera persistence while scrubbing, resume following, Reduce Motion, Dynamic Type, actual frame pacing, and the user's short/long/missing-route recordings. The available fixture set does not include an exactly 30-second activity, a no-stream recording, or a five-hour ride. Package tests cover mathematical short/long/empty boundaries without inventing recordings.
