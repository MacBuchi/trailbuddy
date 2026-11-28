# TrailBuddy

*What's new — in plain words, by topic. Each block names its versions. This English list starts with version 0.120.0; the German CHANGELOG.md describes all earlier versions.*

## The Garmin watch with the iPhone

*Versions 0.207.0–0.207.2, 2026-11-27 to 2026-11-28*

On the iPhone, too, the route now goes to the Garmin watch and its rides come back, as on Android. There, TrailBuddy does not see the watch by itself: the navigation start sheet shows "Connect watch" once, the tap opens Garmin Connect, and you choose the watch there. After that, the usual switch with its name appears. The iPhone asks for Bluetooth only on "Connect watch", never when you open the app. Garmin Connect must be installed on the iPhone; without it nothing appears. Nothing changes on Android or the web.

Since 0.207.1, TrailBuddy hears the watch while the app sits in the background on the iPhone — before, a ride from the watch only arrived once you opened TrailBuddy. And when you connect the watch fresh from Garmin Connect, its messages now come through right away.

Since 0.207.2 the iPhone app is smaller: it no longer carries the parts for push notifications, which do not exist on the iPhone yet. Push on Android and the web stays as it is.

## Notifications, spoken cues and navigation on the iPhone

*Version 0.206.0, 2026-11-27*

On the iPhone, TrailBuddy now asks on the way, as it does on Android. When you ride onto a trail with a report, a notification comes with "That’s right", "Trail is open" and "Change…", and detected wheelies, jumps and stoppies ask with "Correct" and "Wasn't one". The buttons work with the screen locked, without opening the app. The iPhone asks once, when you start your first ride, whether TrailBuddy may send notifications. It does not ask when you open the app. Spoken cues now play on the iPhone too, and music only gets quieter while they play. Navigation keeps running there in the background and speaks with the screen locked; you end it in the app. Nothing changes on Android or the web.

## Recording rides on the iPhone

*Version 0.205.0, 2026-11-26*

You can now record a ride on the iPhone. Recording continues while TrailBuddy is in the background or the screen is locked; the iPhone then shows the blue location indicator at the top. If you swipe the app away in the app switcher, recording stops, and the bar says so when you start. The next time you open the app, the ride continues and TrailBuddy tells you when nothing was recorded. This also applies on Android, for example after the phone restarts. Wheelies, jumps and stoppies are detected the same way on the iPhone; notifications on the way and spoken cues come there later. If you only allow your approximate location, the app now says that a ride needs your precise one.

## The iPhone: import, privacy and a shared foundation

*Version 0.204.0, 2026-11-26*

On the iPhone, GPX import now opens the file picker; before, it failed there. Rides, the outbox, caches and maps stay out of the iCloud backup on the iPhone, just as they stay out of the Google backup on Android. The prompts for location, camera and photo library come in German and English, and the app starts on its own background instead of a white screen. Nothing changes on Android or the web.

## The map on the iPhone simulator

*Version 0.203.1, 2026-11-25*

On the iPhone simulator, no map appeared after signing in. The cause was a false alarm in a helper library; the new version fixes it. Nothing changes on Android or the web.

## First steps towards the iPhone

*Version 0.203.0, 2026-11-24*

TrailBuddy can now be built for the iPhone. There is no download yet. Ride recording, push notifications, whole regions and handing a place to a navigation app stay off there until they have been tested on a real iPhone. Nothing changes on Android or on the web.

## Routes at crossings

*Version 0.202.0, 2026-11-22*

The planner shows the first pass on top. During navigation the upcoming path starts bright green and fades over 500 metres. Completed sections recede into the background.

## GPX routes, trail hotspots, and Garmin route storage

*Version 0.201.0, 2026-11-22*

- “Route from GPX” in the planner opens a track on the map. Start navigation or put the route on your Garmin watch from there.
- Trail hotspots have a lime center. Black trails share one segment.
- In “Routes on the watch,” you can check for the watch again if it hasn't confirmed the transfer. Hold UP in the Garmin test build to find transfer diagnostics.

## MTB avatars and buddy chat

*Version 0.200.0, 2026-11-22*

Refined faces, hairstyles, beards, eyewear, and helmets give MTB avatars
more expression, even in small chat and map portraits. Choose from twelve
hairstyles and nine facial hair options with previews. Clear glasses
leave the eyes visible and sport glasses have a tinted shield. Choose
clear, lightly tinted, or mirrored lenses for your goggles. The editor shows individual options once
you start a portrait. If your buddy list is already loaded, opening a
chat checks only your relationship with that buddy.

## Trail hotspots on the map

*Version 0.199.0, 2026-11-22*

When you zoom out, the map groups nearby trails into rings. The count
and colors show how many trails there are and their difficulty. Tap a
ring to zoom in.

## Map controls

*Version 0.198.0, 2026-11-21*

On the map tab, the buttons and bottom bar are now slightly translucent,
leaving more of the map visible. Tap anywhere in the open legend to close it;
swipe to keep scrolling through its samples.

## Your MTB avatar

*Version 0.197.0, 2026-11-21*

Build your avatar in your profile with helmets, hairstyles, eyewear,
colors and more. Start with a preset or randomize it, then make it your
own. Confirmed buddies see your saved avatar in their list, in chat and
on the map during a live group ride. You can switch back to initials in
the editor at any time.

## Encrypted database backups

*Version 0.196.1, 2026-11-21*

Stored accounts and trail contributions can now be recovered from encrypted
database backups. The privacy policy describes how backups are stored and
retained.

## Answer jump cues on your Garmin watch

*Version 0.196.0, 2026-11-21*

With watch app 1.10.0, press UP to confirm a detected jump or DOWN to
reject it. You can do this with your phone in your pocket. The cue lasts
eight seconds. START and LAP still control recording and trail marks.

## Planner and ride: easier to read

*Version 0.195.1, 2026-11-21*

- The switches under a loop ("Record", "Screen on", "Announcements")
  now clearly show when they are on: a green fill.
- The "other loops" strip is now just called that; the long title was
  cut off on small phones.
