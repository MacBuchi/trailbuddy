# TrailBuddy

*What's new — in plain words, by topic. Each block names its versions. This English list starts with version 0.120.0; the German CHANGELOG.md describes all earlier versions.*

## Start or finish at a trail head

*Version 0.124.0, 2026-10-15*

- A trail's sheet now has “Start in planner” and “Finish in planner”.
  They open the planner on the map with the trail head as start or as
  finish — also from the trail list.
- As a start, the trail is picked right away. As a finish, the planner
  switches to “To a point”, and the route ends at the trail head.

## Loop, last trail or a finish

*Version 0.123.0, 2026-10-15*

- In the planner's parameters you choose where the ride ends: back at
  the start (loop), at the end of the last trail, or at a finish you
  tap on the map. The bar gets its own button for the finish.
- Start and end carry their flag on the map, even when the start is
  your own position.
- A ride that does not end at the start is now called "Route" instead
  of "Loop" — in the sheet, as a saved ride and as GPX.

## Walk along the elevation profile

*Version 0.122.0, 2026-10-15*

- Tap the elevation profile of a planned loop or route, or slide your
  finger across it: a bike on the map shows you the spot, with distance
  and height above the profile. The map stays still, with the whole
  route in view.
- The compact elevation profile now has a km scale below it.

## One error less when the browser starts the app

*Version 0.121.4, 2026-10-15*

- In the browser, every start logged an error in the background
  because the app looked for an interrupted ride — there are none
  there. In the browser it no longer looks.

## Elevation arrows without reception

*Version 0.121.3, 2026-10-15*

- In the browser, the arrows ↓ and ↑ next to the elevation showed as
  empty boxes without reception, for example in the GPX import. The app
  now brings these characters along itself.

## "Mine" filter after your last own trail

*Version 0.121.2, 2026-10-15*

- If the trail list was set to "Mine" and you deleted your last own
  trail, it said "No trails for this search" — with no switch left to
  go back to "All". The switch now stays until "All" is chosen again.

## Outbox in the browser after starting without a connection

*Version 0.121.1, 2026-10-15*

- If the web app was opened without a connection, a waiting
  contribution only went out the next time you opened it, and "No
  signal" stayed on screen although the network was long back. Now
  the browser notices the return in this case too: the outbox sends,
  and the trails are loaded fresh.
- The outbox also sends when the app starts on a tab other than the
  map — in the browser, for example, after reloading the "Trails" page.
  Until now it waited until you opened the map.

## "What's new" in English

*Version 0.121.0, 2026-10-14*

- When the app runs in English, this list is in English too — from
  version 0.120.0 on. Below it come the older versions, which are
  described in German only.

## Privacy policy and imprint in English

*Version 0.120.0, 2026-10-14*

- The privacy policy, the imprint and the guide to deleting your account
  are now also available in English. When the app runs in English, the
  profile opens the English page right away.
- The German version remains the binding one; each page links to its
  other language at the top.
