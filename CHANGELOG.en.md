# TrailBuddy

*What's new — in plain words, by topic. Each block names its versions. This English list starts with version 0.120.0; the German CHANGELOG.md describes all earlier versions.*

## Detecting wheelies, jumps and stoppies — to try out

*Version 0.148.0, 2026-10-31*

- Under “About TrailBuddy” the regular app now also has the switch
  “Detect wheelies, jumps and stoppies (test)”. It is off by default and
  applies from the next ride on.
- While a ride with this switch is running, a small window above the map
  shows what the detection sees right now: a full-suspension bike from the
  side that lifts or drops its front, the angle, the running time with its
  peak, and whether you are riding, have the front up or are in the air.
  The picture runs about two seconds behind — that is how long the
  detection needs.
- After every detected wheelie, jump or stoppie the window asks “Correct”
  or “Wasn't one”, even if the banner gets lost among other notifications.
  The flag reports what it missed. The window can be shrunk to a small
  button.
- All measurements stay on the device; the privacy policy now also says
  what is measured.

## Notes and reports are one

*Version 0.147.0, 2026-10-31*

- The trail sheet now has a single button: “Report”. In it you choose,
  if you like, whether the trail is closed, destroyed, changed or open
  again, and write what is going on — with a photo if you want. A text
  on its own works too.
- At the bottom of the sheet everything is in one list, “Reports”:
  “Closed” with the text and the photo below it, as one line. Your
  buddies get one notification for it instead of two, with the text as
  the second line.
- The status stays until someone reports “open again”; text and photo
  disappear after 90 days or with “Done”. If a warning still stands next
  to the text, “Done” asks whether the trail is open again.
- You now set the condition (barely rideable to well kept) on its tile at
  the top of the sheet. A tap opens your rating and who said what.
- Without a connection, a text on its own also waits in the outbox. A
  photo needs reception; the dialog tells you.

## The planner avoids closed trails

*Version 0.146.0, 2026-10-31*

- A trail reported as closed or destroyed is no longer a way for the
  planner — neither downhill nor uphill as a connection between two
  other trails. The same goes for stretches the official source closes
  (e.g. in Tyrol), as long as the “Official trails” layer is on.
- If you pick such a trail yourself, the loop still takes it and says so
  below the result: “Includes closed trails: …”.
- “Changed” blocks nothing: those trails stay a way.

## Measuring stoppies

*Version 0.145.0, 2026-10-31*

- Development app only, with raw sensor data switched on: besides
  wheelies and jumps the measurement now also detects stoppies — the
  rear wheel up under hard braking. A banner “Stoppie detected” follows
  with duration, tilt and braking, plus “Correct” and “Wasn't one”; the
  measurement's notification now has “Missed stoppie”.
- A steep section without braking does not count as a stoppie. The
  thresholds are only starting values; they are set from the answers.
  Nothing changes in the regular app.

## Back button on the trail sheet

*Version 0.144.1, 2026-10-31*

- From Android 16 on, the back button sometimes sent the app to the
  background although the trail sheet was open — mostly after leaving
  the app once and coming back. Back now closes the sheet first, then
  the selection, and only on the empty map does the app go to the
  background.

## Wheelies and jumps from processed sensors

*Version 0.144.0, 2026-10-31*

- Development app only, with raw sensor data switched on: wheelies are
  now detected by the signal processing — it learns how the phone sits
  on the bike and so tells braking, corners and hits from a real tilt.
  Long wheelies are no longer cut short.
- New: after a jump a banner "Jump detected" shows the time in the air
  and the landing, with "Correct" and "Wasn't one"; the measurement
  notification now also has "Missed jump".
- The app remembers the mount from the last ride and so detects from
  the first minutes. The banner comes two to three seconds after the
  event. Nothing changes in the regular app.

## Counting wheelies and rating them right away

*Version 0.143.0, 2026-10-30*

- Development app only, with raw sensor data switched on: after each
  detected wheelie or manual a banner shows its duration, length and
  tilt, with "Correct" and "Wasn't one". If none came, tap "Missed
  wheelie" in the measurement notification. The answers go into the
  sensor file and set the thresholds. Nothing changes in the regular app.

## Measuring airtime and wheelies

*Version 0.142.0, 2026-10-30*

- Development app only: a switch under "About TrailBuddy" records
  acceleration, gyroscope and GPS during a ride. The thresholds for
  airtime and wheelies are measured from that before the app detects
  them. The file stays on the device and can be shared from "My rides".
  Nothing changes in the regular app.

## Signing in with GitHub, Discord and Google

*Version 0.141.0, 2026-10-29*

- Signing in with GitHub, Discord and Google is switched on — the
  buttons are under sign-in and sign-up.