- During a ride the status ("Recording · Learning the mount") sits on a
  dark pill and no longer runs into the street names on the map.

## Fixed limits per bike, also for distance

*Version 0.195.0, 2026-11-21*

- The loop planner works with two fixed limits per bike: climbing and,
  new, distance (60 km for the bio bike and 90 km for the e-bike by
  default). You set both under "Adjust". The time no longer shrinks the
  limits; the same number shows everywhere, in the header, the tiles
  and the comparison.
- Below the bike you see how fast you climb, about "450 m/h". The
  planner estimates the time from that. Once your rides are learned,
  it shows your own value.
- After a recording that was longer than your limit, the app asks
  whether to raise it — as before for climbing, and for both in one
  question.
- Tidied up: "Climb" and the time fit their tiles again, the header
  wraps instead of cutting off, numbers stay with their units, and many
  trails that do not fit the budget show as one line to expand.

## Sensor data with light and proximity

*Version 0.194.0, 2026-11-20*

- Recording sensor data now also writes ambient light and the proximity
  sensor into the file, if the phone has them. Later this should help
  the app tell more reliably whether the phone is in a pocket. Nothing
  is detected from it yet, and no new permission is needed.

## No online map inside a saved area

*Version 0.193.1, 2026-11-20*

- Inside a saved area, the map on Android now loads nothing from the
  network, also when zooming. It takes everything from storage as long
  as the area covers the whole view. At the edge of the area, the online
  map comes back.

## Fewer requests, place names for older areas

*Version 0.193.0, 2026-11-20*

- The app asks the map storage for its indexes (map, ways, heights,
  regions) at most once a day, instead of at every start and every time
  “My areas” opens. A tap on “Update” there still gets the newest
  version right away.
- Heights loaded once for a trail’s profile stay on the device. The
  profile costs no request next time and also shows without a network.
- Areas saved before the place search have no place names yet. “My
  areas” now says so and fetches them with “Update”, only a few kB.
  After that the search finds villages and peaks in them offline, too.
- A place named exactly like what you typed only comes first when it is
  nearby (up to 30 km). Further away, distance decides, and the nearby
  “Aurach” comes before a distant “Au”.

## Development build starts again

*Version 0.192.3, 2026-11-20*

- Only the development build for testing (“TrailBuddy Dev”): since
  0.192.1 it quit right at start on Android. The regular app was not
  affected.

## Search on the device first

*Version 0.192.2, 2026-11-20*

- The search on the map now finds towns and peaks in your saved areas
  and in what was loaded before first — without asking the network. Only
  a tap on “Search more places online” asks the map storage; after that
  the open field keeps searching online as you type.
- A name that matches what you typed exactly, or starts with it, now
  comes first — “Au” finds Au before the nearer Pfaffenau.
- After jumping to a place, a short pin shows exactly where it is.
- Places and name lists that were loaded once stay on the device (up to
  20 MB) and are not fetched again; their index is asked for at most once
  a day. That saves mobile data and requests.

## Fewer requests to the map storage: measuring first

*Version 0.192.1, 2026-11-20*

- Only in the development app and the web preview: the profile has a new
  row “Development”. It counts how often the app has asked the map
  storage since it started — split into map, ways, elevation, manifests,
  places and place search, with “Reset” for a new round of measuring.
  This is the basis for cutting those requests, especially inside saved
  areas. Nothing changes in the normal app.

## Search on the map

*Version 0.192.0, 2026-11-19*

- The magnifier now also finds **towns, villages, peaks, passes and
  huts** — not only nearby but across the whole map. One tap and the map
  flies there; a hut opens its sheet right away.
- The names come from our own list on our map storage, not from a
  third-party search service. Only the first two to four letters of the
  word you search for are requested.
- Without a connection the magnifier searches the place names of your
  saved areas — newly saved areas bring them along.

*Version 0.191.0, 2026-11-19*

- New at the top of the button column: the **magnifier**. It finds your
  trails and your buddies' trails, saved start points and places around
  the centre of the map — also by type, such as “drinking water” or
  “bike shop”, and even when those places are hidden on the map. Tap a
  result and the map jumps there. Typo? The search says “Did you mean
  …?”.
- The search only looks at what the app already knows: no query goes
  to an outside service.

## No more error with “Buddys unterwegs” during a ride

*Version 0.190.1, 2026-11-19*

- With “Buddys unterwegs” switched on, an internal error could occur
  during a recording when a new ride point and a new position arrived at
  the same time. The check now waits until the app has handled both.

## Safer among buddies

*Version 0.190.0, 2026-11-19*

- You can **block** someone: from a buddy row via the “⋮” menu, from a
  request and in a conversation. You are then no longer connected, your
  messages are gone for both of you, and neither of you can send the
  other a new request. The blocked person is not told. You can unblock
  in your profile under “Blocked users”.
- You can **report** a person or a single message — with a reason and,
  if you like, a note. The report goes only to the operator, not to the
  person. To report a message, long-press it.
- “Remove buddy” is now in the same “⋮” menu on the buddy row.

## More stable

*Version 0.189.3, 2026-11-19*

- The app no longer freezes when the phone's location service hangs.
  Until now, stopping a ride or switching off your position could leave
  the app "not responding" while the system was stuck. The app now only
  listens to the location data it really needs.

## Tidied up

*Versions 0.189.1–0.189.2, 2026-11-18*

- Nothing new to see: the source code is now formatted consistently.
  The app behaves exactly as before.
- Getting ready for the Play Store: new versions can go to internal
  testing on Google Play on their own.
- The "Delete account" page now also explains how to delete single data
  without deleting the whole account.

## Routes on the watch

*Version 0.189.0, 2026-11-18 (watch app 1.9.0)*

- **"Put on watch"**: On the planner result and in a ride's menu in
  "My rides", one tap puts the route on the Garmin watch without
  starting navigation. Up to three routes stay there; when the watch is
  full, the app asks which one should go.
- **Start on the watch without your phone**: Hold UP, "Saved routes",
  pick a route — it loads in one piece, with length and climb in the
  list. A new navigation route and "End route" leave the saved ones
  alone.
