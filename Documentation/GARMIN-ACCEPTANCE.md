# Garmin M3 implementation evidence

The app now runs a foreground routine reconciliation on launch/return to active, and retains pull-to-refresh. The planner decides whether backfill or the weekly deep scan is owed. Settings can request full history with every original downloaded again; normal sync resumes its saved pass after interruption. Unchanged hashes retain one revision.

An optional `BGAppRefreshTask` requests quick sync only, with a 15-minute earliest scheduling date. iOS decides whether and when it runs. SwiftUI task cancellation propagates to the planner; foreground sync remains the reliable path. The app declares the task identifier and `fetch` background mode. No background delivery has been observed on a phone.

Garmin setup accepts the key's creation date and 30/90/180-day or one-year period. The estimate warns seven days before expiry and after the entered period ends. It never claims Garmin supplied an expiry date or refuses to try merely because the estimate elapsed. Key, lifetime and refusal state live in one device-only Keychain item. Legacy plain keys remain readable with unknown expiry. A refused key stops automatic retries until replaced; failed replacement preserves the previous credential. A protected Keychain read is retried on the next foreground sync.

## Automated evidence

- `GarminKeyLifetime` tests pin all four periods, the seven-day boundary, expiry boundary and coding round trip.
- `GarminJourneyTests` runs the real planner, ZIP reader, FIT decoder, ActivityLibrary, persistent adapter and disk store with scripted remote responses. Four tests pass:
  - week-late uploads arrive through quick sync; months-late uploads arrive through the next deep scan; restart and repeats preserve three distinct activities and single revisions;
  - a failed backfill keeps completed months; restart finishes it; failed listings infer no removal; later stable listings mark removal while retaining originals and feed rows;
  - actual task cancellation between history listings preserves completed months and resumes after reopening storage;
  - an insertion and deletion between overlapping pages settles with every surviving identity and no duplicate revisions.
- Targeted journey log: `/private/tmp/sweatkit-garmin-journeys.log` (local, ephemeral).
- Full affected suites passed: **39 Sync tests and 84 Library tests**, `/private/tmp/sweatkit-garmin-final-tests.log`. The unsigned generic iPhone Release build passed, `/private/tmp/sweatkit-garmin-final-build.log`; the built plist contains the permitted refresh identifier and `fetch` mode. No simulator/device interaction was performed by this workstream.

## Still requires interactive/live verification

Exercise launch, foreground/background transitions, pause/resume, and full reconciliation. Verify Keychain migration and locked-device retry, invalid replacement preserving the old key, refusal surviving relaunch, all expiry form options and reminder readability. Test actual key/token/rate-limit failures with user-supplied credentials. Check BGAppRefresh expiration cancellation when iOS grants background time. Confirm Dynamic Type/VoiceOver and layout in Settings and the feed. These are not certified by the passing package tests or compiler.
