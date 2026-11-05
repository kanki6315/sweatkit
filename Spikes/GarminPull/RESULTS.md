# Garmin Personal API spike: results

Milestone M0, the three Garmin gates from the spec's "M0 decision gates" table.

**Status: waiting on a live run.** Garmin's pages settle none of the three gates on their own. The tool, its offline tests and the commands are ready; see `README.md`. Rows marked *Waiting on live run* are filled in once `swift run GarminPull gates` has been run with a real key.

## What is built

- `Packages/SweatKitGarmin` is the real client, kept whatever the gates decide: key-for-token exchange with renewal before expiry and one renewal on a 401, activity search by local start-date range with offset paging and sort order, activity summaries, original-file downloads as unopened bytes, and typed errors for a refused key, a refused fresh token, rate limiting, network failure and an unexpected response. It takes the key as a parameter and never logs the key or the token. Its assumptions that the live run checks are `Bearer` for data calls and the token body's field names (difference 3 below). It is not yet in `project.yml`.
- `Spikes/GarminPull` is the throwaway probe on top of it.
- Not built until the gates report: the sync depths, the month-by-month backfill and its two-listing check, a source-adapter protocol, storage and de-duplication.

Docs read on 4 November 2026: the [Personal API](https://developer.garmin.com/gc-developer-program/personal/personal-api/) page, the [Personal API FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq/) and the [endpoint reference](https://developer.garmin.com/gc-developer-program/personal/swagger-docs/). The endpoint reference page draws a Swagger viewer in the browser; the OpenAPI 3.0.1 document behind it ("Garmin Connect Personal API", version 1.0.0) is embedded in the page's script and was read from there.

## Gates

| Gate | Passes when | Result | Evidence | Decision |
| --- | --- | --- | --- | --- |
| 1. Does the Personal API return the original file with per-second power, heart rate and GPS? | A ride from the Garmin computer downloads with all three channels intact | *Waiting on live run.* The docs say the download is "an activity file in its original format", delivered as `application/x-zip-compressed`. They say nothing about which fields are kept. | To come: activity 24172582403 against `Fixtures/fit/outdoor-ride.fit`. The fixture has SHA-256 `d6050fe0…89561d7`, 877,925 bytes, 5,347 records, power on 5,337, heart rate on 5,347, position on 5,347. The run reports the inner FIT's SHA-256 and the same counts, and `isOriginal`, `fileFormat` and `trimmed` from the activity's metadata. | *Pending.* Pass: the API is the sync path for rides, and the inner FIT is the preserved original. Fail: file import becomes the main path for rides, and the API is used for listing and summaries. |
| 2. How deep is the history, and what are the rate limits? | Full history lists and downloads, or the limits are measured and written down | *Waiting on live run.* Neither is documented. The OpenAPI document lists no `429` response on any endpoint and no rate-limit headers. | To come: the earliest start date from an ascending search, compared with when the account was first used; whether the earliest activity's file downloads; every response header from about 10 paced requests (`out/requests.jsonl`); any `429` and its `Retry-After`. Optionally `months` for a month-by-month walk of up to 36 months. | *Pending.* Fail: backfill from a Garmin data export, and throttle sync to the measured limit. If no limit is hit in the gate run, the limits are recorded as "none seen at N requests, 3 s apart", which settles the gate's "written down" condition but not a full backfill's rate; the app then keeps pacing and stops on the first `429`. |
| 3. Do Zwift rides appear in the Personal API? | A Zwift ride is listed and its file downloads | *Waiting on live run.* The docs do not mention Zwift or virtual rides. The listing carries `activityType.typeKey` and `manufacturer`, which would identify one. | To come: activity 24906063494 found in its month's listing, its summary type and manufacturer, and its download against `Fixtures/fit/zwift-ride.fit` (2,409 records, power, heart rate and position on all). | *Pending.* Fail: Zwift rides come from file import or Apple Health. |

## Where Garmin's docs differ from the spec, or add to it

| # | Spec says | Garmin's docs say | Effect |
| --- | --- | --- | --- |
| 1 | Garmin provides "each activity file in its original format"; downloads are "kept byte for byte". | The download endpoint returns `application/x-zip-compressed`: the original file inside a zip. | The original to keep and hash is the file inside the zip, not the zip. Zip bytes can change with compression or timestamps while the file does not, so a revision keyed on the zip's hash would make false revisions. The spec's preservation and revision rules should name the inner file. To confirm in gate 1. |
| 2 | "Access tokens last 24 hours with no refresh token." | Tokens are valid "for 24 hours or until the Personal API key expires, whichever occurs first". Deleting a key also ends its tokens. | Token expiry is the earlier of 24 hours and the key's expiry. A token can die early if the key is deleted, so a `401` must lead to the re-entry flow, not only a token refresh. |
| 3 | The app exchanges the key for a token and then calls the endpoints. | The token endpoint is on the Personal API page and FAQ but not in the OpenAPI document. Its response body is not documented anywhere. The OpenAPI document declares no security scheme; the FAQ only says Connect APIs take "OAuth2 access tokens". | The token's field names, its stated lifetime and the header the data endpoints expect are all unconfirmed. The spike assumes `Authorization: Bearer <token>` and parses `access_token` or `accessToken`. The token check reports the real key names. |
| 4 | The search "filters only by activity start date and pages by offset"; history is walked in months of start dates. | Confirmed. `startDate` and `endDate` are inclusive and use the activity's **local** start date. The default sort is `startLocal`, descending. `start` is a zero-based offset. | Backfill months are local-time months. Storage should keep `startTimeLocal` so a range check can tell which month an activity was listed under. A ride that starts near midnight on the last day of a month falls in the month of its local date. |
| 5 | "A month rarely exceeds one page of 99." | The default `limit` is 99. No maximum is documented. | Page size 99 is confirmed as the default. Whether a larger `limit` is accepted is unknown; the spec does not depend on it. |
| 6 | Not mentioned. | `excludeChildren` defaults to `true`: legs of a multisport activity are left out of the listing unless asked for. | Multisport legs would not be listed by default. Rides and walks are rarely multisport, so this is a note for later, not a change. |
| 7 | A changed summary is detected by comparing listing entries; the file is downloaded again when start, duration or distance changed. Known limit: a file that changes while the summary stays the same is missed. | The per-activity endpoint `GET /activity-service/activity/{id}` has `metadataDTO.lastUpdateDate`, `uploadedDate`, `isOriginal`, `fileFormat.formatKey` and `trimmed`. The listing entry has none of them. | `lastUpdateDate` could narrow the known limit, at one extra request per activity. Worth checking in the live run whether it moves when an activity is edited. Not a change to the spec yet. |
| 8 | Rate limits and history depth "are not documented". | Confirmed. Nothing on any of the three pages, and no `429` in the OpenAPI responses. | No change. Gate 2 measures them. |
| 9 | Keys expire after 30, 90 or 180 days or 1 year; Garmin emails a week before. | Confirmed. The key is shown once; a lost key has to be deleted and a new one made. Its status and expiry show on Garmin Connect on the web. | No change. The app cannot read the key's expiry from the API; the user has to enter it, or the app counts from the chosen period. |
| 10 | Not mentioned. | The OpenAPI document lists a second server, `personal.connectapi.garmin.cn`. | Accounts in China use a different host. Not relevant to a personal build. |

Listing entries (`SummarizedActivityDTO`) carry `activityId`, `startTimeLocal`, `startTimeGMT`, `beginTimestamp`, `duration`, `elapsedDuration`, `movingDuration`, `distance`, `activityType` and `manufacturer`. That is enough for the spec's de-duplication rule and revision triggers without fetching each activity, as the spec assumes.

## Sync design checks for the live run

These are not gates, but the same run answers them. *Waiting on live run.*

| Check | How | Result |
| --- | --- | --- |
| Ascending sort with `limit=1` returns the earliest activity | `earliest` | |
| A month range returns that month's activities and nothing outside it | `month`, and the month listings inside `activity` | |
| The token response's field names and stated lifetime | `token` | |
| Data endpoints accept `Authorization: Bearer` | Any data call after `token` | |
| Whether `lastUpdateDate` is present and plausible | `activity` | |
