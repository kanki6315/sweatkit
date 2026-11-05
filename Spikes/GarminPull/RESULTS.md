# Garmin Personal API spike: results

Milestone M0, the three Garmin gates from the spec's "M0 decision gates" table.

**Status: all three gates pass.** Live run on 4 November 2026 with the user's Personal API key: `swift run GarminPull gates`, 11 requests 3 seconds apart, after one earlier token request that got a 406 (difference 11 below). No request was rate limited.

## What is built

- `Packages/SweatKitGarmin` is the real client, kept whatever the gates decided: key-for-token exchange with renewal before expiry and one renewal on a 401, activity search by local start-date range with offset paging and sort order, activity summaries, original-file downloads as unopened bytes, and typed errors for a refused key, a refused fresh token, rate limiting, network failure and an unexpected response. It takes the key as a parameter and never logs the key or the token. The live run confirmed its request shapes, `Bearer` for data calls, and the response models. It is not yet in `project.yml`.
- `Spikes/GarminPull` is the throwaway probe on top of it.
- Not built yet: the sync depths, the month-by-month backfill and its two-listing check, a source-adapter protocol, storage and de-duplication. The gates passed, so these can now be designed as the spec describes, with the changes listed under "Effect on the spec".

## Gates

| Gate | Passes when | Result | Evidence | Decision |
| --- | --- | --- | --- | --- |
| 1. Does the Personal API return the original file with per-second power, heart rate and GPS? | A ride from the Garmin computer downloads with all three channels intact | **Pass.** The download is byte-for-byte the original FIT. | Activity 24172582403 downloads as `24172582403.zip` (245,305 bytes, `application/x-zip-compressed`) holding one file, `24172582403_ACTIVITY.fit`. Its SHA-256 is `d6050fe041a53669522e998ce32db3ca04df4d1837dff6f303600adef89561d7`, the same as `Fixtures/fit/outdoor-ride.fit`. Both have 877,925 bytes, 5,347 records, power on 5,337, heart rate on 5,347, position on 5,347 and 5,337 one-second steps. FIT integrity check passes. The summary says `isOriginal: true`, `fileFormat: fit`, `trimmed: false`. None of the reported stripping of fields shows up. | **The API is the sync path for rides.** The FIT inside the zip is the preserved original, and its hash is the revision hash. File import stays as the path for files that never reach Garmin. |
| 2. How deep is the history, and what are the rate limits? | Full history lists and downloads, or the limits are measured and written down | **Pass.** Full history lists and downloads. No limit was reached or signalled. | The ascending search returns activity 4034877128, a run on 7 September 2019. Its file downloads: a 10,193-byte zip holding a 21,353-byte FIT with 310 records, heart rate and position on all of them, and 48 one-second steps (the watch recorded in smart mode then). None of the 11 responses carried a rate-limit or `Retry-After` header. The headers present are standard HTTP ones plus Cloudflare's `cf-ray` and `cf-cache-status` (`out/requests.jsonl`). The newest page was full at 99 entries and reached back to 27 April 2026. The busiest month on it held 24 activities. | **Backfill uses the API, not a Garmin data export.** History goes back at least to September 2019; the user can say whether that is the account's first activity. Limits are written down as "none signalled at 11 requests, 3 s apart". The spec's fallback of throttling to a measured limit stays the plan: M3 keeps pacing, stops on the first 429, honours `Retry-After`, and resumes from checkpointed months, which the client's `rateLimited` error supports. Backfill size is about 87 monthly listings plus one download per activity, so at 3 s per request a backfill of a few hundred activities takes tens of minutes. Garmin's real limit for that load is first seen in M3's backfill. |
| 3. Do Zwift rides appear in the Personal API? | A Zwift ride is listed and its file downloads | **Pass.** | Activity 24906063494 is the newest entry and appears in its month's listing (October 2026, 3 activities) with `typeKey: virtual_ride` and `manufacturer: ZWIFT`. Its zip holds `24906063494_ACTIVITY.fit`, byte-for-byte `Fixtures/fit/zwift-ride.fit`: SHA-256 `324247fa61aa813a2542fc6691fef98293b6a04bc5b6094dc4784247cbccfcfe`, 266,547 bytes, sub-sport virtual activity, 2,409 records with power, heart rate and position on all of them. | **Zwift rides come through Garmin sync.** File import and Apple Health are not needed for them. `virtual_ride` in the listing, or the FIT's virtual-activity sub-sport, marks them for the charts-first detail screen. |

## Effect on the spec

These are proposed changes from the run and the docs, for whoever owns the spec. This spike does not edit it.