- **If TrailBuddy is closed on the watch**, the job waits and goes over
  as soon as the watch app checks in. In your profile under "Routes on
  the watch" you see what's there and what is still coming, and remove
  routes again.
- **Off route without a phone** the watch says "no phone" — only the
  phone can replan.

## Announcements and buddies on the Garmin watch

*Version 0.188.0, 2026-11-18 (watch app 1.8.0)*

- **The watch buzzes briefly with the announcements.** With
  "Announcements" on, it shows the trail's shape and name for a few
  seconds when a trail is ahead, when you ride in and when it's done —
  going off route and arriving it still notices by itself.
- **"Max is riding" on your wrist too**: when a buddy nearby is out, the
  watch buzzes and shows their disc and name.
- **Group ride on the watch**: buddies sharing "Live" with you appear on
  the watch map as a disc with their initial; those farther away sit
  small at the edge in their direction, an old position as a ring.
- **The watch app computes and stores more sparingly**: built like the
  store package, and the map and route tracking compute less per frame
  and per GPS fix — about 4.6 KB more headroom on the fēnix 5.
- **Routes on the watch at most 700 points** instead of 800: long routes
  are simplified a little more so the watch can still take a new route
  mid-ride.

## Group ride

*Version 0.187.0, 2026-11-18*

- **Buddies on the map while you ride.** Turn on "Live" during a ride
  (the new button above the record button): buddies nearby who have it
  on too show up exactly on your map — as a disc with their initial —
  and you on theirs.
- **Per ride only, off by default.** It is over when the ride ends.
  "Home" and the first kilometre apply as with "Buddies out riding";
  nothing is stored.
- **Homies**: in the buddy list you choose per buddy whether they are a
  homie. Homies see your coarse cell of about 5 km as a square on the
  map, even from far away — never more exact, not live.
- **Honest without signal**: an old position is shown faded and says
  "4 min ago"; after a quarter of an hour it disappears.

## Buddies out riding

*Version 0.186.0, 2026-11-18*

- **If a buddy is riding near you right now, TrailBuddy tells both of
  you** — once per ride, without distance or direction. If you want to
  meet, send a message.
- **Only a coarse cell of about 5 km is shared**, never your position,
  and it is not stored. Never within 1 km of "Home" (kept only on your
  phone) and never in the first kilometre of a recording. Without a
  recording only while the app is open.
- **Asked once, with "Yes" preselected.** Afterwards you switch it on or
  off under Profile → Notifications, where you also set "Home". In the
  buddy list each buddy has two switches: whether they see you and
  whether you get notices about them.
- **With "Announcements" on you also hear it** while you are recording.

## Announcements in your ear

*Version 0.185.0, 2026-11-17*

