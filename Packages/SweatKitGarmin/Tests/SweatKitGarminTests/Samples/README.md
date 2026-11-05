These bodies are hand-written, not copied from Garmin, so they hold no personal data.
Their field names, types and formats match the responses M0's live run recorded on
4 November 2026: search entries write times as `yyyy-MM-dd HH:mm:ss`, the activity
summary writes them as `yyyy-MM-ddTHH:mm:ss.0`, and `beginTimestamp` is milliseconds.
The values are illustrative.

`token.txt` is the shape the token endpoint returned: the token as plain text
(`text/plain`), with no lifetime. `token-object.json` is a JSON shape the client also
accepts in case Garmin changes the format; Garmin has never returned it.
