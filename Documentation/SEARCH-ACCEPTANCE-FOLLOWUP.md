# Search acceptance follow-up

Target: TestFlight 0.1.0 (310.22.2). Branch: `codex/search-acceptance`.

## Implemented

The user selected integration into Activities. `App/RootView.swift` now has three tabs: Activities, Routes, and Trends. Native toolbar title search binds to the existing `feedFilters.search` in Activities, with one feed and one navigation history. The duplicate Search tab and its automatic presentation state are removed.

`.scrollDismissesKeyboard(.immediately)` now applies to the Activities feed. A scroll gesture requests native keyboard dismissal even with an empty query, without explicitly clearing search or filters. Sport/date/setting controls, query construction, route thumbnails, MapKit, and feed rendering are unchanged. `App/ActivityFeedView.swift` has only a documentation-comment update to describe the integrated filter state.

There are no unresolved product inputs. Real-device interaction acceptance remains pending.

## Verification

- `swiftc -frontend -parse App/RootView.swift`: passed (syntax only, not an iOS build).
- `git diff --check`: passed.
- Existing Store feed checks: **8 tests passed**, including combined title/sport/date/setting filters and pagination (`swift test --disable-sandbox --package-path Packages/SweatKitStore --scratch-path /tmp/sweatkit-search-store-build --filter FeedTests`, with module caches redirected to `/tmp`). Local log: `/tmp/sweatkit-search-store-tests.log`. CoreData emitted sandbox notification-registration warnings; the suite completed successfully. These tests do not exercise keyboard gestures or UI filter bindings.
- Debug iOS Simulator build passed after XcodeGen generation; log: `/tmp/sweatkit-search-ios-build.log`.
- Simlock identity succeeded with elevated sandbox access. Exclusively leased iPhone 17 / iOS 27.2 (`lse_3f3e0846-6185-48d5-9057-0e489ae79ba3`), installed and launched the production build, and inspected [the empty-library capture](Evidence/SEARCH-ACCEPTANCE/activities-integrated.png). It confirms the native title-search field under Activities and the three-tab layout. No activity data was fabricated or imported. The lease was released afterward.
- This capture does not verify keyboard gestures, populated results, dark appearance, Dynamic Type, or signed-device behavior. No real phone was accessed.

## Required real-device acceptance

1. Open Activities, activate title search with an empty field and keyboard visible. Drag the list up and down; keyboard should dismiss without pressing Search.
2. Type part of a real activity title, scroll, and confirm the query and matching results remain.
3. Combine title query with sport, indoor/outdoor, and date filters. Dismiss the keyboard, change each filter, and confirm query preservation and correct results.
4. Check no-results and short-result lists, clear/reset, reopening the keyboard, switching tabs, and opening/backing out of an activity.
5. Confirm only Activities, Routes, and Trends appear as tabs; title search is discoverable within Activities. Check light/dark appearance and accessibility text sizes.

Code checks do not certify TestFlight acceptance. No release, upload, merge, new fixture data, or re-certification of other acceptance areas is part of this change.
