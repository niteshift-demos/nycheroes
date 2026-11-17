# Wanted levels and police pursuits

Heroes keep flight, speed, swinging and slams. Fighting gang thugs is legal.
Hitting civilians or officers in front of a witness brings the police.

## Crimes and escape

`Combat.crime(kind: StringName, world_position: Vector3, severity: float)`
and `Combat.report_crime(kind, world_position, severity)` describe a crime
committed by **the local hero**, using world coordinates. Other systems can
report carjacking through this same API. Do not call it for remote visual
updates or NPC attacks: those would blame the wrong player.

A civilian or standing police officer within 45 m must have an unobstructed
view of the crime. The victim can be that witness. Civilian assaults add 0.65
heat; police assaults add 1.0. Stars are heat rounded up, capped at five.
Punches, speed rams and damaging ground slams knock pedestrians down for four
seconds. Repeated hits on someone already down add no heat. Harmless jump and
recovery shockwaves only scare civilians. At most four civilian ragdolls run
at once; additional victims use a fallen pose. No external assets were added.

Standing officers see the hero within 65 m when the world does not block the
ray between them. After five seconds without being seen, stars flash and show
SEARCHING. Officers walk toward the last known location; reinforcements pause.
Eighteen more seconds unseen remove one star, then each eighteen seconds
removes another. New witnessed crimes or police sight restart this clock.
Flying high or escaping around buildings works.

## Police and BUSTED

Officers arrive on loaded sidewalk lanes 22–65 m away, outside the camera view
or behind world geometry. One arrives every three seconds up to two per star,
with a hard cap of ten officers run by this player. They wear navy uniforms
and blue caps, with NYPD labels. At one star they chase and use melee to
subdue the hero; at three stars their chase and attacks are faster; five-star
heavy officers have more health and deal more melee damage. They reuse the
thugs' collision and curb climbing, animation, attack slots and hit replication.
There are no guns or new navigation meshes. Patrol cars join the response at
two stars (below).

A knockout while wanted shows BUSTED, clears the pursuit, and after two
seconds restores the hero to full health on a nearby loaded sidewalk. If no
sidewalk is available, recovery uses the current location. Officers go away
when the pursuit ends, they fall, or their suspect gets more than 180 m away.
Police defeats do not increase the gang defeat counter or emit `thug_defeated`.

## Co-op and floating origin

`Hero.wanted_stars` and `Hero.wanted_searching` are plain state sent by
`PlayerSync`; remote name tags and distant player markers show wanted stars.
`Wanted.stars`, `Wanted.searching` and `Wanted.stars_changed(stars)` expose the
local pursuit to other systems. `Wanted.busted` marks an arrest.

The current game uses distributed NPC ownership, not a single authoritative
host: each player runs their local encounters. Police follow that same model.
The encounter director allocates their net IDs, shares police descriptions and
20 Hz snapshots only with nearby peers, routes hits to their owner, and removes
copies that leave range. Police descriptions include the suspect peer ID and
response tier. Existing host handover preserves those fields; officers whose
suspect left end their pursuit. They never attack an innocent co-op partner.
Civilians remain local ambience, as before; they are not networked NPCs.

Crime positions, spawn locations, search destinations and respawn locations
are world coordinates. Officer bodies inherit thug floating-origin handling;
civilian ragdolls explicitly shift their simulated bones.

## Launch and checks

- `?police=0` disables local heat and police spawning, including `?wanted`.
- `?wanted=N` starts at 0–5 stars. On desktop use `-- --wanted=3`.
- Browser check: `?wanted=3&quality=low&name=Agent&solo=1&gangs=0`.
- `godot --headless --path . res://tests/wanted_test.tscn` checks crime,
  innocent gang fighting, bounded police spawning and pursuit, escalation,
  replicated police descriptions and hero state, searching, decay and BUSTED
  using a synthetic street (no city downloads).
- Regression scenes: `combat_test`, `pedestrian_flee_test`, `coop_test`,
  `hero_moves_test`. Import first with `godot --headless --path . --import`.