1. **Preserve and hash the inner file.** Downloads come as a zip. "Kept byte for byte" and "a changed file, by content hash" should name the FIT inside the zip. The zip's own bytes are not the original.
2. **Token handling.** The token is plain text with no stated lifetime. The client treats it as valid for the FAQ's 24 hours, renews it 5 minutes early, and renews once on a 401. Tokens also end when the key expires or is deleted, so a refused key means re-entering it, not just renewing the token.
3. **Month ranges are local-time months.** The search's `startDate` and `endDate` match `startTimeLocal`. Both month listings in the run held only activities whose local start date was in that month.
4. **Activity summaries have `lastUpdateDate`.** `GET /activity-service/activity/{id}` returned `lastUpdateDate` and `uploadedDate`; the listing has neither. This could narrow the spec's known limit for a file that changes while its summary stays the same, at one request per activity. Worth considering in M3; not needed for M0.

## Where Garmin's docs differ from the spec, or add to it

| # | Spec says | Garmin's docs say | Effect |
| --- | --- | --- | --- |
| 1 | Garmin provides "each activity file in its original format"; downloads are "kept byte for byte". | The download endpoint returns `application/x-zip-compressed`: the original file inside a zip. **Live:** confirmed. Each zip holds one file named `<id>_ACTIVITY.fit`, byte-identical to the original. | See "Effect on the spec" 1. |
| 2 | "Access tokens last 24 hours with no refresh token." | Tokens are valid "for 24 hours or until the Personal API key expires, whichever occurs first". Deleting a key also ends its tokens. | See "Effect on the spec" 2. |
| 3 | The app exchanges the key for a token and then calls the endpoints. | The token endpoint is on the Personal API page and FAQ but not in the OpenAPI document. Its response body is not documented anywhere. The OpenAPI document declares no security scheme. **Live:** the token is returned as `text/plain`, a 1,141-byte bare string with no lifetime, and data endpoints accept it as `Authorization: Bearer <token>`. | The client reads the body as the token and uses the documented 24-hour lifetime. |
| 4 | The search "filters only by activity start date and pages by offset"; history is walked in months of start dates. | `startDate` and `endDate` are inclusive and use the activity's **local** start date. The default sort is `startLocal`, descending. `start` is a zero-based offset. **Live:** confirmed for August and October 2026. | See "Effect on the spec" 3. |
| 5 | "A month rarely exceeds one page of 99." | The default `limit` is 99. No maximum is documented. **Live:** the busiest recent month held 24 activities. | Confirmed. No month in the run needed paging. |
| 6 | Not mentioned. | `excludeChildren` defaults to `true`: legs of a multisport activity are left out of the listing unless asked for. | A note for later. Rides and walks are rarely multisport. |
| 7 | A changed summary is detected by comparing listing entries. Known limit: a file that changes while the summary stays the same is missed. | The per-activity endpoint has `metadataDTO.lastUpdateDate`, `uploadedDate`, `isOriginal`, `fileFormat.formatKey` and `trimmed`. The listing entry has none of them. **Live:** all five were present. | See "Effect on the spec" 4. |
| 8 | Rate limits and history depth "are not documented". | Confirmed. Nothing on any of the three pages, and no `429` in the OpenAPI responses. **Live:** no rate-limit headers on any response. | See gate 2. |
| 9 | Keys expire after 30, 90 or 180 days or 1 year; Garmin emails a week before. | Confirmed. The key is shown once. Its status and expiry show on Garmin Connect on the web. | The app cannot read the key's expiry from the API. The user enters it, or the app counts from the period they chose. |
| 10 | Not mentioned. | The OpenAPI document lists a second server, `personal.connectapi.garmin.cn`. | Accounts in China use a different host. Not relevant to a personal build. |
| 11 | Not mentioned. | The documented curl command sends no `Accept` header. **Live:** the token endpoint answered `Accept: application/json` with `406 Not Acceptable`, because it serves `text/plain`. | The client sends `Accept: */*` to the token endpoint, as curl does. Data endpoints accept `application/json`. |

Listing entries (`SummarizedActivityDTO`) carried `activityId`, `startTimeLocal`, `startTimeGMT`, `endTimeGMT`, `beginTimestamp`, `duration`, `elapsedDuration`, `distance`, `activityType` and `manufacturer`, 96 fields in all. That is enough for the spec's de-duplication rule and revision triggers without fetching each activity, as the spec assumes. `manufacturer` can be null: it was absent on the 2019 run.

## Sync design checks

| Check | Result |
| --- | --- |
| Ascending sort with `limit=1` returns the earliest activity | Yes: 4034877128, 7 September 2019. |
| A month range returns that month's activities and nothing outside it | Yes, for August 2026 (19 activities) and October 2026 (3). |
| The token response's format and stated lifetime | Plain text, no lifetime stated. |
| Data endpoints accept `Authorization: Bearer` | Yes, every data call returned 200. |
| Whether `lastUpdateDate` is present and plausible | Present. For 24172582403, a ride on 26 August uploaded on 30 August, it is 2 seconds after `uploadedDate`. For the Zwift ride it equals `uploadedDate`. Neither had been edited, so whether it moves on an edit is still unknown. |
