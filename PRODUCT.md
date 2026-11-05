# Product

## Register

product

## Users

One person to start: a cyclist who also walks, runs and hikes, recording on a Garmin computer, Zwift and Apple Watch. They open SweatKit after an activity to relive it and check the numbers, and every so often to look at the long view. They know their own data well (threshold power, zones, the routes they repeat) and want it shown exactly, without explanation they don't need.

Built for personal use now, but designed as if it might be distributed later: first-run, empty states and recovery flows should make sense to someone who isn't the author.

## Product Purpose

A native iOS app that replaces Strava and Garmin Connect for viewing one person's own activities. It merges Garmin, Apple Health and FIT files into one local-first library, shows each activity as a scrubbable 3D flyover with an effort-coloured route, compares efforts on repeated routes, and tracks trends over time. No account, no server, no social layer.

Success: two weeks of daily use without opening Strava for viewing, because SweatKit is both more vivid for reliving a ride and clearer for reading it.

## Brand Personality

**Vivid, precise, private.**

- **Vivid**: effort colour on the route and in the charts is the most alive thing on screen. Reliving the ride should carry some of the thrill of doing it.
- **Precise**: numbers are exact, stable while scrubbing and trustworthy at a glance. The app never invents or smooths over missing data; it says what it doesn't have.
- **Private**: no audience and no pressure. Progress is something you notice, not something you're pushed toward. The voice is plain, calm and specific, never cheerleading.

Emotional goals: the thrill of reliving the effort, and quiet satisfaction watching progress build, with no guilt either way.

References: Apple's own apps and the Human Interface Guidelines are the primary reference (standard navigation, sheets, toolbars, Liquid Glass from the system). Flighty for dense live data made legible and calm. Carrot for personality carried in details rather than chrome.

## Anti-references

- **Strava's social feed**: kudos, orange everywhere, leaderboards, comparison with other people.
- **Garmin Connect clutter**: dense widget dashboards, tiny tiles, menus within menus.
- **Gamified fitness**: streaks, badges as rewards, rings, guilt notifications, confetti.
- **Generic dark SaaS dashboard**: neon-on-black cards, hero metrics, gradient glows.

## Design Principles

1. **The data is the interface.** Map, route and charts are the content; controls float over them and stay out of the way. Colour belongs to data, so zone colours keep their meaning everywhere.
2. **Native first.** Use the system's components and behaviours before inventing custom ones. Custom work is limited to where the product needs it (the stats panel, the timeline, the flyover).
3. **Never invent data.** Show what exists, mark what's missing or unavailable, and explain staleness or sync gaps plainly.
4. **Steady under the thumb.** Scrubbing, playback and live values must feel stable and immediate: fixed-width digits, no jitter, motion that explains position rather than decorates.
5. **Progress without pressure.** Records and trends are informative, not motivational. No nagging, no streaks, no comparison with anyone else.

## Accessibility & Inclusion

No formal WCAG target for now. The spec's baseline still applies from the first build: Reduce Transparency, Increase Contrast, Reduce Motion (follow camera falls back to overview), Dynamic Type, and VoiceOver including audio descriptions of charts. Zone palettes are colour-blind safe, and text over satellite imagery is checked against both bright ground (snow, sand) and dark ground (forest).