- **Phone in your pocket, earbuds in:** With the new "Announcements"
  switch TrailBuddy tells you when a trail is coming up ("Trail Rosskopf
  Süd, S2, in 200 metres"), when it starts and when you are done — with
  your time and, if detection runs, your airtime. Also once when you
  leave the route and when you are back on it, and "You have arrived".
- **Your buddies' fresh reports come along:** "Max, 3 days ago: tree
  down" — reports from the last two weeks, not your own.
- **Without navigation too:** If you only record, you hear a known
  trail's name and grade as you ride into it.
- **No turn instructions.** The voice is your phone's own speech output,
  no network needed; music only gets quieter. The switch is in your
  profile under "Navigation" and as a chip when you start a ride. Off by
  default, Android app only.

## "Saved" even without a start point

*Version 0.184.0, 2026-11-17*

- **The "Saved" choice is always there for the start.** If you have no
  start point yet, the list tells you how to save one — long-press the
  map or tap a place — and offers "Save my location" right away.

## Start points in the planner

*Version 0.183.0, 2026-11-17*

- **"Saved" for start and target:** next to "My location" and "Choose on
  the map" the planner offers a third choice. It opens the list of your
  start points and your buddies', nearest first, the one you chose last
  at the very top. For a route it works for the target too.
- **Already chosen at the car park:** if you are within 300 m of a
  saved point, it is the start when the planner opens. At home it stays
  "My location".
- **Save start:** tapping "Start" in the planner's header offers "Save
  start" — over the result as well. "Save my location" is there and
  below the list; it starts as private and reminds you not to share your
  front door.
- Start and target in the header now carry the name of the place or
  start point you chose.

## Start points on the map

*Version 0.182.0, 2026-11-16*

- **Save as start point:** long-press the map or tap a place (a car
  park, say) and choose "Save as start point". You give it a name and
  decide whether your buddies see it.
- **On the map:** your start points show as a flag on a green disc,
  your buddies' as a blue ring. A tap opens a sheet: as start or target
  in the planner, drive there with your navigation app — and on your
  own ones rename, make private or delete. You can save a buddy's point
  as your own.
- **Can be switched off:** "Layers" has a "Start points" switch.

## Saving start points — the groundwork

*Version 0.181.0, 2026-11-16*

- **Under the hood for saved start points:** soon you can save a car
  park or the entrance of a trail centre as a start point and share it
  with your buddies — then the planner no longer asks "From where?"
  every time. This version sets up the storage: a start point has a
  name, a location and the choice whether your buddies see it. It is
  kept on your device with the trails, so it is there at the car park
  without reception, and without a connection it waits in the outbox.
  The buttons for it come with the next versions.
- **Privacy policy:** it names saved start points as a new kind of data
  — who sees them and how long they stay.

## Loops compared

*Version 0.180.0, 2026-11-16*

- **"Compare" on the "other loops" strip:** a view of its own shows all
  loops as a chain — time to the right, trail share upwards. Every loop
  is the one before plus one trail; where the chain has a peak, the loop
  is worth it, the other points are faded.
- **The ring around each point** shows how much of your climb limit the
  loop needs; shape and colour inside are its hardest grade. A tap shows
  the loop on the map, the card below names the trail that was added,
  time, share, climb and grade. "Take this loop" or "Back to the
  suggestion".
- **"Also above the limit":** the switch works out once which loops
  more climbing would allow — hollow and dashed in the warning colour,
  with "… m above the limit". Such a loop isn't ridden; its button
  raises your bike's limit and plans again.

## Other loops at a glance

*Version 0.179.0, 2026-11-16*

- **The "other loops" strip:** below the numbers of a loop's result,
  every loop the planner built on the way to its suggestion stands as a
  stem on the time line — from one hour below to one hour above your
  time. The higher the stem, the more trail; on top sits the loop's
  hardest grade as shape and colour. "SUGGESTED" marks the suggestion.
- **Tap or drag** to snap to the nearest loop. The numbers change at
  once; the line on the map and the profile follow as soon as the loop is
  computed. Below it says what changes: "Shorter: without …" or "Longer:
  also …". "Start ride", Save and GPX take the loop shown.
- **The "Time" tile** shows only the number now — its scale has become
  the strip. For a loop the elevation profile now sits below the buttons
  so that "Start ride" stays visible when collapsed; the sheet opens a
  little higher for it.
- The suggestion itself stays as it was; sometimes the planner now finds
  a connection that was just out of reach before, and the loop gets more
  trail.

## The watch shows symbols instead of words

*Versions 0.178.0–0.178.1, 2026-11-16 (watch app 1.7.0)*

- **Number pages:** a small symbol precedes each value instead of the
  word — stopwatch for ride time, measure for distance, heart for pulse,
  mountains for altitude, signpost "to trail", flag "to finish", clock for
  the time of day. The numbers are bigger, the unit sits small and grey
  behind them.
- **Jumps:** the jump on the left (plane, air time, count), the wheelie on
  the right (angle, count). The cues during a ride show symbol and number:
  plane, wheelie, stoppie.
- **Recording:** before the start only a triangle sits at the top right by
  the START key, in the pause two bars on orange. "TRAIL" and "ARRIVED"
  stay words, and so do the questions.
- **Arrived:** a stopwatch instead of "h", air and wheelie on one line.
- The app itself is unchanged.
- **Checked (0.178.1):** the line above the ride ("Learning the mount",
  "Jumps on", "Pocket: jumps only") is now part of the check that
  replays the flow between phone and watch. Nothing changes for you.

## Everything fits the round watch screen

*Version 0.177.3, 2026-11-16 (watch app 1.6.2)*

- **At the bottom of the map** the black area starts a little higher, and
  from 10 km the distance has no decimal ("123 km") — the line with
  distance and climb used to run off the round edge.
- **Free ride:** the riding time now sits next to "FREE RIDE", distance
  and climb below.
- **Arrived:** the trail shields count themselves, the best values (air
  and wheelie) follow in two lines and are fully readable.
- **Number pages:** before the start a grey dot replaces "START: RECORD"
  at the bottom (the text stays at the top of the map); the map says
  "Storage full". A question's time bar no longer runs under "NO".

## The watch shows long names and the question in full

*Version 0.177.2, 2026-11-15 (watch app 1.6.1)*

- **Long trail names:** at the bottom of the watch map a long name now
  gets smaller and then shortened in time, before the black border cuts
  it. Before, the watch measured against the whole round screen instead
  of the map.
- **The question "Route from your position?"** uses a smaller font and
  now fits the screen; "START = YES" moves a little away from the edge.

## Your favourite trails count for more

*Version 0.177.1, 2026-11-14*

- **Trails you ride often weigh twice as much in the suggestion:** each
  ride on a trail now gives it 12 % more weight (full from five rides),
  together with your stars at most 80 %. Before, the preference was so
  weak that it hardly ever changed the suggestion. A trail you never
  rode stays in play when it lies well.

## The climb limit grows with your rides

*Version 0.177.0, 2026-11-14*

- **One limit per bike:** the bio bike and the e-bike now each have
  their own climb limit in the planner. Switch the bike and its limit
  applies; what you had set before stays with the bike that was chosen
  then.
- **Climbed more than the limit says?** If a recorded ride climbed at
  least 100 m more than your bike's limit, a line in the sheet at the end
  of the ride asks: "1100 m climbed — raise the limit for the bio bike
  from 800 to 1100 m?" The app only raises it when you tap "Raise", and
  never lowers it. "Undo" takes the answer back.
- **Only one question, and rarely:** after "No" the app asks again only
  when a ride climbed another 100 m more. If a ride recorded as bio bike
  clearly looked like an e-bike, the one question is "Was it one?" —
  "Yes" moves the ride to the e-bike, "No" raises the bio bike's limit.
  Close the sheet without answering and the line shows once in the
  planner the next time you open it. Everything stays on the device.

## The suggestion knows your favourite trails

*Version 0.176.0, 2026-11-14*

- **Your trails count for more:** the planner leans a little towards
  trails you rated well yourself (4 or 5 stars) or have ridden often.
  Nothing is ruled out by it: a trail you have never ridden still comes
  along when it lies well on the loop.
- **How often you rode a trail** is counted by the phone from your rides
  in "My rides" — once per ride, and only on the device. The count goes
  neither to the server nor to your buddies. The web app has no rides,
  so there only your stars count.

## A loop on suggestion

*Version 0.175.0, 2026-11-14*

- **Suggest a loop:** in the planner, the button under "Loop" now reads
  "Suggest a loop". The planner picks the trails itself — from all in
  your network near the start: within 5 km for 1 h, 8 km for 2 h, 12 km
  for 3 h, 15 km beyond. Reported trails stay out. Above the result it
  says "Suggestion: 4 trails within 12 km".
- **Edit:** next to Save and GPX, "Edit" leads into the selection with
  the suggested trails already chosen.
- **Climb to match the time:** the suggestion uses your climb limit for
  3 h, proportionally less for shorter loops, never more for longer ones.
- **Search wider:** if no trail lies within the radius, or too few fit
  the time, "Search wider" tries the next, larger radius.
- **Short loops more precise:** under 2 h the loop may only differ by a
  quarter of the time (15 min at 1 h); from 2 h on it stays half an hour.
- **Rather shorter with more trail:** if a shorter loop has clearly more
  trail share than any within the time window, the planner takes it and
  says so in the result.

## Time is a guide, not a limit

*Version 0.174.0, 2026-11-13*

- **One minute over no longer costs a trail:** the planner's time now
  reads "About 3 h". The loop may be half an hour shorter or longer;
  within that, the planner picks the version with the most trail share.
  If the next trail is only reachable by a long approach, the loop stays
  a little shorter — if it lies almost on the way, it comes along, even
  if that makes 3 h 20.
- **How much of your limit:** under "Climb" and "Time" in a loop's
  result there is a slim scale — the climb against your limit, the time
  with its ± 30 min window. If something goes over (with must-ride
  trails or dragged points), the scale turns orange.
- **Honest estimate:** the time reads "approx. …", and below it says
  that it is estimated without breaks. If the loop stays clearly
  shorter because no more trails fit, the sheet says so.

## The planner asks first what you have in mind

*Version 0.173.0, 2026-11-13*

- **Two questions instead of a toolbox:** the planner button opens a
  small sheet: loop or route? Below it, depending on the choice, the
  start (your location or a point on the map) and the time with large
  − and + keys — or the end. Everything is preset; your last choice is
  in front next time.
- **A route in three taps:** planner, "Route", a tap on the map — as
  soon as the end is set, the app computes. With "My location" as the
  end it takes you back to yourself; you then tap the start on the map.
- **Loop:** "Choose trails" takes start and time into the usual
  selection. A ready-made suggestion follows in one of the next steps.
- **"Put it together yourself"** opens the planner as before, without
  questions. Tapping a trail does the same.

## The planner for editing, tidied up

*Version 0.172.0, 2026-11-13*

- **Start and end at the top:** the planner shows start and end as two
  rows at the very top, below them time, climb and bike with "Adjust".
  A tap on "End" decides whether it becomes a loop (back to the start),
  a route to a point on the map or an end at the last trail — no more
  hunting for the destination.
- **The bar on the left with words:** Point, Area, List — nothing else.
  "Area" is one tool; while it is active you switch between add and
  remove below it.
- **One button at the bottom:** the row at the bottom counts what is
  selected, has "Clear" and ONE button "Compute loop" or "Compute
  route". What a tap on a trail changed is said in the same row with
  Undo — the bar above it used to cover "My location".
- **"Adjust" in two tiers:** bike, time and climb at once; what you set
  once (hiking trails, list radius, preferences, filling in paths
  online) is folded away under "Fine-tuning".
- **The flags are always there:** the start flag also at your location,
  the end flag as soon as an end is set. A tap on a flag opens the same
  choice as its row.
- **The same words everywhere:** the long press says "Start here",
  "Destination here", "Via point here"; trail and place sheets "As
  destination", "As start" (and for a place "As via point"). "As
  destination" computes at once — with the planner open it is the end of
  exactly this plan, without asking.

## One button to ride, one end

*Version 0.171.0, 2026-11-13*

- **Result and start in one:** the planner's result shows the totals as
  four tiles (distance, climb, trails or descent, time), the profile
  below and the switches as chips: record, watch, screen on. One tap on
  "Start ride" — the second sheet with the switches is gone. The app
  remembers your choice for next time.
- **One end:** in the follow view the button is now "End ride". If a
  recording runs along, it asks whether everything should end or only
  the navigation.
- **Visible on the way:** a line above the buttons says what is running
  — recording, watch, jumps on. "Trail starts" and "Trail ends" sit
  there as a button with a word.
- **Phone in a pocket** (with the wheelie detection under test): a chip
  says whether the phone is on the bike or in a pocket; after a minute
  or two of calm riding the app also recognises the pocket by itself.
  In a pocket there are no wheelies or stoppies any more, a jump only
  with a hard landing — and the mount from the pocket is no longer saved
  for the next ride.

## Jumps and wheelies on the watch

*Version 0.170.0, 2026-11-13 (watch app 1.6.0)*

- **A short cue, no new page:** when the phone detects a jump, wheelie
  or stoppie, the watch shows it for 3 seconds at the top of the map,
  such as "Air 0.9 s" or "Wheelie 12 m". Then the trail is back. If the
  watch is asking a question, the question wins. At most one cue every
  10 seconds, and only while it is fresh — a message to the watch takes
  a few seconds.
- **A sign while detection runs:** a small dot with an arc sits at the
  left edge of the map while the phone detects and has learned its
  mount. If it is missing, the phone is not detecting right now.
- **The "Jumps" page** still appears only with the first best value.

## Long routes no longer crash the watch

*Version 0.169.1, 2026-11-13*

- **At most 800 points to the watch:** a very long or very winding route
  could crash the watch app while loading — the test bench showed it from
  1750 points. The app now simplifies a route for the watch to at most
  800 points. That leaves enough room for the watch to accept a new route
  on the way, too. On long routes the line on the watch gets a little
  coarser; bends are kept.

## The watch log

*Version 0.169.0, 2026-11-12*

- **When the watch app gets stuck, it can tell (0.169.0):** The watch
  app remembers its last 120 steps — which button, which menu item,
  which message, whether there was GPS and whether you were on the
  route, with the seconds since it started; no position, no names. The
  log comes to the phone with every ride and after a crash of the watch
  app, and stays there. When you report a bug with the light bulb, the
  dialog offers to attach the log — only if you tick the box, and it
  shows you the list first. That way a problem from the trail can be
  replayed at the desk instead of having to ride it again. Needs the new
  watch app 1.5.0.

## The watch app checks its own flows

*Versions 0.168.1–0.168.3, 2026-11-11 to 2026-11-12*

- **Phone and watch talk by the script (0.168.3):** every conversation
  between the app and the watch — route across, recording, the ride back,
  going off route, ending — is now written down once, and both sides are
  checked against it. The emulated watch is also as slow and unreliable as
  Garmin Connect in the field: messages take seconds, get lost or reach a
  closed watch app. Found and fixed in the watch app: when the phone asked
  for a waiting ride while the watch was starting, the ride only went
  across at the next start — now it goes as soon as the route has loaded.
  Nothing changes in the app.

- **Phone and watch on the test bench together (0.168.2):** the real
  connection to the watch can now be checked without a watch and without a
  ride — the app in an emulated phone, the watch app in Garmin's simulator.
  Route across, recording, pause, going off route, a new line and the ride
  back all run there automatically. Nothing changes in the app.

- **Under the hood of the watch:** buttons, menus, deadlines and messages
  from the phone now run through a flow part of their own that the tests
  play through without a watch on the wrist — recording, pause, trail marks,
  the question about a new line, waiting for the phone at start and sending
  the ride. On the wrist everything looks as before; nothing changes in the
  app.

## The watch gets the nearest line without anyone navigating

*Version 0.168.0, 2026-11-10*

- **Free riding with a line:** if the watch has no line and the phone has no
  navigation target, the phone looks for the trail whose line is nearest to
  the watch (800 m range, at least 250 m long) and sends it. Nothing in range,
  the watch keeps its own track.
- **Already before START** the watch counts distance, minutes and climb, and
  draws the last 25 minutes faintly in moss. Storage still starts at START.
- **When the watch drifts off such a line** it reports where it is, and the
  phone sends the next trail in range — the watch asks first.
- **The watch app (1.3.1) ships no invented test route:** with no line it
  starts in free riding.

## The watch asks before a new line takes over

*Version 0.167.0, 2026-11-11*

- **When the watch drifts off its line**, it tells the phone where it is, and
  the phone replans the route from there — the same thing the “Replan route”
  button does. Until now the old line simply stayed, and nobody noticed.
- **The watch asks first:** “Route from your position?” START or BACK decline
  the new line, and anyone who does nothing accepts it after eight seconds. At
  the start, while loading and in free riding it still takes it quietly.
- **It only asks when a ride is actually running.** A watch app that doesn’t
  know the question yet (older than 1.3.0) is left alone.

## A scanned QR opens the buddies screen

*Version 0.166.0, 2026-11-11*

- Scanning an invite QR with TrailBuddy already installed goes straight to the
  buddies screen: the inviting name sits in the search box and the search runs
  right away. Until now everyone landed on the download page and had to search
  by hand.
- Without TrailBuddy on the phone nothing changes: the page to download it.
- No account yet? Sign in first — the invite waits until then.
- The web app understands the same suffix: `?invite=` opens its buddies screen
  with the name.

## The watch says what it is doing

*Version 0.165.0, 2026-11-11*

- When the line is more than half a kilometre away, the watch now shows the
  whole route fitted into the circle, the next rejoin point as a dot and a
  dashed line to it. Until now the map stayed empty in that case and only the
  distance was shown.
- The navigation bar on the phone says whether the watch is connected and
  whether it is recording or paused. The watch reports this itself; the phone
  never asks it.
- If the watch reports a place more than 200 metres from the phone, the dot in
  the bar turns red and the bar says it in words.
- The watch names its own version in its greeting (1.3.0), so the phone can see
  which build is actually running.

## Inviting buddies: a QR code instead of typing

*Version 0.164.0, 2026-11-09*

- „Invite buddies“ now shows a QR code that the phone next to you scans with
  its camera. It carries only the name of the inviting buddy, no version
  number — the code stays valid even when the app is downloaded from
  somewhere else later.
- The page the code opens explains the way: load the app, create an account,
  open Buddys, search for the name, send the request. Anyone who already has
  TrailBuddy needs no new app and searches right away.
- On iPhone or on a computer the page shows the web app instead of the
  Android file.
- Without a scanner it works as before: share the invitation as text.

## Big offline areas load without straining the phone

*Version 0.163.1, 2026-11-08*

- The map and the offline areas run on a newer MapLibre release. When
  downloading a large area, the phone used to remember every request
  until it ran out of room — the download broke. Now it lets go of them
  once they are done.
- Switching between maps no longer leaves invisible leftovers of the
  old map in the background.
- The build for the APK works again: Gradle fetches its package in the
  smaller form, and Kotlin now comes straight from the Android toolchain
  instead of an extra plugin.

## The planner takes your transfers seriously

*Version 0.163.0, 2026-11-07*

- Connections and uphill trails are now part of the network along their
  whole line. The planner can join them midway where a path crosses.
  If a map path covers a transfer only in part, the planner still uses
  it.
- The planner prefers transfers and uphills even more than before —
  that is exactly why you entered them.
- A trail ends next to the transfer? The planner now takes it instead
  of jumping across the terrain to the nearest junction. Every metre
  without a path now counts as pushed and costs extra, because there
  may be thorns, rock or nothing at all.

## Start and stop recording on the watch

*Version 0.162.0, 2026-11-07*

- On the Garmin watch you now control the recording yourself, like
  Garmin's own activities: START begins it, START again pauses. While
  paused, a menu offers Resume, Save and Discard. A discarded ride is
  gone completely.
- The lap button (BACK) marks "trail starts" and "trail ends" on the way.
  After the end you can keep the trail or discard it. The marks come to
  the phone with the ride, and the split sheet treats them like the
  phone's own.
- The top of the map always shows what the recording is doing: START,
  PAUSED, TRAIL or a red dot. Up and down flip the pages, holding UP
  zooms the map.
- If TrailBuddy is running on the phone, it records too as soon as you
  press START on the watch, and it stops with the watch.
- A loop the phone wanted to send to the watch sometimes never arrived,
  and the watch only showed "Free ride". Now the watch keeps asking while
  on a free ride, and the route follows.
## Name the trail while you ride

*Version 0.161.0, 2026-11-07*

- When you tap "Trail ends" during a recording, the app asks right away
  what the trail is called. After the ride the name is already in the
  split sheet — no more guessing in the evening which section was which.
- If the app already knows the stretch (your trail or a buddy's, or you
  named it earlier today), the name is already in the field. One tap on
  "Save" is enough.
- "Save, next one starts" for two trails back to back, "Later" if you'd
  rather keep riding, and "Discard" for a mark you set by accident.
- Ride a trail twice and the split sheet shows it once, with "ridden 2×"
  — also when it is already in the network. Before, the second run
  became a new trail next to it.

## The watch rides on its own

*Version 0.160.0, 2026-11-07*

- The TrailBuddy app on the Garmin watch now also starts without the
  phone and without a navigation: without a route it shows your own
  track, speed, distance and climb.
- The watch records every ride itself — position, altitude and time, no
  heart rate. When you end it, the ride goes to the phone if it is
  there; otherwise it waits on the watch until you next open the watch
  app with the phone nearby. The watch deletes it only once it is on
  the phone.
- On the phone it is listed under “My rides” as “From the watch” — like
  any other ride to split and export. If you recorded the same time with
  the phone too, the phone's ride is kept. Garmin gets none of it, and
  no Garmin activity is created.

## New contact address

*Version 0.159.1, 2026-11-07*

- The imprint, the privacy policy and the account deletion page now
  name macbuchi.apps@gmail.com as the contact.

## Loaded on the way stays

*Version 0.159.0, 2026-11-07*

- What the planner fills in from the map host with reception now stays
  on the device — before, it was gone when the app closed. Plan in the
  same spot again and no network is needed; so your offline network
  grows bit by bit where you ride.
- "My areas" shows one line per region for it, "Loaded on the way",
  with its size and "Clear". It is not an area: no outline on the map,
  and "Update" does not fetch it again.
- When there is a newer map version, the planner fetches only the
  pieces it needs right then, the next time you plan with reception.
  Above 50 MB per region, what you have not needed the longest goes.

## Planner: a route is called a route

*Version 0.158.1, 2026-11-07*

- When the planner computes towards a destination, the sheet says
  "Route" while it computes — before, it said "Loop" and "Computing the
  loop …" until the result arrived. The settings are then called
  "Route settings".
- When no saved area covers the way, the message now says "from the
  start" instead of "from your location" — the start can also be a
  tapped point or a trail head.

## Airtime among buddies (test)

*Version 0.158.0, 2026-11-07*

- If you switched on the detection of wheelies, jumps and stoppies under
  “About TrailBuddy”, you now find a new switch below it: “Share airtime
  with buddies”. It is off by default.
- Switched on, the app shares per trail your best airtime of one run and
  your longest jump (with the month, no day) and your airtime of the last
  30 days — no ride, no place, no max G. It is computed on the phone.
- The trail sheet then shows “Airtime among buddies” with the top three
  and your place, and “Trail done” your place for this run. Your buddies
  show their airtime of the last 30 days and titles like glider pilot,
  frequent flyer, trail king and ground crew. A game, not a record — and
  you only see buddies who share too.
- Turning it off deletes what you shared.

## Navigation: closer in, a longer bar

*Version 0.157.1, 2026-11-07*

- A navigation started from “My rides” while the map showed all of
  Europe sometimes stayed zoomed out that far. Now it zooms back in with
  the next position.
- When the navigation ends because you are far off the route, the bar
  with “Resume” now stays 30 instead of 10 seconds. It says the
  recording keeps going only when one is actually running.

## Re-plan the route, leave the route

*Version 0.157.0, 2026-11-07*

- When you are more than 100 m off the route while navigating, “Re-plan
  route” sits next to “Back to the route”: the app computes the rest
  again from where you are, up to the next trail head ahead — without a
  trail ahead, to the destination. All trails of the route stay in, only
  the way there is free. So you don't have to set every point exactly
  the way you will actually ride.
- The new route turns back only if that is clearly shorter; otherwise it
  carries on in the direction you are riding.
- The watch gets the new route by itself, and so does the notification.
- When you are more than 500 m off the route, the navigation ends by
  itself — only after you have been on the route once. The recording
  keeps going, and “Resume” brings the route back. This also works when
  the app has been swiped away.
- You set both distances in Profile under “Navigation”; ending can also
  be switched off.

## Screen on while recording

*Version 0.156.0, 2026-11-06*

- During a ride a sun button sits above the flag: tap it and the screen
  stays on as long as the ride runs. Tap again and it may turn off. The
  app remembers the choice for the next ride; it starts switched off so
  a phone in the pocket doesn't drain its battery.
- If a navigation ends while the ride goes on, the screen stays on when
  the ride holds it.

## "Spaßig" takes trails along the whole way

*Version 0.155.2, 2026-11-06*

- On a longer route in the "Spaßig" style, the planner only saw trails
  within about 12 km of the start. So it took trails with a large detour
  early on and later rode past trails right next to the route. Now trails
  along the whole way count, and those with the smallest detour come
  first.

## Two quiet errors fewer

*Version 0.155.1, 2026-11-06*

- When a ride started, the list of trails TrailBuddy offers to confirm
  along the way could fail to save — two writes got in each other's way.
  They now run one after the other.
- If the sign-in in the browser has expired after a long break, the app
  still takes you to the login, but no longer sends an error report.

## The watch no longer shows the old route first

*Version 0.155.0, 2026-11-06*

- When the phone opens the TrailBuddy app on the Garmin watch, the watch
  first shows the TrailBuddy logo as a loader until the new route has
  arrived, instead of briefly showing last time's route. Below it, the
  watch shows how far the transfer has got. If the phone doesn't answer
  within 8 seconds, the watch shows its stored route as before.
- If you end the navigation on the phone, the watch app closes. If you
  end it on the watch, it ends on the phone too. A running recording
  keeps going and is saved on the phone as before.
- The route no longer goes to the watch twice when the watch checks in
  while it is still on its way.

## The watch knows where you are right away

*Version 0.154.0, 2026-11-06*

- Until the Garmin watch has its own GPS, it uses the phone's position:
  it shows straight away where you are and how far it is to the trail and
  to the finish, instead of waiting. The arrow is hollow then, with
  "PHONE GPS" above it. That stops with the watch's first own GPS fix.
  The position stays on the watch and is not stored.
- If the watch app and the phone app don't match, the phone doesn't send
  the route at all and says which side is out of date — instead of just
  "The watch didn't answer".

## The watch stays stable

*Version 0.153.2, 2026-11-05*

- The TrailBuddy app on the Garmin watch crashed shortly after starting
  ("IQ!") while it was still waiting for GPS: the route overview was too
  much computing for the watch. It now works out the overview once and
  then only draws it.
- The route goes to the watch in a more compact form — half as many
  numbers as before. That saves transfer time and memory on the watch.
  If the transfer breaks off halfway, the missing parts are sent again
  on their own.
- If the watch can't load a route (not enough memory, or the app crashed
  with it twice), the phone sends it once more, simplified; if that
  fails too, it tells you. Navigation on the phone carries on either way.
