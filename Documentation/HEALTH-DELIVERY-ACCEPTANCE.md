# Health foreground and background delivery

Implemented, not device-verified. Health refresh now runs alongside Garmin on foreground activation and during optional app refresh, after the user has requested Health reads. It does not request permissions automatically.

`SweatKitAppDelegate` installs `HKObserverQuery` instances before returning from launch, so a HealthKit wake does not depend on an active SwiftUI scene. Observed types match the read authorization set: workouts, workout routes, heart rate, cycling power/cadence/speed, and running power/speed. Background delivery requests `.immediate`, which is an upper bound on notification frequency, not a scheduling promise. The background-delivery entitlement is declared.

Observer notifications are batched. An arrival during an existing Health pass waits for that pass, then runs another anchored fetch so a type already read is not accidentally skipped. Once all queried anchors and pending snapshot IDs are saved, HealthKit completions are released before costly snapshot derivation. On a failed or cancelled fetch, existing anchors and any saved pending IDs remain intact and foreground activation retries them; acknowledging the notification does not claim a successful import. Error notifications are acknowledged and surface a foreground-recovery message.

Observer work requests ordinary UIKit background time and has a 20-second cancellation deadline when the app is not active. A foreground import is allowed to finish; UIKit expiration still governs later background time. Expiration and user pause cancel active Health queries; completions are exactly-once, including late/duplicate paths. Work that was already captured remains pending for the next foreground pass. iOS can defer delivery, withhold background time or suspend the app; none of these is evidence that a read permission was denied.

## Evidence

- Installed iPhoneOS27.2 SDK headers read: `HKHealthStore.h` (background activation still requires observer queries and corresponding fetches) and `HKObserverQuery.h` (completion after processing a delivery).
- Primary documentation: [HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery) and [Executing observer queries](https://developer.apple.com/fr/documentation/healthkit/executing-observer-queries).
- `swiftc -swift-version 6 -parse-as-library App/HealthDeliveryCompletion.swift Scripts/check-health-delivery.swift -o /private/tmp/check-health-delivery` followed by the executable passes 100 races with 100 concurrent callers each, plus reentrant completion, using the production callback wrapper.
- Unsigned generic iPhone Release build passed: `/private/tmp/sweatkit-health-delivery-final-build.log` (local, ephemeral). No simulator or phone access was performed by this workstream.
- Existing library tests cover durable anchors/pending snapshots and import/reimport/rebuild. The new iOS observer lifecycle itself has not been exercised by those host tests.

## Remaining checks

On a signed phone, confirm the provisioning profile includes HealthKit background delivery. Grant reads, relaunch, add a workout and delayed route/quantity samples while foregrounded and backgrounded. Confirm one activity, updated samples, saved-anchor recovery, and the feed refresh. Test permission revocation/review, device lock, background expiration, a notification arriving during an active refresh, and Pause stopping both foreground and observer work. Verify system throttling/failure messages do not claim permissions were granted or denied. No item in this paragraph is marked passed.