- If signing in with the provider fails, the app now says why:
  cancelled, took too long, or the provider account carries the
  addresses of several TrailBuddy accounts. Before, you silently landed
  on the sign-in page again.

## Signing in without Apple

*Version 0.140.1, 2026-10-29*

- Signing in with Apple is gone: it would need a paid Apple account.
  Google, Microsoft, Facebook, GitHub, Discord and LinkedIn stay, next
  to email and password.

## Your name after signing in with Google & co.

*Version 0.140.0, 2026-10-29*

- Signing in via a provider for the first time, you now pick your
  username before the map — it is how your buddies find you. If the
  provider brings a username (GitHub, for example), it is already in
  the field; the app never suggests your full name.
- „Later“ keeps the provisional name; you can change it any time
  under Profile, „Account“.

## Signing in with Google & co. prepared

*Version 0.139.0, 2026-10-29*

- The app can now sign you in with Google, Apple, Microsoft,
  Facebook, GitHub, Discord and LinkedIn — next to email and
  password. The buttons appear under sign-in and sign-up as soon as a
  provider is switched on; until then nothing changes.
- If an account with your address already exists, signing in via a
  provider opens that account — no second one is created.
- An account via a provider needs no password. The app picks a
  username at first; a note tells you once, and you can change it
  under Profile, „Account“.

## „Not now“ is remembered

*Version 0.138.5, 2026-10-29*

- Choosing „Not now“ or „Later“ on a tour no longer brings the
  question back on every start — for the welcome, the tours on the
  tabs and the tour in the split sheet. Every tour can be started any
  time under Profile, „Quick guide“; the welcome now says so too.

## Destination in the open planner

*Version 0.138.4, 2026-10-29*

- With the planner open, „Route to here“ (long press on the map) and
  „Route here“ (from a place) now just set the destination of that
  plan and compute right away. Selected trails, stars, start and via
  points stay — the question „Replace the plan?“ no longer comes up.

## Decimal comma in the elevation profile

*Version 0.138.3, 2026-10-29*

- The spot under your finger in the elevation profile now writes
  kilometres the same way as the summary above it („16,5 km“) —
  until now it said „16.5 km“.

## Navigation in the small window

*Version 0.138.2, 2026-10-29*

- The small window while navigating now shows your position and the
  route ahead, zoomed out further than the full view. Until now the
  map in it stood still and showed a patch from the middle of the
  screen — often without the route and without you.
- At the bottom there is now just one sign and one number, large
  enough to read: the next trail's shield and the distance to it, the
  rest on the trail, “GO” at the trail head, and off the route the
  arrow to it and the distance. Names and climbs are in the
  notification.

## Trail list and elevation profile in the planner

*Version 0.138.1, 2026-10-29*

- “None” in the planner's trail list now really clears everything —
  including trails that dropped out of the list after a smaller radius.
  Until now they stayed selected out of sight and kept the area large.
  If selected trails lie outside the radius, the list now says how many.
- When you drag along the elevation profile, the reading for that spot
  now sits right beside the line, no longer in the corner by the height
  axis.

## Plan bigger loops, faster with older areas

*Version 0.138.0, 2026-10-29*

- The planner now covers a much larger area: up to 300 tiles instead of
  120, roughly the full 30 km radius. This is possible because of the
  tile preparation from 0.136.0 — a plan now needs only a fraction of
  the memory.
- Areas saved before 0.137.0 are now prepared for the planner in the
  background when the app starts. Until now this only happened on the
  first plan there, which took correspondingly long. If everything is
  ready already, you won't notice anything.

## Elevation profile and buttons right under the summary

*Version 0.137.2, 2026-10-29*

- In the result of a loop or route, the elevation profile now sits
  directly under the summary, with "Navigate" and "Save" below it.
  Descents, way mix and notes (such as "moved onto the nearest path")
  follow underneath — before, they pushed the profile out of the
  collapsed sheet. The summary appears only once, and the sheet opens
  just far enough for the buttons to show in full.
- The spot you pick in the profile now shows a mountain bike on the map
  instead of a city bike.

## "My position" in the browser answers right away

*Version 0.137.1, 2026-10-28*

- In the web app, a tap on "My position" often got no answer although
  your own dot was already on the map — after half a minute it said
  "Position not available". When the dot is there, the map now jumps to
  it right away. The same goes for starting navigation, the planner and
  "I'm on site".

## The first plan is fast too when the area is saved

*Version 0.137.0, 2026-10-27*

- After you save an area, the app prepares its ways for the planner in
  the background, not only on the first plan. So the first loop there is
  fast as well. While it runs, "My areas" shows a line with its progress;
  the cross cancels it, and the next save in
  the region continues where it stopped.
