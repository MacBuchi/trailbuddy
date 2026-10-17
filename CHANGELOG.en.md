# TrailBuddy

*What's new — in plain words, by topic. Each block names its versions. This English list starts with version 0.120.0; the German CHANGELOG.md describes all earlier versions.*

## Test version next to the real app

*Version 0.127.3, 2026-10-17*

- For measurements on the phone there is now a separate test version,
  "TrailBuddy Dev". It sits next to the real app, with its own data and
  its own sign-in, and doesn't look for updates. Nothing changes in the
  real app.

## Route planning crashes less

*Version 0.127.2, 2026-10-17*

- Values learned from your own rides that fall outside any plausible
  range now count as not learned — before, such a value could crash the
  time shown in the planner.
- If computing a route fails, no old line stays on the map; switching
  quickly between "Direct", "Fun" and "Easy" always shows the result of
  the last tap.
- If "Learn from my rides" fails, the app says so instead of failing
  silently.

## Fewer freezes while computing routes

*Version 0.127.1, 2026-10-17*

- While planning a loop, routing to a trail head or learning from your
  own rides, the app could compute for so long on a phone that Android
  reported "app isn't responding". One step that looks for crossing
  paths is now much faster.

## An easy way to the trail head

*Version 0.127.0, 2026-10-16*

- Besides “Direct” and “Fun”, “To the trail head” and “Route here” have a
  third button: “Easy”. The way then takes cycleways and quiet roads,
  gravel where needed, and as little climbing and as few steep ramps as
  possible — it keeps well away from hiking paths and steps. Good for the
  approach, when you want to save your legs for the trail.
- The navigation icon on a trail offers “In TrailBuddy: easy” too.
- The time shown stays your bike's (bio or e-bike, with what it learned
  from your rides); “Easy” only changes which way is chosen.

## Via points before planning

*Version 0.126.0, 2026-10-16*

- The planner has a new button in its bar: with it you tap via points on
  the map that the ride should pass — the hut, the fountain, the
  viewpoint. A place works too, with “Via point in planner” in its sheet.
- The plan leads through all points and picks the order itself. A tap on
  a number removes the point again; the settings show how many there are
  and offer “Remove all”.
- The points come before the budgets: if the detour costs too much, fewer
  trails fit in.

## A place as start or finish

*Version 0.125.0, 2026-10-16*

- The sheet of a place on the map, such as a car park or a fountain, now
  has “Start in planner” and “Finish in planner”. As a finish, the
  planner switches to “To a point”.
- While the planner waits for its start or finish, a tap on a place takes
  exactly its position, not the spot next to your finger.

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
