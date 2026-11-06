# Search acceptance follow-up

Target: TestFlight 0.1.0 (310.22.2). Branch: `codex/search-acceptance`.

## Implemented

`App/RootView.swift` applies `.scrollDismissesKeyboard(.immediately)` to the Search feed. A scroll gesture requests native keyboard dismissal even when the search field is empty. This modifier does not clear the query, dismiss the search presentation explicitly, or change filters. Activities, route thumbnails, MapKit, and shared feed implementation are untouched.

## Pending product choice

The current Search tab renders another `ActivityFeedView`, sharing `ActivityFeedFilters` and `LibraryModel` with Activities. Consequently it repeats the Activities heading, weekly totals, status rows, and actions. The spec describes three tabs and title search as an Activities filter.

Two options have been presented for user selection; neither is implemented:

1. **Integrate into Activities (recommended):** keep Activities, Routes, and Trends; put native title search alongside the existing Activities filters. One feed and one navigation history.
2. **Distinct Search:** retain the Search tab with a Search heading, a title-search prompt before a query, and matching activities afterward. Preserve shared filters while removing duplicated feed framing from Search.

Await the user's choice before changing information architecture. Coordinate any later shared `ActivityFeedView.swift` edits with the Activities owner. This initial change touches only the Search branch of `RootView`.

## Verification

- `swiftc -frontend -parse App/RootView.swift`: passed (syntax only, not an iOS build).
- `git diff --check`: passed.
- Existing Store feed checks: **8 tests passed**, including combined title/sport/date/setting filters and pagination (`swift test --disable-sandbox --package-path Packages/SweatKitStore --scratch-path /tmp/sweatkit-search-store-build --filter FeedTests`, with module caches redirected to `/tmp`). Local log: `/tmp/sweatkit-search-store-tests.log`. CoreData emitted sandbox notification-registration warnings; the suite completed successfully. These tests do not exercise keyboard gestures or UI filter bindings.
- Simlock identity check returned `connect EPERM` for its daemon socket under the sandbox. No simulator or phone was accessed, and no gesture or rendered UI result is claimed.

## Required real-device acceptance

1. Open Search with an empty field and keyboard visible. Drag the list up and down; keyboard should dismiss without pressing Search.
2. Type part of a real activity title, scroll, and confirm the query and matching results remain.
3. Combine title query with sport, indoor/outdoor, and date filters. Dismiss the keyboard, change each filter, and confirm query preservation and correct results.
4. Check no-results and short-result lists, clear/reset, reopening the keyboard, switching tabs, and opening/backing out of an activity.
5. After the product choice is implemented, confirm the agreed integrated or distinct presentation.

Code checks do not certify TestFlight acceptance. No release, upload, merge, new fixture data, or re-certification of other acceptance areas is part of this change.