- After "Update" of a region, the app prepares the affected areas again
  right away. If you plan meanwhile, the preparation waits until the
  planner is done.
- A whole region is not prepared in the background — that would take
  hours. There, every plan prepares its surroundings itself.

## Planning is faster where you have planned before

*Version 0.136.0, 2026-10-27*

- Planning is much faster where you have planned before or where the
  area is saved. The first plan in a saved area prepares its ways for the
  planner and keeps them next to the map; every further loop or route
  there only puts them together — also after a restart. No network, no
  new download.
- When "Update" brings new map, height or way tiles, the app prepares
  the affected spots again on the next plan.

## Web app: code after a reload, location in the browser

*Version 0.135.2, 2026-10-27*

- While sign-in waits for the code from the e-mail (forgotten password
  or confirming a new account), the code entry comes back after a
  reload. Chrome likes to reload background tabs while you are in your
  mailbox — until now the empty form came back and the code could no
  longer be entered anywhere. Only the address is remembered, for one
  hour, as long as the code is valid.
- "My location" in the browser now asks for location properly and
  answers within 30 seconds at most instead of waiting forever without
  reception. If the browser has blocked location for the site, the
  message says where to allow it again: the icon at the left of the
  address bar.
- Cancelled map tiles no longer show up as errors in the browser
  console.

## "The network is still responding" at the top, and only as long as needed

*Version 0.135.1, 2026-10-27*

- The notice "Trails from … — the network is still responding" now sits
  at the top edge of the map with the other notices, no longer in the
  middle of the map beside the buttons.
- It appears only after a few seconds — usually the fresh state has
  arrived by then, so it no longer just flashes up.
- When reception comes back it goes away on its own: the app quietly
  asks again every 15 seconds, and at once when the phone switches
  between Wi-Fi and mobile data. Until now it stayed until the
  connection was fully gone and back.

## Trail heads in the woods, and loops through points only

*Version 0.135.0, 2026-10-27*

- When a trail starts or ends in the middle of the woods, the planner
  now takes it anyway: it joins the trail to the nearest way, up to
  200 m away, and says below the result which trail starts or ends how
  far off. Until now such a trail dropped out with "not on a mapped
  path".
- Waypoints alone are now enough in the planner: with no trail chosen,
  "Compute" plans a loop through the points back to the start (or up to
  the last point), and you can navigate it right away.

## No more picking trails in the planner by accident

*Version 0.134.1, 2026-10-18*

- In the planner, a tap on the map only counts when it hits the trail
  line itself. A tap just beside it, say on the way next to it or just
  to dismiss something, leaves the selection as it was.
- Every tap that adds or leaves out a trail now says so briefly at the
  bottom (say: “Hexentanz” added), next to "Undo". A starred
  trail you tapped away comes back with its star.

## Start and destination may lie beside the way

*Version 0.134.0, 2026-10-18*

- If you tap a start, a destination or a waypoint beside the way in the
  planner, the point now jumps up to 200 m to the nearest way instead of
  the plan stopping with "no way". The flag moves along, and the result
  says how far, for example "Start moved to the nearest way, 120 m
  away". This also works when you plan from your own location and are
  standing off the way.

## The planner computes on a leaner way network

*Version 0.133.5, 2026-10-18*

- The planner's way network takes a good third less memory again, it is
  built a bit faster, and the first computation of a loop is a fifth
  faster. The planned loops stay exactly the same.

## The planner needs less memory for the way network

*Version 0.133.4, 2026-10-18*

- The way network the planner computes on takes only a little over half
  the memory it used to, and it is built a bit faster. The planned loops
  stay exactly the same.

## The planner computes faster

*Version 0.133.3, 2026-10-18*

- The first computation of a loop takes about 40 percent less time. The
  planned loops stay exactly the same.

## The planner needs less memory

*Version 0.133.2, 2026-10-18*

- With many trails in the frame the planner took a lot of memory, close
  to a gigabyte on older phones. It now keeps its intermediate results
  much more compactly and computes a bit faster as well. The planned
  loops stay exactly the same.

## “Route to here” keeps the start

*Version 0.133.1, 2026-10-18*

- If you tapped a start on the map in the planner and then long-press and
  pick “Route to here”, the route now begins at that start. Until now it
  began at your own position, even when that was far away.

## “Cancel” next to the progress bar

*Version 0.133.0, 2026-10-18*

- If planning takes too long, there is now a “Cancel” button next to the
  progress bar. The planner stays open, and the chosen trails, start and
  target stay set; “Recompute” starts again. Until now only the X helped,
  and it closed the whole planner.

## Recompute without rebuilding the way network

*Version 0.132.2, 2026-10-18*