- At the bottom of the watch, distance and climb now fit inside the
  round edge.
- Important: update the watch app and the phone app together — the new
  watch app only understands routes from the new phone app.

## The bike's angle is right again

*Version 0.153.1, 2026-11-05*

- At the end of one ride, the wheelie detection had stored the phone's
  position on the bike twisted and afterwards showed angles that were
  too small: tilting by 90° showed as about 35°. It now learns the
  direction of travel only once the bike has also braked, and keeps a
  newly learned position only once it is well backed. Until then the
  old one stays.

## The watch shows more and counts right

*Version 0.153.0, 2026-11-05*

- On the Garmin watch, the climb "to finish" now matches the phone.
  Until now, hilltops on straight paths could get lost when the route
  was made smaller, and the watch showed too little.
- Before the watch has GPS, it shows the whole route as an overview,
  with start, trail heads, length and climb, instead of only "Waiting
  for GPS".
- When a new route arrives from the phone, the watch vibrates once,
  briefly.
- On the watch's number pages the labels sit further apart and no
  longer run into each other; the test line with battery and memory is
  gone. Long trail names get a smaller font before they are cut.
- During navigation, the phone now shows a watch icon while the route
  goes to the watch. Its dot shows the state, a tap says it in words.

## The bike in the live window follows at once

