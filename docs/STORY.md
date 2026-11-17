# The Borrowed Skyline

An original twelve-chapter campaign for NYC Heroes. A newly arrived hero
answers a call from **Mara Vale**, a night-shift repair dispatcher. The
**Tollkeepers** have stolen the city's emergency maintenance network and
sell access to streets, power and safe passage. Witness **Ivo Chen** has the
ledger that can expose them. Three lieutenants hold borough keys: **Nera
Flint** in Brooklyn, **Oren Pike** in the Bronx and **Sable Quill** on Staten
Island. Their boss, **Alden Voss**, believes keeping the lights on entitles
him to own everyone underneath them. The hero returns the network to the
people who built it. All characters, organization names and dialogue were
written for this game.

Walk into the **gold S** to start the next chapter. Purple contracts remain
available. One story giver is available at a time; completing it unlocks the
next. Completed chapters persist in Settings (`story_completed_v1`, 0–12),
including the web's immediate localStorage mirror. An interrupted chapter
restarts at its giver; intermediate steps are not saved. Ordinary completed
chapters cannot be retried for another reward. Failure or Abandon does not
advance the story. The final completion leaves the city contracts available.

Phone cards show a speaker initial, portrait color and short text. They
advance every eight seconds; **Enter / controller accept / Next** advances,
and **Skip call** skips the conversation. New calls also arrive between
objectives. Objective clocks wait during calls and city loading. Calls do
not pause the shared world or prevent movement.

## Chapters and geographic references

Coordinates are latitude, longitude (WGS84), converted by `Geo.to_world`.
Times are design targets of roughly 2–6 minutes including calls and normal
travel within each job, not timed playthrough measurements. Travel between
borough givers is free exploration and is not included. Use flight or super
speed for these longer journeys; the radar's edge-clamped S points the way.

| # | Mission | Start / main location | Play | Reward |
| --- | --- | --- | --- | ---: |
| 1 | A City on Loan | Times Square, 40.75835, -73.98565 | Meet the repair crew, fight collectors, fly south through three sky rings | $10,000 |
| 2 | Above the Noise | Fifth Avenue / Empire State, 40.74845, -73.98480 | Follow a rooftop flight route, intercept three airborne ID packets, return to the street | $12,000 |
| 3 | East River Receipt | FDR at East 34th, 40.74400, -73.97180 | Take the recovery car, drive to the approach, stop a ledger van, lose one wanted star | $15,000 |
| 4 | Someone Must Stay | Washington Street, DUMBO, 40.70330, -73.98940 | Protect Ivo for 65 seconds through gang waves, recover his evidence | $18,000 |
| 5 | Public Frequency | Unisphere, 40.74600, -73.84460 | Smash park-road relay cars, collect keys, broadcast above Flushing Meadows | $20,000 |
| 6 | No Free Ride | Surf Avenue / Coney Island, 40.57540, -73.98160 | Clear four guards, defeat Flint's charge rig, fly away with her key | $25,000 |
| 7 | Home Crowd | River Avenue / Yankee Stadium, 40.82740, -73.92570 | Protect an electrician for 45 seconds, defeat Pike's slam rig, take his key | $30,000 |
| 8 | Last Boat Out | St. George terminal approach, 40.64320, -74.07480 | Break relay cars, fight guards and Quill's charge rig | $35,000 |
| 9 | A Bridge for Everyone | Brooklyn Bridge Manhattan approach, 40.71210, -74.00490 | Take a maintenance car, drive to the roadblock, smash relays, fly across the bridge | $40,000 |
| 10 | The Last Collection | Astoria Park waterfront street, 40.77869, -73.92114 | Take a recovery car, stop a courier van, lose two wanted stars | $42,000 |
| 11 | Open Circuit | One WTC south plaza, 40.71200, -74.01300 | Clear five guards, smash the master relays, collect access and fly to Midtown | $45,000 |
| 12 | The Borrowed Skyline | Empire State Fifth Avenue entrance | Ascend, defeat Voss's charge/slam rig on the roof, return to Times Square | $50,000 |

The Queens cars use the actual park road at **40.74534, -73.84699**, about
214 m west of the Unisphere reference. Bridge flight rings follow the
existing modeled tower references at **40.7072684, -73.9983348**,
**40.7056860, -73.9963447**, **40.7041035, -73.9943545**, at 90/110/90 m.
The final roof uses **40.748365, -73.985914**, world approximately
**(-35, 314, 1070)**, on the Empire State's broad 313.4 m setback roof,
away from the antenna. Its ascent rings are 45–70 m above that roof. The return passes Times
Square at 400 m before descending to its 180 m finish, clearing intervening
skyscrapers.

### Checking the placements

The references were checked against the public city's version-7 binary
lod0 tiles (manifest build `6ae006e2`). For the original references, nearest
sidewalk / drivable lane distances in meters were: Times Square 5.0 / 23.9;
Empire State entrance 1.5 / 5.2; FDR 1.3 / 4.9; DUMBO 5.9 / 10.8;
Unisphere 7.2 / 214.6; Surf Avenue 3.0 / 12.4; River Avenue 8.1 / 14.7;
St. George 8.8 / 3.2; Brooklyn Bridge approach 5.4 / 1.3; WTC south plaza
70.7 / 84.3. Astoria was moved onto its checked road, from a reference
99.2 m inside the park. Queens cars were moved to the checked road too.
Vertical triangle intersections and live physics raycasts put the final
setback roof at 313.4 m. Its collision stays loaded during nearby elevated
story objectives, including at Low quality on phones.
Street heights are authored from those tiles; actual gangs and witnesses
raycast down from just above them, avoiding overhead roofs and signs.

