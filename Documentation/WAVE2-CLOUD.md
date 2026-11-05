# Wave 2 — private iCloud second copy and recovery

Implemented 5 November 2026 on `codex/wave2-cloud`, starting at `0b1f05a` (verified with `git merge-base --is-ancestor 0b1f05a HEAD` before editing). No merge, push, release, container deployment or user-data upload was performed.

## Implementation and boundaries

- `SweatKitCloud` is a new leaf package depending only on Model. `PrivateCloudCopy` uses `CKSyncEngine` against the **private** database in `iCloud.com.arjunakankipati.sweatkit`, custom zone `SweatKitRecoveryV1`. SwiftData remains explicitly configured with `.none` for CloudKit mirroring. No shared schema migration is introduced.
- `CloudRecord` is the transport allowlist: originals, source metadata, Garmin source descriptors, links, activity decisions, tombstones, profile events and feature decision envelopes. Original record names hash the kind plus stable source identity and content hash. Identical imports therefore address identical original records. Automatic links retain the identity package's deterministic names; individual user decisions retain their original names.
- Source metadata is projected from `SourceRecord`, with `activityID` removed: source identity, source state, import date, current revision and revision descriptors. Mutable source/profile values are separate immutable events; latest event time, then record name, resolves concurrent updates. All source revisions are retained; the winning event chooses the current revision. Profile events preserve the complete user-entered threshold history; concurrent profile edits resolve as whole-profile last-writer-wins, not fieldwise merging.
- Garmin source metadata has a separate narrow projection: identity, source name/type/manufacturer and local UTC offset. Garmin summary measurements and the reconciliation checkpoint are not copied. The existing Garmin bridge records descriptor changes and the app's existing cache is bootstrapped read-only. A restored device rebuilds Garmin reconciliation state when it reconnects; credentials are never exported.
- CKAssets contain only validated Garmin/import bytes reached through a non-Health source revision. There is no directory upload. `library-backup.json` and `identity.json` are **not** copied wholesale. The existing manifest already excludes Health; the identity journal also contains matching candidates, so the new exporter reads only links, decisions and tombstones. Generated titles, locality caches, activity rows, streams, metrics, thumbnails, Health facts and credentials remain local.
- Health source UUIDs and explicit decisions/links/tombstones are permitted identity data. Health snapshots, samples, routes, summaries and matching candidates are absent from the transport. Re-reading a Health workout can reattach decisions by UUID. Cross-device Health UUID stability still requires live verification.

## Retry, recovery and deletion

`CloudTransport/` is excluded from OS backup. It holds immutable staged assets plus an atomic replica/engine-state checkpoint. Fetched assets and record envelopes reach disk before accepting the next engine state. A failed checkpoint blocks further token advancement and the next attempt reloads durable state. Invalid/corrupt records and checkpoints fail closed; they never silently reset the library. FIT decoding happens after fetch persistence, so a failed rebuild remains retryable. The app replays the durable inbox even if the send phase fails, so a quota error cannot hold back an already-fetched deletion.

Each explicit sync fetches remote tombstones before sending pending local work. A durable tombstone suppresses original/source-metadata uploads regardless of record arrival order or timestamps. Pending deletes replace queued saves. Successful saves alone increment confirmed counts; local staging never does. Immutable create/create conflicts accept identical server records, including the case where a conflict response omits an asset URL but intact local bytes exist. CloudKit owns operation batching; the SDK's pending-change batch initializer observes its request limit.

Recovery persists decisions before importing originals and uses the existing serialized library writer and identity resolver. Interrupted source recovery is marked durably so partially restored revisions cannot become newer local edits on restart. Local imports arriving during a fetch are preserved for the next copy. Originals are decoded again and derived results rebuilt. Permanent deletion also erases the transport's staged file copies while cloud networking is paused. Remote erasure remains pending until an enabled, successful sync; retained tombstones prevent later stale uploads from resurrecting an activity. Shared original bytes belonging to another surviving source remain available under that source's record.

The account's record ID is bound to the checkpoint. A different Apple account cannot receive this library. Signing back into the original account resumes it. No automatic migration to a different Apple account is offered.

## App and board 09

