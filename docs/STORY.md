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
available. One story giver is available at a time. At a shared landmark it takes
priority over replayable contracts, so a contract cannot block the chain.
Completing a chapter unlocks the next. Pause → Missions lists all twelve chapters with ACTIVE / PASSED / AVAILABLE /
LOCKED status, saved campaign progress, and waypoints only for the active or
next available story chapter. Story objectives use the shared bottom-centre
subtitle HUD and results use its MISSION PASSED / FAILED banners. Phone calls
use the shared panel, button and font theme above the objective area.

Completed chapters persist in Settings (`story_completed_v1`, 0–12),
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
  punches, speed rams or a damaging slam. It has 160 relay health, backed by the shared chassis damage, fire and
  explosion path. Physical rams, punches, slams and wrecks all stop the relay. A target
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
Relay damage uses the shared vehicle crash/punch/blast API; criminal-driver
impacts do not report crimes against the local player.

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
  `window.nycStoryState` (including relay positions/health and witness health). Set `window.nycStoryPilot=true` to drive ordinary
  hero input, or false to return to keyboard controls. This QA option renders
  3-D at quarter resolution while retaining full-size UI and allows up to
  120 physics ticks per drawn frame and skips covered 3-D draws during city
  loading, so software rendering does not slow the
  simulation clock. Ordinary play keeps its chosen quality preset. It never teleports,
  edits health, deals direct damage or advances objectives. It is a debugging
  aid, not proof that every possible route or co-op flow has been played.

## Browser QA instrumentation

The opt-in `story_playtest` telemetry also reports cash, a simulation clock,
private room code, peer IDs, remote heroes (mode, wanted tag, model, paint and
car health), nearby thugs/bosses, and patrol cars. These are observations of
ordinary game state, not setters.

For controlled co-op checks after a mission, `window.nycStoryInput` may supply
ordinary input fields: `stick: [right, back]`, `move: [x, 0, z]`,
`aim: [x, y, z]`, `vertical`, and the boolean fields in `HeroInput`.
`flight: true/false` and `driving: true/false` request a toggle only when the
current mode differs. Vehicle telemetry includes wreck state.
`toward: [x, y, z]` converts a flight waypoint into aim/throttle each physics
tick, avoiding stale browser telemetry on slow software-rendered frames.
Delete `window.nycStoryInput` to return to the pilot or keyboard. This interface
exists only with `?story_playtest=1`; it cannot set position, health, cash,
wanted level, mission progress, or network state. The pilot clears roofs before
steep descents, crosses low park buildings at height, and approaches cars
within punching range instead of relying on the thug-only melee lunge.

## Recorded browser QA — 2026-11-17

Godot 4.7.2 web export, Chromium/SwiftShader, Low quality, real public city
tiles, `?story=n&story_playtest=1`, zero ambient pedestrians/traffic and the
ordinary campaign actors. The opt-in pilot and manual overrides feed
`HeroInput`; no positions, health, rewards or objectives were edited. Each
run starts with cash zero. Final cash also includes $50 thug bounties.
Times are wall time from observed mission activation, excluding initial city
loading and including calls, screenshots and manual navigation.

| Chapter | Browser result | Wall time | Chapter reward | Final cash | Stuck / retry |
| --- | --- | ---: | ---: | ---: | --- |
| 2 | MISSION PASSED | 59.7 s | $12,000 | $12,000 | Pilot descent adjusted; fresh run passed. |
| 4 | MISSION PASSED | 102.8 s | $18,000 | $18,400 | Witness 100%; no softlock. |
| 5 | MISSION PASSED | 175.8 s | $20,000 | $20,000 | Manual detour around park building. |
| 6 | MISSION PASSED | 33.3 s | $25,000 | $25,250 | No softlock. |
| 7 | MISSION PASSED | 88.1 s | $30,000 | $30,350 | Overhead spawn bug fixed; fresh run passed. |
| 8 | MISSION PASSED | 366.9 s | $35,000 | $35,600 | Manual flight around raised roadway; no retry. |
| 9 | MISSION PASSED | 64.3 s | $40,000 | $40,000 | First detour failed after target despawn; fresh run passed. |
| 10 | MISSION PASSED | 159.2 s | $42,000 | $42,000 | Manual full-throttle catch; escape completed. |
| 11 | MISSION PASSED | 296.6 s | $45,000 | $45,250 | First flight timed out at WTC; routed retry passed. |

