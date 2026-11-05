# GarminPull

Throwaway probe for milestone M0. It runs the spec's three Garmin decision gates against the live Personal API. Nothing in `App/` or `Packages/` depends on it, and it can be deleted once `RESULTS.md` is complete.

The API client itself is not throwaway: it is `Packages/SweatKitGarmin` (token exchange and renewal, activity search, activity summaries, original-file downloads, typed errors). This probe adds what only M0 needs around it: reading the key from the environment, pacing, the gate checks, FIT decoding with Garmin's SDK, and rate-header reporting.

## Safety

- The key is read only from `GARMIN_API_KEY`. The tool never prints, logs or writes it. Requests are logged with the `Authorization` header left out.
- Requests go one at a time, at least 3 seconds apart. The first `429` stops the run, and the tool sends nothing more.
- A `401` or `403` also stops the run.
- Downloads, saved JSON response bodies (never the token response) and the request log go to `out/`. That folder is in `.gitignore` because it holds real GPS tracks. Do not commit it.

## Before a live run

1. In Garmin Connect on the web, open the Personal API Key page, choose **Create Key**, read and accept the terms, pick an expiry and copy the key. Garmin shows it only once.
2. In a terminal, export it without echoing it or putting it in your shell history (zsh):

```bash
read -rs "GARMIN_API_KEY?Garmin Personal API key: " && export GARMIN_API_KEY
```

3. Run every command from this folder:

```bash
cd Spikes/GarminPull && mkdir -p out
```

## The checks

One command runs all three gates in a single paced session of about 10 requests: token, newest page, earliest activity, then for each reference activity its summary, its month's listing and its file, then the earliest activity's file.

```bash
swift run GarminPull gates 2>&1 | tee out/gates.txt
```

The same checks one at a time. Each exchanges the key for a token first, so each costs one extra request.

| Gate | Command |
| --- | --- |
| Token exchange and its response shape | `swift run GarminPull token` |
| 1. Original file with per-second power, heart rate and GPS | `swift run GarminPull activity 24172582403` |
| 2. Newest page | `swift run GarminPull newest` |
| 2. Earliest activity, for history depth | `swift run GarminPull earliest` |
| 2. One calendar month by start date | `swift run GarminPull month 2026-10` |
| 2. Month-by-month walk, as the backfill would (at most 36 months) | `swift run GarminPull months 2025-11 2026-10` |
| 3. Zwift ride listed and downloadable | `swift run GarminPull activity 24906063494` |
| Any one download, compared with a fixture | `swift run GarminPull download 24172582403 --compare Fixtures/fit/outdoor-ride.fit` |

`activity` with one of the two reference IDs fetches the summary, lists that activity's month and checks the ID is in it, downloads the file, and compares it with the matching fixture by SHA-256 and by channel counts.

To check the decoder without a key, decode a local FIT or zip:

```bash
swift run GarminPull inspect ../../Fixtures/fit/outdoor-ride.fit
```

## What to send back

Paste the output of `gates` (or `out/gates.txt`). It holds activity names, IDs and dates, but no key, no token and no coordinates. The request log `out/requests.jsonl` holds every response header, with cookies hidden, and is useful if anything looks rate limited.

## Tests

No network. The client's tests (request building, response parsing, token renewal, error mapping) are in the package. From the repository root:

```bash
Scripts/test-packages.sh SweatKitGarmin
```

From this folder, the probe's own tests cover month ranges, pacing, stopping after a 429, rate-header detection, zip handling and FIT channel counts against the shared fixtures:

```bash
swift test
```