The existing Settings “Sync and storage” section now includes an iCloud summary row using `SettingsSummaryRow`. Its destination has opt-in/pause, actual status, pending-record count, last **confirmed** copy, “Sync and recover now,” and recovery/privacy scope. No successful timestamp or copied count is supplied by fixtures. Enabling the second copy is explicit; pausing retains the existing remote copy.

Foreground and existing background-refresh paths call the coordinator after source sync. A debounced refresh follows library reloads; changes arriving during a running copy request another pass. Settings dismissal reloads recovered activities. Existing navigation and `AppTheme` remain intact; Routes and Trends tab content is untouched.

The simulator intentionally reports that CloudKit requires the signed device build/container. This is a capability gate, not a simulated network/account/quota failure. Production CKError handling distinguishes unavailable account, quota, network, service throttling and signing/container errors; saved local activities remain usable.

### Capture evidence

Actual SwiftUI app captures, iPhone 18 Pro Max simulator, iOS 27.2, through an exclusively leased Simlock device. These used a **temporary navigation-only launch harness** around the real Settings and CloudSettings views; the harness was removed before the production build. No activity fixture, fake timestamp, count or success status was injected.

- [Settings light](Evidence/WAVE2-CLOUD/settings-light.png), [dark](Evidence/WAVE2-CLOUD/settings-dark.png)
- [Disabled/empty copy light](Evidence/WAVE2-CLOUD/cloud-disabled-light.png), [dark](Evidence/WAVE2-CLOUD/cloud-disabled-dark.png)
- [Real simulator capability error light](Evidence/WAVE2-CLOUD/cloud-error-light.png), [dark](Evidence/WAVE2-CLOUD/cloud-error-dark.png)
- [Largest accessibility text light](Evidence/WAVE2-CLOUD/cloud-error-large-light.png), [dark](Evidence/WAVE2-CLOUD/cloud-error-large-dark.png)

Visual inspection: the new iCloud row follows board 09's icon/title/detail/chevron hierarchy and native grouped surface. Native header spacing, the existing profile rows, Done control and source error text still differ from the illustrative board. The board's successful-copy numbers, threshold suggestion and deep-scan history are not fabricated. The new destination is a native Form extension, not an independently approved board. Large text wraps; content extends below the first viewport and requires scrolling. These captures do not certify tap/swipe navigation, VoiceOver traversal, lower-page scrolling, physical-device layout, account/quota UI under real errors, or full board parity. Approved boards were not changed.

Impeccable context and hardening/craft guidance were applied; its mechanical detector returned `[]` for the changed SwiftUI views. PRODUCT.md has legacy Impeccable metadata; migration was intentionally outside this feature.

## Contracts for integration

1. **Model addition:** `CloudDecisionEnvelope` carries an immutable UUID, namespace, payload version, action time, device identifier and opaque `Data`. Cloud retains unknown versions. Routes should call `await library.appendCloudDecision(envelope)` after a durable explicit user action and read `library.cloudDecisions(namespace:)` to replay supported versions deterministically. Use route names, stable effort/source identifiers and manual decision parameters only. Never encode a route/model wholesale, coordinates derived from Health, cached matching results, alignments or computed metrics. A route payload codec/privacy audit and replay integration belong to Routes; no peer-private type was guessed here. If a manual edit needs geometry, define an approved non-Health/user-authored boundary before wiring it.
2. **Library:** `cloudExport`, `cloudOriginal`, `cloudRestore` are additive. Restore's asset provider supplies hash-validated originals. Its journal preserves opaque future decisions and profile/source events independently of local caches. Existing writer/journal helpers became module-internal solely to support the feature extension; `importBytes(alreadyLocked:)` avoids recursive writer acquisition. Profile writes join that same writer so recovery cannot race a save.
3. **Garmin bridge:** `updateSummary` now also records the narrow cloud descriptor projection; no credential or Garmin summary measurement enters it. Remote permanent deletions remain pruned through the existing bridge's deletion cleanup on source sync/startup.
4. **App:** minimal stored `LibraryModel.cloud`, construction, reload scheduling; RootView changes only lifecycle sync. Existing Settings rows and feature tab content remain owned by their original features.
5. **Wiring:** `project.yml` adds the leaf package, remote-notification background mode and per-configuration APS environment. Entitlements add the explicit iCloud container and CloudKit service while preserving Health capabilities. Regenerate Xcode with `xcodegen generate` after integration.

