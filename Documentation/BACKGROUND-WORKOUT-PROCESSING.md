# Background workout processing

Manual Health and Garmin syncs, including initial connection and full Garmin history scans,
and FIT file imports request iOS 26 continued processing. Their tasks belong to the model,
not to a SwiftUI view. Switching apps does not cancel them. iOS shows workout progress and
can expire or cancel the request; the worker then stops cooperatively.

Requests use unique identifiers under the permitted `workout.*` namespace. Immediate
submission is used because the operation has already started. A finite UIKit background
assertion covers launch latency or refusal. Finishing before launch cancels the request;
a late callback cannot attach to a later operation. Completion and expiration release
background assertions exactly once.

Automatic activation syncs use finite background time without showing a continued-task
Live Activity. Health observer delivery keeps its existing 20-second background budget.
A waiting observer can expire without cancelling an operation owned by another caller.

The separately registered processing task resumes Health pending snapshots and Garmin's
routine history/checkpoint pass. It schedules its next opportunity before starting, and
propagates expiration to work it owns. iOS controls when it runs. It does not request Health
permissions or replace the user's Garmin credentials. Protected Health data and credentials
may be unavailable while locked; existing failure paths retain saved progress for retry.

FIT imports keep their security-scoped URLs while the process is alive. Unfinished files
are not a durable import queue across process termination: reselect those original files.
Health and Garmin work, by contrast, resumes from the existing on-disk checkpoints.

## Device acceptance checks (not yet performed)

Use a physical iPhone on iOS 26 or later; simulator scheduling does not prove background
execution. Follow Simlock before using a test phone.

1. Start a sizable Health import, Garmin history sync, and FIT batch separately. Switch
   apps while each is running. Confirm system progress advances, then reopen and check
   completed workouts and no duplicate activities.
2. Cancel the system progress activity. Confirm processing stops, saved workouts remain,
   and a later Health/Garmin refresh resumes from checkpoints.
3. Exercise immediate request refusal (for example, under system resource pressure).
   Confirm foreground processing still works and finite background expiration saves
   partial progress without leaving a stuck running state.
4. Finish a tiny import before the continued-task launch callback. Start another import;
   confirm the previous request does not cancel or complete the new one.
5. Deliver a Health observer notification during a manual Health sync and background the
   app. Confirm the observer's deadline does not cancel the manual operation.
6. Launch the registered processing task through Xcode's background-task diagnostics,
   then trigger expiration. Confirm completion reports failure, work stops, and the next
   run resumes. Also verify success and disabled-source paths.
7. Lock the phone during Health processing; verify unavailable protected data is retried
   after unlocking without treating it as a deletion or a permission denial.
8. Terminate/relaunch after partial Health/Garmin processing. Confirm durable recovery.
   For a FIT batch, confirm completed files remain and reimporting originals is safe.
