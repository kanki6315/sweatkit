# Local Health storage and non-Health recovery

The library keeps Health-derived values outside the OS-backup-eligible part of its directory. It does not exclude the entire library root.

| Location | Backup policy | Contents |
| --- | --- | --- |
| `Originals/` | Eligible | Garmin and imported original files, byte for byte |
| `library-backup.json` | Eligible | Non-Health source identities, ordered revision hashes/dates, current revision, state, and the user-entered athlete profile |
| `identity.json` | Eligible | User decisions, links, tombstones, and non-Health matching candidates |
| `LocalMetadata/` | Excluded before opening SQLite | Shared SwiftData database, WAL/SHM and external payloads, including resolved feed rows and metrics that may come from a Health primary |
| `HealthOriginals/` | Excluded before writing | Versioned Health workout snapshots |
| `HealthMetadata/` | Excluded before writing | Health matching candidates (sport, start, elapsed time and distance) |
| `Streams/`, `Thumbnails/`, `Localities/` | Excluded | Rebuildable decoded streams, analysis streams and display caches |
| `health-sync.json` | Individually excluded | Health anchors, known workout intervals and pending snapshot IDs; replacements are staged in an excluded directory and flagged before atomic rename |

A backup restore has no `LocalMetadata` database. The store replays `library-backup.json`, then the library rebuilds feed rows and metrics from preserved originals and applies the identity decisions. Health records are read again from HealthKit and their decisions reattach by workout UUID. A Health-only workout that has disappeared from HealthKit cannot be recovered from this backup, as specified in the MVP contract.

The manifest is committed before durable source/profile metadata changes. A generation marker inside the excluded metadata directory records completion of the database save. If a process exits between those writes, the next open replays the manifest before exposing the store. Cached rows and metrics do not change the recovery input. Invalid manifests fail explicitly; they never silently reset the library.

The legacy mixed database migration first copies SQLite components into the excluded directory. A final marker distinguishes a complete copy from an interrupted one. The old files are removed only after opening the copied database and committing the non-Health recovery manifest. Legacy Health snapshots and matching candidates are moved into their excluded locations. This cannot remove data from backups made by older versions.

`BackupIsolationTests` verifies a restore with only eligible files, all non-Health revisions and the profile, preserved title/visibility decisions, fallback from an unavailable Health primary, later reattachment of Health, migration of the old layout, interrupted-generation replay, exclusion attributes and rejection of corrupt manifests. These are filesystem/host tests, not an actual device-backup or iCloud restore certification. CloudKit replication remains M4 work.

## Persistent trend caches

`LocalMetadata/TrendsCache/` holds one compact history snapshot and at most twelve
chart presentations. It inherits LocalMetadata's backup exclusion and is never
part of cloud recovery. Files are atomic, disposable JSON payloads; missing or
undecodable payloads are rebuilt. History keys include the pipeline and cache
schema versions. Presentation keys include the history snapshot, filters,
calendar/timezone, schema version, and minute of calculation, preserving the
existing one-minute freshness policy for rolling date windows.

Store input mutations remove this directory before changing metadata. A new
persistent generation prevents in-flight calculations from writing old results
back after an edit or deletion. Recovery replay also clears the cache. Per-ride
power-curve writes do not invalidate it, because they are derived cache outputs.
The full history snapshot remains reusable across restarts until input data or
algorithm versions change; chart presentations remain subject to time expiry.
