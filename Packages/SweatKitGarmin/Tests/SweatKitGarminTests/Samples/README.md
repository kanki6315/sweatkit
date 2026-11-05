These bodies are hand-written from the field names and types in Garmin's Personal API
OpenAPI document (`SummarizedActivityDTO`, `ActivitySummaryDTO`), not recorded from a
live call. The values are illustrative. `token.json` is a guess: Garmin does not
document the token endpoint's response body. Replace each with a recorded body once
the M0 probe has run (`Spikes/GarminPull/out/responses/` holds them; strip personal
fields first). The probe never saves the token response.
