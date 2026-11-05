---
name: SweatKit
description: Your own rides and walks as scrubbable 3D flyovers, compared and tracked over time, on your device only.
---

<!-- SEED: re-run /impeccable document once there's code to capture the actual tokens and components. -->

# Design System: SweatKit

## 1. Overview

**Creative North Star: "The Instrument Over the Landscape"**

SweatKit is a precise instrument laid over a vivid world. Satellite terrain and the effort-coloured route are the landscape; the stats panel, timeline, tab bar and sheets are the instrument, floating in Liquid Glass and keeping out of the way. Everything that isn't data is native, neutral and steady, so the effort colour is the most alive thing on screen.

The system is native iOS first. Standard tab views, navigation stacks, toolbars and sheets pick up Liquid Glass from the system; custom glass is limited to the stats panel and the timeline. The density borrows from Flighty (lots of live data, legible and calm) and the personality borrows from Carrot (character in the details, never in the chrome). Motion is responsive: feedback and transitions on system springs, with the flyover as the only choreographed sequence.

The system rejects Strava's social feed (kudos, orange everywhere, leaderboards), Garmin Connect clutter (dense widget dashboards, tiny tiles, menus within menus), gamified fitness (streaks, reward badges, rings, confetti) and the generic dark SaaS dashboard (neon-on-black cards, hero metrics, gradient glows).

**Key Characteristics:**
- Data is the colour; chrome is neutral, plus one themeable accent.
- Glass only on the floating layer, never stacked on glass.
- System typography with fixed-width digits for every live value.
- Responsive motion on system springs; haptics mark meaningful crossings.
- Light and dark follow the system; text over imagery holds on snow and on forest.

## 2. Colors: The Effort Palette

A full palette with four named roles, each used deliberately, plus a user-selectable accent theme. Exact values are `[to be resolved during implementation]`, defined in OKLCH and shipped as asset-catalog colours with light, dark and Increase Contrast variants.

### Primary
- **Theme Accent** `[to be resolved during implementation]`: the one interactive colour. Selected tab, primary buttons, toggles, the scrub cursor and focus. Themeable, with three initial themes drawn from the logo explorations:
  - **Electric Cyan**
  - **Neon Lime**
  - **Cobalt**

### Secondary
- **Effort Ramps** `[to be resolved during implementation]`: data colour. Seven power zones, five heart-rate zones, a relative pace or speed ramp, and gradient bands (descent, flat, three climb steepnesses). Colour-blind safe and identical across the map, the timeline, charts and legends.

### Tertiary
- **Signal Colours** `[to be resolved during implementation]`: status only. Sync state, stale results, warnings and errors (expired key, denied Health access, failed request), plus the record and repeated-route marks in the feed. Never decorative.

### Neutral
- **System Neutrals**: backgrounds, grouped surfaces, separators and the label hierarchy come from the system's semantic colours, so Dark Mode, Increase Contrast and Liquid Glass tinting behave natively. Source badges follow each provider's attribution rules.

### Named Rules
**The Data Owns Colour Rule.** Zone and ramp colours mean one thing everywhere. Never reuse an effort colour for chrome, and never use the accent to encode data.

**The Theme Collision Rule.** Each accent theme is checked against every effort ramp it will sit beside. Where an accent sits too close to a zone hue (Neon Lime against the green zones, Electric Cyan against the cool end of the ramps), the chrome near the data steps back to neutral, rather than the data changing colour.

**The One Accent Rule.** The theme accent stays at 10% of any screen or less. On the flyover it appears only on the cursor and the active control.

## 3. Typography

**Display Font:** SF Pro Display (system)
**Body Font:** SF Pro Text (system)
**Label/Mono Font:** SF Mono, or SF Pro with monospaced digits, for live numerals

**Character:** One family, native and quiet, with numerals that hold still. Hierarchy comes from size and weight, not from mixing typefaces.

### Hierarchy
`[font sizes to be chosen at implementation, mapped onto Dynamic Type text styles]`
- **Display**: large stat numerals in the stats panel and comparison time gaps. Heavy weight, monospaced digits.
- **Headline**: screen and section titles (large navigation titles, the activity title).
- **Title**: feed card titles, week headers, sheet section heads.
- **Body**: settings, explanations, recovery and empty-state copy. Short and plain.
- **Label**: units, axis labels, legend chips, metadata (date, sport, source). Units are smaller and lighter than the number they qualify.

### Named Rules
**The Still Numbers Rule.** Every value that updates while scrubbing or during playback uses fixed-width digits and a fixed-width slot, so nothing jitters or reflows.

**The Dynamic Type Rule.** Every text style maps to a system text style and scales. Stat slots reflow to fewer columns at large sizes rather than truncating numbers.

## 4. Elevation

Flat by default, with the system providing depth. Content (lists, charts, map) sits at the base layer; the floating layer (stats panel, timeline, tab bar, toolbars, sheets) is Liquid Glass. There's no custom shadow vocabulary. With Reduce Transparency on, glass falls back to the system's opaque material.

### Named Rules
**The Single Pane Rule.** Glass never sits on glass. A sheet over the flyover hides or merges the stats panel rather than stacking on top of it.

**The Glass Is For Floating Rule.** List rows, feed cards and chart backgrounds are never glass. If it scrolls with the content, it isn't glass.

## 5. Components

<!-- Omitted in seed mode: no components exist yet. Signature components to document on the first scan: stats panel, timeline scrubber, legend chip, feed card, week header, route dot chart. -->

## 6. Do's and Don'ts

### Do:
- **Do** use standard SwiftUI tab views, navigation stacks, toolbars and sheets, and let the system apply Liquid Glass.
- **Do** keep effort colours identical on the map, timeline, charts and legend chip, and always name the current overlay in a legend.
- **Do** use fixed-width digits for every live value (The Still Numbers Rule).
- **Do** test text and glass over bright ground (snow, sand) and dark ground (forest).
- **Do** use system springs for transitions and a haptic tap when the cursor crosses a lap boundary.
- **Do** replace the follow camera with overview and a moving marker when Reduce Motion is on.
- **Do** show missing or unavailable data as plainly marked gaps, never as smoothed or invented values.

### Don't:
- **Don't** look like Strava's social feed: no kudos, no orange everywhere, no leaderboards or comparison with other people.
- **Don't** fall into Garmin Connect clutter: no dense widget dashboards, tiny tiles, or menus within menus.
- **Don't** gamify: no streaks, rings, reward badges, guilt notifications or confetti. Record marks are information, not celebration.
- **Don't** build a generic dark SaaS dashboard: no neon-on-black cards, hero metrics or gradient glows.
- **Don't** stack glass on glass, or put glass on list rows or chart backgrounds.
- **Don't** use an effort colour for chrome, or the theme accent for data.
- **Don't** add choreographed entrances (routes drawing in, stats counting up). The flyover is the only choreography.