Chapters 1, 3 and 12 were reported browser-complete by the prior story task;
they were not repeated in this QA pass. Chapter jumps intentionally do not
advance saved story progress when earlier chapters remain unfinished.

The chapter 7 failure exposed a second, higher gang-spawn raycast selecting
an overhead structure after the story had selected the street. Story bosses
and protection attackers now retain the short street search. Mission cleanup
also accepts freed actors before applying a typed callback. Both have story
regressions. Pilot-only fixes cover steep descents, low buildings, vehicle
punch range, elevated targets and catching moving vans. Chapter 11's recorded
retry used bounded flight waypoints around WTC before returning to its normal
rings. Browser screenshots and co-op status are recorded in the QA pull request.

### Two-browser co-op QA

Two isolated Chromium sessions joined private rooms through the local signaling
service. The guest received the host's sedan model 0 / paint 0, movement, and
crash health (100 → 61.0827 on both sides). Wanted tags carried the host's count;
three-star snapshots included two patrol copies and six officer copies with
matching positions and damage. Both browser views are attached to the QA PR.
The guest alone also defeated the host-owned Flint rig: host health observations
were 420 → -30 and the host advanced to its exit flight while supplying only
hovering input.

### Follow-up pursuit and destruction QA — 2026-11-17

Two Chromium/SwiftShader windows, both partly visible, used a private room and
the ordinary `?wanted=3&car=1&story_playtest=1` launch options. The driver took
the starter with G; the guest used ordinary flight input above the avenue,
looking back toward the driver and approaching patrols. No health, position,
wanted or network state was edited. The original host rejoined between runs;
the room host migrated to the observer while the suspect continued to own
its own police, as the distributed encounter model intends.

The guest camera showed the wanted driver and moving police cars without
buildings or trees hiding the pursuit. At guest simulation times 1224.817 and
1229.083, the driver moved from (455.404, 18.617, -240.440) to
(470.563, 18.908, -268.609); one patrol moved from
(417.013, 17.831, -180.132) to (462.262, 18.800, -254.199).
The driver's tag rose from four to five stars and its car health fell from
83.101 to 41.876, then zero as patrols collided with it.

The guest saw the explosion effects and charred wrecks after the driver exited
and destroyed patrols left their active fleet. At time 1245.617, the guest had
both a burnt sedan (paint 0) at (492.372, 18.964, -317.688) and a burnt patrol
(paint 12) at (477.515, 18.999, -281.215); a second burnt patrol followed.
At 1280.8 the bounded wreck list was empty. Guest-side screenshots of the
pursuit, blast plume and settled wrecks are attached to the follow-up PR.
The brief orange fireball was also seen in an earlier capture at the lower
edge of the view; the selected sequence shows the later expanding plume.

Before this fix, an occupied car exited Drive before sending a destroyed
state, and a burned patrol left the fleet before that state could be sent.
The new bounded recent-wreck list in PlayerSync fixes both paths; see
DRIVING.md for lifetime, distance and local-only limits. QA telemetry now
also reports `loading` and received visual `wrecks` so captures can distinguish
city loading, a missing occupied-car copy and an actual shared wreck.

Limits: this uses G takeover of a launch-supplied starter, rather than a live
traffic-slot carjack. Phones, gamepads and Windows GPUs were not exercised.
Private connection attempts can time out while one maximized browser fully
covers the other; keeping both windows partly visible lets their simulation
clocks and networking continue. Wait for city loading and private-room spawn
placement before driving away; otherwise arrival can interrupt the setup.
