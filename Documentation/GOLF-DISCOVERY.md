# Golf enrichment discovery — HealthKit only

Discovery date: 6 November 2026. Acceptance reference: TestFlight 0.1.0 (310.22.2).

## Decision and evidence boundary

The user clarified: **“I only want to use healthkit data here.”** No Arccos account, export, API integration, new subscription or credential work is in scope.

Recommend a modest Health-backed round summary first: recorded date/time, duration, source, and distance when supplied; add heart-rate detail and a route only after inspecting a representative round. Do not infer scores, hole boundaries, shots, clubs, course names, walking versus cart travel, or pace of play from workout duration/GPS. A workout path is not a ball-flight or shot map.

This is a discovery deliverable, not a UI implementation or TestFlight acceptance result. No real golf workout, Health snapshot, metadata dictionary or associated sample set was supplied. The repository's four real fixtures are cycling and walking FIT files. Actual golf values and sample availability remain unknown.

The starting checkout is `fd7bd09` and does **not** contain the reported accepted Golf behavior: `Sport` has no golf case and the Health adapter maps golf to `.other`. Searching local commit subjects for golf found no matching commit. Identify the accepted baseline before any runtime edits; do not recreate or overwrite the label/duplicate fixes from this older checkout.

## Current import and presentation audit

| Area | Verified behavior in this checkout | Implication |
| --- | --- | --- |
| `App/HealthConnection.swift`, `snapshot` | Retains workout UUID, source name/bundle, start/end, duration, stated total distance, timezone offset and indoor flag | Basic record context exists; totals are not per-second samples |
| Same adapter | Uses workout-associated quantities restricted to the workout's writing source | An overlapping Watch HR sample is not automatically part of an Arccos-written workout; do not silently widen provenance |
| Same adapter | Queries routes for the workout regardless of sport; retains valid positions, altitude and speed | A readable route could already be stored even when summary-only UI hides it |
| Same adapter | Queries heart rate; walking/running distance and steps are gated to `.onFoot` | Golf mapped to `.other` skips distance/step samples; do not change sport family just to enable queries, because matching also uses that family |
| Same adapter | Retains pause/resume events, laps and segments | These are source intervals, not proven golf holes |
| `HealthSnapshot.swift` | Stores normalized activity and source identifiers, not the entire raw metadata dictionary | Arbitrary course/round metadata cannot be recovered from the saved snapshot; a fresh Health read would be needed |
| `App/ActivityDetailView.swift` | `summaryOnly` is true for unsupported sports even with native samples | Limited display does not prove the source lacked a route/HR |
| `HealthConnection.observedTypes` | Already requests workouts, routes, HR, steps and walking/running distance; active energy is absent | First pass can use existing access. Adding an active-energy sample query would explicitly expand read permissions and is not proposed now |

Read alongside `CLAUDE.md`, `PRODUCT.md`, `DESIGN.md`, the MVP spec's Health import/identity rules, `Documentation/WAVE1-SOURCE-ACCURACY.md`, `Documentation/HEALTH-STORAGE.md`, and `Fixtures/README.md`.

## Official availability versus actual data

- Apple defines a [golf workout activity type](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/golf). It identifies the activity; it does not establish a scorecard schema.
- Apple documents [reading routes associated with workouts](https://developer.apple.com/documentation/healthkit/reading-route-data). This is a supported path when the writer saved a route and Health makes it readable. No route has been verified for this user's round.
- Apple's [workout metadata keys](https://developer.apple.com/documentation/healthkit/workout-metadata-keys) include workout brand, indoor status and other workout context. The reviewed documentation does not establish standard score, hole or shot fields. Custom metadata must be inspected and its semantics confirmed before adding a typed allowlist; do not dump arbitrary metadata into logs or UI.
- Initial research, now outside the chosen scope: Arccos publishes an [On-Course Data API](https://api.arccosgolf.com/swagger) with rounds, round stats, courses and clubs, but explicitly restricts access to issued clients and OAuth authorization. Its [access form](https://payment.api.arccosgolf.com/) requires licensee information and agreement. This proves a supported restricted API exists, not that the user or SweatKit has access. No reliable official general-purpose personal export format or Arccos-to-Health scorecard contract was verified. Do not use unofficial authentication clients or scraping as a substitute.

## Next implementation decision

1. Identify the accepted Golf baseline and one representative round's date/time and recording source/device.
2. With that round available locally, inspect only its workout properties, metadata keys/value types, route count, and workout-associated sample counts/time coverage. Compare visible source fields against the saved snapshot. Keep private records out of committed fixtures and logs unless separately authorized.
3. If route/HR already exist, propose exposing that existing data for Golf while preserving its sport identity and duplicate behavior. Do not enable generic full-sport support merely to bypass summary-only presentation; that can expose unrelated metrics and routing behavior.
4. If useful values exist only in metadata, propose additive typed fields with provenance, backward-compatible snapshot decoding, adapter-version refresh and Health backup isolation. Model changes need explicit handoff. If the source only supplies duration, retain a truthful compact summary.
5. Obtain product input before a dedicated golf detail layout or broader model changes. Use Impeccable for subsequent UI work. No UI was produced in this discovery pass.

## Verification and remaining acceptance

Code inspection establishes import gates and the summary-only gate; official-source research establishes available contracts. This documentation-only change requires a diff/whitespace check, not simulator or package execution. No Health permissions, source matching, app code, models or fixtures changed. No simulator/device was used; use Simlock before later device work.

Pending inputs: accepted Golf commit/branch; representative round date/time and source/device. Arccos access is no longer an input.

On the accepted real-device build: compare the selected round with Health; record which properties, metadata and associated channels actually exist; verify Golf labels and absence of false duplicate suggestions after refresh/relaunch; ensure missing values stay unavailable and Health-derived additions remain excluded from backup. These checks are unperformed. Search, routes, trends, playback, metrics, MapKit performance and iCloud are outside this change. No release/upload or merge is included.

## Recovered release baseline

The accepted fixes were found in the uncommitted working tree at `/Users/arjunakankipati/.codex/worktrees/3bb8/sweatkit` (HEAD `3b7b61e`). Its `build/release/0.1.0-310.22.2` contains the archive and `export-retry.log`, ending in upload success on 6 November 2026. The first export failed; the retry succeeded. There is no clean release commit to cherry-pick. The current working copy is recovery evidence, not a byte-for-byte source manifest of the archived binary.

Earlier searches incorrectly treated absence of a Golf enum as absence of the fix. The actual fix keeps `.other` for matching and adds `sourceSportName` to Health snapshots and Store V2. Focused copies of that implementation, migration tests and adjacent-session identity tests are recovered here. Only the Golf-label hunk is taken from each of HealthConnection and ActivityFeedView; unrelated sync, feed, route, trends and playback edits stay in their owning worktrees. The original worktree remains untouched. No further baseline input is needed.
