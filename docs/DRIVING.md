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
The chase camera follows the car and pulls back as speed rises. Mouse,
right stick and touch still orbit it.

Press interact again to get out. Either door or the space behind the car
must fit the hero capsule; if all are blocked, the driver stays inside.
The car coasts to rest and remains a solid body that heroes collide with
and other driven cars can push. It can be entered again and disappears past 420 m from the
camera. Superpowers are available again after leaving the car.

Traffic brakes for samples across driven and abandoned cars' footprints.
Traffic cars remain inexpensive lane simulations: the player can collide
with buildings and physical cars, but ordinary traffic has no rigid bodies.
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
world scene and game controller need no driving setup. The crouched driver
sits inside the tinted cabin; it is a placeholder seated pose.

The driver continues receiving plain `HeroInput`. `PlayerSync` adds Drive
at the end of its mode list and appends model, paint and seed after wanted
stars/searching in snapshots (indices 15–17).
Remote cars draw at the interpolated hero position without local simulation.
Only occupied cars are network-visible; abandoned cars are currently local,
and traffic populations are local, so simultaneous claims across peers are
not arbitrated. New receivers also accept the original 13-field and wanted-only 15-field snapshots;
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