*Version 0.152.3, 2026-11-05*

- The small window of the wheelie detection now shows the tilt with
  almost no delay: about 0.1 seconds instead of around 2.7. Whether the
  app detects a wheelie, jump or stoppie is still decided a second or
  two later as before; only the display is faster.

## The route reaches the watch sooner

*Version 0.152.2, 2026-11-04*

- When the navigation start sheet finds the watch, the app already works
  out heights and junctions for the watch while you are still reading.
  After "Go" the route goes across without waiting again.

## The watch stays connected more reliably

*Version 0.152.1, 2026-11-04*

- Re-plan on the way while the old route is still going to the watch,
  and the new one now arrives afterwards — before, it could get lost.
- While the phone waits for the watch, it asks again a few times instead
  of waiting for an answer that was lost.
- If Garmin Connect restarts during the ride, the app finds the watch
  again by itself.
- The start sheet says "Looking for the watch …" until it is clear
  whether a watch is connected.

## The watch fetches the route by itself

*Version 0.152.0, 2026-11-04*

- If TrailBuddy is closed on the Garmin watch when navigation starts,
  the watch now asks "Open TrailBuddy?". After you say yes, the route
  arrives by itself — before, it was silently lost although the phone
  thought it had been sent.
- The app only says "Route on the watch" once the watch has confirmed
  it. If the watch does not answer, the bar says so; open the watch app
  later and it fetches the route.
