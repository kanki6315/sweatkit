# SweatKit design references

These boards are the approved visual targets for implementation and acceptance, versioned on 5 November 2026. `../DESIGN.md` defines the design-system rules; `../PRODUCT.md` defines product intent; the MVP spec defines behavior and calculations.

Open [the interactive board](Boards/index.html) in a browser. It is self-contained: styles, scripts, icons, illustrative data and generated terrain are embedded. No external assets or build step are required. The `Boards/png/` captures provide fixed light/dark references; they are design targets, not screenshots of the implemented app.

| Board | Screen | Light | Dark |
| --- | --- | --- | --- |
| 01 | Activity feed | [Light](Boards/png/01-activity-feed-light.png) | [Dark](Boards/png/01-activity-feed-dark.png) |
| 02 | Flyover | [Light](Boards/png/02-flyover-light.png) | [Dark](Boards/png/02-flyover-dark.png) |
| 03 | Analysis sheet | [Light](Boards/png/03-analysis-sheet-light.png) | [Dark](Boards/png/03-analysis-sheet-dark.png) |
| 04 | Indoor ride | [Light](Boards/png/04-indoor-ride-light.png) | [Dark](Boards/png/04-indoor-ride-dark.png) |
| 05 | Routes list | [Light](Boards/png/05-routes-list-light.png) | [Dark](Boards/png/05-routes-list-dark.png) |
| 06 | Route page | [Light](Boards/png/06-route-page-light.png) | [Dark](Boards/png/06-route-page-dark.png) |
| 07 | Comparison | [Light](Boards/png/07-comparison-light.png) | [Dark](Boards/png/07-comparison-dark.png) |
| 08 | Trends | [Light](Boards/png/08-trends-light.png) | [Dark](Boards/png/08-trends-dark.png) |
| 09 | Settings | [Light](Boards/png/09-settings-light.png) | [Dark](Boards/png/09-settings-dark.png) |

## What is authoritative

Match composition, hierarchy, spacing, typography, data colours, control placement and the described interactions. Use native iOS components and accessibility behavior rather than reproducing browser chrome literally. The boards' numbers, names, route terrain, sync timestamps, records and history are illustrative, not data to ship in the app. A drawn control does not prove a feature is implemented.

Preserve the layouts while handling actual data: empty or partial recordings, unavailable metrics, permission failures, long titles, different sports and large text. Never fabricate records, route membership, historical comparisons or cloud status to match an example. Existing supported functionality must remain reachable as the layout changes. New running-form charts extend the analysis surface using the same visual rules; their absence from the original board does not remove them from scope.

The HTML includes simulated interactions, not a production MapKit camera or a complete behavioral specification. Read each caption alongside the MVP spec. If a visual reference and a required behavior conflict, record the discrepancy and resolve it explicitly rather than silently dropping either requirement.

## Acceptance

For each implemented screen, compare fresh app captures with its light/dark reference at comparable sizes. Check layout and interaction, not just whether the code builds. Exercise representative real content and applicable empty/error states. Record tested build, device/runtime, outcomes, remaining differences and capture paths. Package tests do not certify visual parity, device performance or live Health/Garmin behavior.

Do not alter these targets merely to make an implementation pass. Intentional design changes should update the board/captures together in a separate reviewable change. Keep discarded explorations and generated app screenshots outside this reference folder. Add `Design/Assets/` only if a future approved board needs external assets.