Foot officers use the existing direct steering and can get stuck behind
complex building corners. Search is deliberately lightweight: last known
location plus line-of-sight checks twice per second, rather than a city-wide
navigation graph. Precinct-specific respawns are future work.


## Patrol cars and roadblocks

At two through five stars the suspect's game runs at most **1 / 2 / 3 / 4**
patrol cars, in addition to the foot response. White sedans carry blue side
stripes, NYPD lettering and an alternating red/blue emissive roof bar visible
in daylight and at night. They reuse `PropMeshes.car()`, the car material and
the existing sound bank's CC0 sirens; no new assets or tile rebuilds are needed.
Their flashing shield blips use `Radar.add_node_blip`.

Cars appear on loaded **traffic** lanes 45–170 m away, outside the camera
frustum or behind solid world geometry. Sidewalk lanes are not driving lanes.
A bounded rotating scan checks at most 24 candidates per spawn attempt. A
physics shape check keeps spawns clear of buildings and existing physical
cars. At four or five stars, a moving driving suspect can also meet one pair
of parked cars across a road ahead. The pair is separate from the moving-car
cap; another roadblock waits at least 25 seconds and for the old one to clear.

`PolicePursuit` makes steering decisions five times a second. Far away, cars
follow the directed `TrafficLanes` graph, choosing the next street toward the
last known position. Within 45 m they steer directly and, against a driving
suspect, aim beside and slightly ahead of the car to ram or box it in. They
feed plain `HeroInput` into `DriveVehicle.drive()`, with the same acceleration,
grip, collision and floor physics as player cars. A stuck car briefly backs
up. NPC driving never reports its bystander impacts as the player's crimes.

Against a nearby foot suspect a patrol brakes, stops and deploys two existing
`PoliceOfficer` nodes through the encounter director. Those officers use the
same suspect ownership, hit replication and foot pursuit as reinforcements.
The stopped car is available to steal with G / R3 / CAR. Police-car theft
reports `steal_police_car` with severity **2.0**, using the usual witness rule.
The livery follows the normal driver snapshot; stealing removes the car from
the response fleet, and after leaving it follows ordinary abandoned-car rules.
As with other abandoned cars, stealing is local to the peer that owns that
physical car; remote patrol copies are visual state, not claimable bodies.

An occupied patrol sees its suspect within 65 m through the same world
occlusion ray as foot officers and resets the wanted escape timer. Searching
cars slow down and cruise lanes around their last known position; they do
not track the hidden hero's new location. Reinforcements pause while searching.
Police cars disappear when wanted clears, or beyond 360 m while unseen.

The encounter director shares a complete small fleet of plain descriptions
and state at 20 Hz with peers within 400 m. Copies interpolate world positions
and heading without physics or AI. Full fleets recover lost arrivals and
removals and support late joiners. A departing suspect's cars disappear rather
than moving ownership to an innocent player. All targets, lane points and
snapshots use world coordinates, and bodies join `floating` independently.

`res://tests/police_cars_test.tscn` checks every spawn cap, real driving pursuit,
foot deployment, sight, search memory, severity-two theft, stolen driver state,
roadblocks, despawn, floating origin and actual ENet fleet RPCs, using a
synthetic street. Keep `wanted_test`, `drive_test`, `traffic_test`, `combat_test`,
`radar_test` and `coop_test` passing. A browser check starts with
`?wanted=3&car=1&quality=low&name=Agent&solo=1`; enter the starter sedan with G.
`?police_profile=1` logs mean decision time per physics frame every 300 frames
(target below 0.3 ms/frame; excludes vehicle physics, rendering and tile updates).

Routing is deliberately local and greedy, not citywide shortest-path planning.
Cars can still get stuck at complex corners, blocked streets or dead ends.
They do not obey traffic lights during a pursuit and use direct contact for
ramming; there are no weapon attacks, tire damage or vehicle destruction.