- Start a new route on the way and it goes to the watch without further
  steps. If the watch briefly loses the connection, the phone checks
  afterwards that it still has the right route.
- Opening the app does not prompt the watch — only starting navigation
  with "Show on the watch" does.
## Libraries refreshed

*Version 0.151.1, 2026-11-04*

- Nine building blocks of the app brought up to date, among them the
  server connection, location, notifications and the local database.
  Nothing visible changes for you.

## Junctions on the Garmin watch

*Version 0.151.0, 2026-11-04*

- The route on the watch now shows a short grey piece of the path that
  branches off at every junction. You see where you can turn and where
  the route goes on — without a map and without turn instructions.
- The paths come from your saved areas (with reception also from the
  server) and from the trails you see in the app.
- If the watch does not answer, the phone now says after 20 seconds at
  most that the route did not arrive — before, it waited silently.
  Sending no longer stalls the map.
- With a paired Garmin watch the app crashed as soon as the navigation
  start sheet asked for the watch. Fixed.

## The route on your Garmin watch

*Version 0.150.0, 2026-11-04*

- With a Garmin watch running the TrailBuddy watch app, the switch “Show
  on the watch” appears when you start a navigation. The route then goes
  to the watch once via Garmin Connect, and from there the watch navigates
  on its own — even if the phone sleeps in your pocket or the connection
  drops. The bar says “Route on the watch” once the watch has stored it.