## Validation

All logs below are local `/tmp` evidence, not files required by the app:

- Existing full Library suite: **119 tests passed**, including the 500-workout scale case, before the final additive recovery tests (`/tmp/sweatkit-cloud-library-tests.log`).
- Cloud reducer/disk suite: **7 tests passed** (`/tmp/sweatkit-cloud-final-transport.log`). Tests exercise restart, confirmation, stale upload/deletion ordering, shared-original retention, invalid Health assets, immutable collisions, unknown feature payloads and corrupt checkpoints without any CloudKit network calls.
- Focused Library deletion/backup/identity/recovery regressions: **21 tests passed** (`/tmp/sweatkit-cloud-final-library-tests.log`).
- Follow-up Garmin/profile/recovery regressions after metadata and interrupted-recovery work: **29 tests passed** (`/tmp/sweatkit-cloud-metadata-tests.log`).
- Completed recovery suite: **8 tests passed** (`/tmp/sweatkit-cloud-recovery-acceptance.log`). Covers actual FIT rebuild, profile and hidden decisions, Health locality/reattachment, stale deletion, concurrent imports/revisions, local import during fetch, interrupted recovery and Garmin source metadata.
- XcodeGen and unsigned simulator Debug app build passed (`/tmp/sweatkit-wave2-cloud-build.log`), followed by capture harness build (`/tmp/sweatkit-wave2-cloud-capture-build.log`).
- Production unsigned physical-iPhone Release build passed (`/tmp/sweatkit-wave2-cloud-device-build.log`, `/tmp/sweatkit-wave2-cloud-final-build.log`, `/tmp/sweatkit-wave2-cloud-verified-build.log`). Separate derived-data directories were used for simulator and physical-device builds.
- Diff whitespace validation passed. Package tests are **not** device acceptance, and reducer/disk tests do **not** prove Apple's live transport behavior.

## Required provisioning and live acceptance

Configured bundle: `com.arjunakankipati.sweatkit`; team: `TDBAHN96B3`; container: `iCloud.com.arjunakankipati.sweatkit`. Fifteen installed provisioning profiles were decoded read-only; none explicitly targeted SweatKit. This task did not verify or create the container in the developer portal, modify provisioning, deploy its schema, sign into an Apple account, archive, release or upload private data.

Before accepting M4:

1. Enable the explicit container/CloudKit and push capabilities for the app ID; generate matching development/distribution profiles. Confirm the `RecoveryRecord` type has `envelope` Bytes and `original` Asset in the private custom zone; validate in development before any production schema deployment. Keep Health capabilities intact.
2. On signed devices with an approved test-only dataset/account, verify initial copy, actual server acknowledgement counts, quota/network/account-unavailable retries, account switching refusal and return to the original account. Check CloudKit Console to confirm the allowlist and absence of Health facts/credentials.
3. Two devices: concurrently import the same original, rename/hide/split/merge, edit profiles and revise an original; let both converge. Delete while the other is offline, then reconnect it. Confirm durable tombstones win and assets are actually removed from CloudKit. Repeat with shared bytes owned by two surviving source identities.
4. Wiped-device restore from iCloud: all permitted originals/revisions, metadata, profile and decisions must recover and recompute. Interrupt fetch, asset persistence, decoding and deletion, relaunch and retry. Measure throughput/memory with the real library; per-record checkpoint writes are deliberately conservative and not yet scale-certified over CloudKit.
5. Reconnect Apple Health; verify workout UUID identity across both devices and decision reattachment. Confirm the documented loss of deleted Health-only workouts. Validate the final integrated Routes decision codec before enabling its export.
6. Exercise navigation, largest text including scrolling to lower controls, VoiceOver, contrast/transparency settings and light/dark on the signed reference phone. Background refresh is opportunistic; there is no claim of real-time push delivery in this implementation.

API implementation references: [Apple CKSyncEngine](https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5) and [CKSyncEngineDelegate](https://developer.apple.com/documentation/cloudkit/cksyncenginedelegate-1q7g8). Delegate events never call fetch/send recursively.