- With your own position as the start, the planner rebuilt the whole way
  network on every “Recompute”, every style change and every trail you
  deselected — your position was a few metres off each time. On older
  phones that took up to 40 seconds. Now it only rebuilds when the start
  leaves the loaded area.

## Messages with “Undo” go away again on their own

*Version 0.132.1, 2026-10-18*

- Messages with a button next to them — such as “Planner closed · Undo” —
  stayed until you swiped them away and covered “Start navigation”. They
  disappear again after a few seconds.

## Progress bar while planning

*Version 0.132.0, 2026-10-18*

- The planner shows a progress bar with a percentage while it builds the
  path network and computes the loop. On older phones a large area can
  take a minute; now you can see that it is moving.
- The limit for “area too large” is now 120 map tiles, about 36 × 36 km.
  Measured on an older phone: more does not fit safely into memory.
- In the development app, planning also logs how many map tiles were
  read.

## Learning the rider profile and “Back to the route” without a frozen map

*Version 0.131.2, 2026-10-18*

- “Learn from my rides” now reads only the map tiles along each ride's
  line instead of its whole frame, builds the road network in the
  background and looks at the 20 most recent rides at most — the sentence
  afterwards says when older ones were left out.
- “Back to the route” is computed in the background and with the bike and
  the style the route was planned with (until now with the defaults). A
  second tap nearby reuses the same network.
- When navigation starts, “Searching for your location …” is shown until
  the first fix arrives.

## Planner: the map stays smooth while the road network is built

*Version 0.131.1, 2026-10-18*

- The road network for a loop or route is now built in the background,
  not in the user interface. Until now the map could freeze for several
  seconds — in dense regions up to “App isn't responding”.
- A frame that is too large (more than 300 map tiles, about 55 × 55 km)
  is no longer read: the sheet says “Area too large” and suggests a
  smaller radius or fewer distant trails.
- Uphill trails and connections only join the network near the start,
  destination, waypoints and selected trails — no longer all within the
  list's radius. The network gets smaller, the loop computes faster.

## Planner: Direct, Easy and Fun with selected trails too

*Version 0.131.0, 2026-10-17*

- A route to a destination now has the three styles even with selected
  trails. **Direct** takes the shortest way and only the starred
  trails. **Fun** takes the selection along, as much as fits in time
  and climbing — like “To destination” before. **Easy** takes it along
  as well, but between the trails it prefers cycleways, quiet roads and
  gravel tracks to paths uphill.
- New in the loop's settings: the “Easy uphill” switch. Turned on, the
  loop plans its connections between trails the same easy way. The app
  remembers the setting.

## One planner for every way

*Version 0.130.0, 2026-10-17*

- “To the trail head” in a trail's sheet, the navigation icon, “Route
  to here” on a long press and the new “Route here” in a place's sheet
  now all open the same planner and compute right away. Until now they
  had their own sheet next to the planner, and both could be open at
  once.
- A long press on the map offers “Start here”, “Route to here”, “Via
  point here” and your navigation app.
- Come in that way and change nothing, and one Back takes you to the
  normal map — a trail you had selected stays selected. Add trails, and
  Back first takes you to the planner's bar.
- After “End navigation” the result is there again, to save it or plan
  anew.
- If a plan with selected trails is open, the app asks before a new
  request replaces it.

## Planner: route from A to B, even without a trail

*Version 0.129.0, 2026-10-17*

- In the planner, “To a point” now works without any selected trail: tap
  the finish, “Compute” — and you get the route there, through your
  waypoints if you set any. Until now the planner always needed at least
  one trail.
- In the result you pick the style: Direct, Easy (cycle paths and small
  roads, little climbing) or Fun (takes trails along the way). The
  planner remembers the style.
- Style and bike (Bike/E-Bike) in the result recompute at once,
  without “Recompute” — for a loop the bike does too.

## Planning: a change no longer looks like an error

*Version 0.128.0, 2026-10-17*

- If you change something after a loop is computed — a trail, the start,
  a slider — you now see “Selection changed” with a “Recompute” button.
  Until now it wrongly said the loop could not be computed. Nothing is
  recomputed until you say so, and an old line never stays on the map.
- Back in the planner goes step by step: first the result closes, then
  the planner. Until now Back closed everything at once.
- Closing tidies up: selection, start, finish and waypoints go too. Then
  “Planner closed” offers “Undo”, and one tap brings back the selection
  and the result.
- A different bike in the rider profile applies at once, also in an open
  planner.
- After a restart the planner opens as a loop again instead of waiting
  for a finish that is no longer set.

## Measuring where route planning stalls

*Version 0.127.4, 2026-10-17*

- The test version can now measure how long planning a loop or route
  holds up the screen, and which step is to blame. Nothing changes in the
  real app — the measurement isn't built into it at all.

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
