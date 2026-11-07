# Activity background validation

The production activity feed uses OpenFreeMap vector tiles and MapLibre Native
7.0.0 to generate static route previews. MapKit still owns the detail flyover,
route inspection/comparison maps and route-library maps.

## Caching and provider limits

- Completed light/dark and compact/large previews live in the library thumbnail
  directory, excluded from backup. Reads update recency; successful map writes
  trim PNGs to 100 MiB. Writes use the store's existing live-revision check and
  permanent-deletion lifecycle, so a late render cannot resurrect deleted data.
- Route-only fallbacks have a separate key and never count as completed maps.
- MapLibre offline packs retain tiles, style JSON, glyphs and sprites in its
  shared SQLite database. Packs cover the overview and adjacent zoom levels.
  Overlapping packs share resources. Each appearance is acquired on demand;
  an appearance not yet downloaded still needs network access initially.
- LRU eviction retains at most 64 packs and reserves 48 MB for an incoming pack
  within a 256 MiB logical resource budget. The ambient cache adds 32 MiB.
  SQLite allocation can exceed live-resource sizes. Incomplete packs reserve
  their full budget; failed/cancelled downloads are removed.
- A shared URLProtocol transport limits actual in-flight requests to four,
  including HTTP/2, and identifies SweatKit in its User-Agent. Each serialized
  job stops accepting resources after 2,800 requests or 48 MB, below the
  provider's published 3,000-tile/50-MB limits. Snapshot jobs time out and retry
  on a later visit; map failure preserves the local route preview.
- Attribution links are displayed on the activity feed; snapshots are internal
  previews and disable MapLibre's attribution that would be illegible at 68pt.
  Any future export must include attribution in the exported artifact.

Provider policy: https://openfreemap.org/quick_start/

## Repeatable offline test

Run `simlock whoami`, `simlock instructions`, and `simlock catalog`; lease an iOS
simulator according to those instructions. No raw simctl commands.

```
python3 Scripts/MapPreviewValidation/prepare.py /tmp/sweatkit-map-validation
xcodegen generate --spec /tmp/sweatkit-map-validation/project.yml
```

Run the generated `MapPreviewHarness` scheme's tests using the leased device.
With Xcode 27+, pass `-DVTSimulatorSetLocation=<grant's device set>` and
`-destination 'platform=iOS Simulator,id=<leased UDID>'` to xcodebuild.

Run the same tests **twice** without uninstalling the harness. The first run
fetches light/dark resources, blocks network at the SDK transport boundary,
and renders fresh images at a different size. The second process starts with
network blocked and renders from the persisted offline database. A marker in
the harness Documents directory selects that second phase. Uninstall only this
harness from your leased simulator to repeat a cold first run.

The tests check image dimensions, coordinate projection, nonempty rendered
content, completed offline packs, no successful network requests while offline,
and image-cache LRU eviction across cache-object recreation. The PNGs are
written to the harness Documents/MapPreviewValidation directory for visual QA.

## Feed integration

```
python3 Scripts/MapPreviewValidation/prepare_feed.py /tmp/sweatkit-map-feed
xcodegen generate --spec /tmp/sweatkit-map-feed/project.yml
```

Run that project's `SweatKit` scheme tests on the leased simulator. It uses the
production feed and synthetic outdoor routes, captures the cached preview, opens
MapKit detail, and returns to the feed.

## Verified 2026-11-07

- App simulator build passed (arm64 and x86_64).
- Cold download + offline regeneration: 304 online requests, zero requests
  attempted during offline rendering; light and dark snapshots passed.
- Separate-process offline regeneration: zero online or blocked requests;
  both snapshots completed in 0.46 seconds on the simulator.
- Image cache LRU/recreation test passed.
- Light/dark map snapshots visually inspected; streets, parks and labels render.
- Production feed UI test passed: prominent and compact previews render, detail
  opens, and returning to the feed succeeds. The composed route previews were
  verified on disk and the feed screenshot was visually inspected.

These timings are simulator observations, not device performance guarantees.