- With the test detection, the ride's best values (longest airtime,
  longest wheelie, largest angle) go to the watch as numbers.
- The watch app is not in the Garmin store yet; until then the GPX export
  stays the way onto any Garmin watch.

## Fewer false wheelies

*Version 0.149.1, 2026-11-03*

- Wheelie detection behind the test switch now needs the front 20° up
  instead of 15°. On almost five hours of test rides every real wheelie
  was still found, and of seven false ones only one remained.

## Values on the trail — to try out

*Version 0.149.0, 2026-10-31*

- With the switch “Detect wheelies, jumps and stoppies (test)” the app now
  counts what it detects on a trail: airtime (all jumps together and how
  many), the hardest landing in G, wheelies with the longest in metres and
  stoppies with the steepest angle.
- While navigating, the values stand above the band on the trail, after
  every jump the app shows “AIR 0.8 s · 2.9 G” for two seconds, and “Trail
  done” shows them again at the end. The notification names them on the
  trail as well.
- The split sheet writes the values next to every trail of the ride, “My
  rides” next to every ride.
- What you answer with “Wasn't one” does not count. A jump only counts when
  it is plausible — riding before and after, the bike upright afterwards.
- The landing now measures an impact that lasts a little instead of a
  single reading: a rattling mount no longer makes a hard landing.
- Below the switch there is a sentence about the risk: only ride what you
  can ride safely — the numbers are estimates. Everything stays on the
  device, nothing is shared.

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