Cars always snap to a **loaded drivable lane**, within 120 m of their
reference, preserving the lane's elevation and direction. If lanes or
collision are not loaded, spawning waits. `?story=n` travels to the start
with Game's ordinary city-loading and sidewalk-arrival behavior. It does
not start a car inside a building. No tiles need rebuilding.

## Objective API

All positions are absolute world meters. Constructors live in `Mission`:

- `drive_to(position, text, radius := 22.0)`: checkpoint requires Drive mode.
- `steal_car(position, text, marked := true)`: enter the mission's marked
  recovery car. With `marked=false`, any occupied car works.
- `chase(position, text)`: stop a fleeing relay van in 150 seconds. Its
  physical `DriveVehicle` follows loaded traffic lanes with a plain
  `HeroInput`, steering and reversing when stuck. Ram it or damage it with
  punches, speed rams or a damaging slam. It has 160 relay health. A target
  more than 350 m away for eight seconds fails; missing targets never win.
- `escape_wanted(position, stars, text)`: raises the real Wanted pursuit to
  at least that many stars and requires that many to decay. Ordinary crimes
  and renewed police sight can extend it. Two-star escapes include the
  integrated NYPD patrol cars; higher heat also allows roadblocks.
- `protect(position, seconds, text)`: an actual witness with 100 health,
  bounded two-person EncounterDirector waves every 18 seconds, at most six
  standing attackers. Nearby attackers deal seven damage per second each.
  Heroes can draw the attackers away or defeat them. Progress pauses beyond
  100 m; staying away for ten seconds fails. Witness death fails immediately.
- `destroy(position, count, text)`: disable every marked relay car. Lane
  placements remain at least seven meters apart, including when several
  authored positions project onto the same straight road segment.
- `fly_through(rings, text, radius := 22.0)`: enter the gold torus rings in
  order while in Flight mode, with a 120-second time limit.
- `boss(position, variant, text)`: a regular EncounterDirector fight with
  a powered thug (420 / 500 / 550 / 900 health). Launch attacks reduce health
  but cannot bypass the rig. Colored clothes, a name/health label and a gold
  1.2-second warning precede charges or an eight-meter ground slam. Jumping
  or flying avoids the slam. Rigs check ground ahead and stop at roof edges.

Mission-owned actors, rings and standing protection waves are removed on
finish, failure and abandon. A successfully acquired, occupied car survives
its theft step. Moving targets use the ordinary floating-origin group.
Only damaging hero attacks affect relay cars; NPC collisions do not report
crimes against the local player.

## Co-op and limits

Progress, phone calls, rewards and objective state belong to each player.
Story gangs and bosses use existing EncounterDirector ownership, authoritative
hit routing and nearby snapshots. Friends can help defeat them. Descriptions
append the boss variant after existing police fields, preserving old thug
and police descriptions. The slow windup animation also carries the remote
warning; ordinary movement snapshots carry charges. No hero movement or
network-input format changes are needed.

Recovery cars, relay vans, rings and witnesses are local mission actors,
like the existing contract pickups. Friends cannot see or damage another
player's relay vehicles or witness; shared car objectives are not implemented.
Traffic AI uses loaded lanes, not a global route planner, and a fleeing van
can get obstructed at complex junctions. Failure/Retry remains available.
There is no recorded dialogue, gunplay or custom imported art.

## Launch and tests

- `?story=1` … `?story=12` starts that chapter and travels to its giver
  (an explicit `?spawn=` keeps its own location). Jumps bypass locks for the
  session; they do not erase or skip saved chapters. Only the next unfinished
  chapter advances saved progress. Launch testing can still grant cash.
- `?story=reset` resets completed chapters; cash remains separate.
- Desktop equivalents: `-- --story=3 --quality=low`.
- `tests/story_test.tscn`: positive/negative paths for each new objective,
  ordered flight, tracked vehicle damage, chase timeout, witness survival
  and death, car retention, origin shifts, boss resilience, roof-edge safety and co-op
  descriptions, all twelve unlocks, immediate disk persistence and reset.
- Keep `missions_test`, `wanted_test`, `drive_test`, `combat_test`,
  `radar_test`, and `police_cars_test` passing. `combat_test` needs city tiles;
  in this sandbox use `-- --tiles_url=http://localhost:8060/tiles`.
- Export with `.niteshift/files/build-web`. Browser software rendering flags
  are documented in `.niteshift/services.yaml`.
- `?story_playtest=1` adds an opt-in QA pilot and read-only telemetry at
  `window.nycStoryState`. Set `window.nycStoryPilot=true` to drive ordinary
  hero input, or false to return to keyboard controls. This QA option renders
  3-D at quarter resolution while retaining full-size UI and allows up to
  120 physics ticks per drawn frame and skips covered 3-D draws during city
  loading, so software rendering does not slow the
  simulation clock. Ordinary play keeps its chosen quality preset. It never teleports,
  edits health, deals direct damage or advances objectives. It is a debugging
  aid, not proof that every possible route or co-op flow has been played.
