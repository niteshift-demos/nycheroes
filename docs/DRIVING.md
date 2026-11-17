# Driving

Walk close to the middle of a traffic car and press **G**, **R3** (right
stick click), or the touch **CAR** button. The traffic slot is removed from
its lane and intersection before the physical car takes over. The car keeps
its model and paint. Hijacking raises danger and emits
`Combat.report_crime(&"carjack", world_position, 1.0)` for the wanted system.

**W / left stick up** accelerates to about 30 m/s (108 km/h). **S / stick
down** brakes and then reverses to 9 m/s. **A/D / stick left/right** steers
relative to the car, including reversed steering when backing up. **Space /
A / BRAKE** is the handbrake: it slows the car while loosening lateral grip
for a slide. Steering and braking have most effect with wheels on the ground.
Steering eases at high speed, grip recovers progressively after a drift, and
the body rolls and pitches under load. Short floor snapping lets the car
leave crests and land again. The chase camera pulls back as speed rises
and looks behind the car while reversing. Mouse,
right stick and touch still orbit it.

Press interact again to get out. Either door or the space behind the car
must fit the hero capsule; if all are blocked, the driver stays inside.
The car coasts to rest and remains a solid body that heroes collide with
and other driven cars can push. It can be entered again and disappears past 420 m from the
camera. Superpowers are available again after leaving the car.

Traffic brakes for samples across driven and abandoned cars' footprints.
Traffic stays in a MultiMesh until a swept footprint touches it. A 16 m
world-space grid visits nearby rows, promotes contacted cars, and lets the
physics engine stop the player and push the abandoned car. Fast heroes,
punches and slams use the same promotion path. Traffic behind the wreck
waits using the existing footprint braking logic; there is no new lane-changing AI.

Cars have 100 health. Hard impacts slow and damage them, shake the camera,
throw sparks and play a metal/glass crash. Damage darkens the paint; below
40 health the hood smokes. At zero health, fire and a **GET OUT** warning
precede a blast by three seconds. The blast hurts a seated driver, launches
nearby cars and people, and leaves a solid, untakeable burned wreck.
Explosions near pedestrians report a crime. Engine pitch follows speed;
sliding tyres screech. Both loops use the existing web audio loop path.
Impacts above 4 m/s knock down pedestrians for four seconds (up to four
civilian ragdolls, then a fallen pose). Thugs and police use Combat's
network-aware launch/ragdoll path. Pedestrian hits report `vehicular_assault`
with severity 0.65 through
`Pedestrian.take_hit`; police hits use Combat's `assault_police` path. Gang
members do not add wanted heat.
There is no driver-ejection animation or extra fleeing driver yet.

## Implementation and co-op

`DriveVehicle` is a `CharacterBody3D` with gravity, floor snapping and sliding
contacts, on collision layer bit 64. It uses one instance of `PropMeshes.car()`
and the traffic/city material, including shader-driven wheels and lights.
`DriveMode` is created by Hero alongside the scene's movement modes, so the
world scene and game controller need no driving setup. The mannequin
uses its supplied Driving animation in the left driver seat, behind tinted glass.
The take-car hint appears only within 3.5 m of an available car.

The driver continues receiving plain `HeroInput`. `PlayerSync` adds Drive
at the end of its mode list and appends model, paint and seed after wanted
stars/searching in snapshots (indices 15–17), followed by health and body
roll/pitch (18–20).
Remote cars draw at the interpolated hero position without local simulation.
Only occupied cars are network-visible; abandoned cars are currently local,
and traffic populations are local, so simultaneous claims across peers are
not arbitrated. New receivers also accept the original 13-field, wanted-only 15-field and earlier driving 18-field snapshots;
all peers need the new build to see driving. Car and hero separately join
`floating`, so origin shifts preserve their world positions and velocity.

## Checking it

`godot --headless --path . res://tests/drive_test.tscn` uses a synthetic road
and a real traffic slot, without downloaded tiles. It checks takeover,
acceleration, steering, braking, reverse, leaving/re-entering, origin shifts
at speed and the remote car snapshot. Keep `hero_moves_test`, `traffic_test`,
`combat_test` and `coop_test` passing too.

Add `?car=1` (desktop: `-- --car=1`) to place a parked starter sedan 2.5 m
beside the spawn once the city loads. For a quiet road check, combine it with
`?car=1&spawn=420,20,-220,-29&quality=low&solo=1`; add traffic to check stopping
and hijacking. This option does not start driving: enter with the same
interact control as any parked car.


For a repeatable web crash check, use `?car=1&car_crash=1&quality=low&solo=1&spawn=420,20,-220,-29&traffic=1&peds=0&gangs=0`.
This opt-in fixture gives the starter 40 health and places one stopped traffic
row 38 m ahead after it settles. Enter with G and hold W to hit it and see
the fire countdown. Normal `?car=1` gives a full-health car.

`drive_test` also checks physical traffic impacts and speed loss, punch/slam
promotion, explosion/driver damage/crime, unavailable wrecks, contextual
hints, elevated traffic exclusion, fast sweeps and nearby-query cost with
180 indexed rows. `wanted_test` accepts the appended car state. Keep
`traffic_test`, `combat_test`, `wanted_test`, `hero_moves_test`, `radar_test`
and `audio_test` passing; tile-based tests can use
`-- --tiles_url=http://localhost:8060/tiles/` in this sandbox.
