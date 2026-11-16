# City contracts and cash

Heroes keep every power. Walk into a purple contract marker to start a
local job; the title and introduction appear above the gold objective.
Reach gold checkpoints by running, super speed, jumping, swinging or flying.
The race checkpoints also accept cars: Drive mode keeps the hero at the
car, and all checkpoint checks read `hero.world_position()`. Bridge Run
radii include the road deck as well as airborne approaches.
Pickup diamonds disappear when collected. Timed legs show a countdown;
running out of time or getting knocked out fails the job. Use **Retry job**
after a result, or **Abandon** during a job. These buttons work on touch.
The Side job button offers another random street crew near you whenever
no mission is active; move near a road if none is available.

| Launch id | Giver | Route | Cash |
| --- | --- | --- | ---: |
| `times_square` | North end of Times Square | Defeat two separate 3-person Broadway gangs | $5,000 |
| `rooftop_courier` | Fifth Avenue at the Empire State Building | Empire State roof, then One World Trade roof in 150 seconds | $8,000 |
| `bridge_run` | Manhattan approach to Brooklyn Bridge | Four timed checkpoints across to Brooklyn | $4,500 |
| `central_park` | Bethesda Terrace | Collect eight power cells around the terrace | $3,500 |
| `broadway_dash` | Times Square, east of the starting spot | Two short timed checkpoints south along Broadway | $1,500 |
| — | Side job HUD button | A random nearby street crew of 3–5 thugs | $1,200 |

The green cash display sits below the wanted stars and counts toward the
new balance when it changes. Being BUSTED fails an active mission and costs
10% of the balance, rounded up and capped at $1,000; the fine also applies
outside a mission. Police officers never pay gang bounties.
Mission rewards are paid once per successful run; routes are replayable.
Every defeated thug within 120 m grants a $50 local assist bounty (including
thugs defeated by a friend). Cash survives visits through Settings' `cash`
key, including its immediate localStorage mirror on the web. Mission
progress does not persist. Cash is capped at $999,999,999.

## Launch options

`?mission=<id>` starts a catalog mission immediately, without teleporting
the hero. Combine with existing `?spawn=x,y,z,yaw` if testing another part
of the city. `?cash=N` sets and saves a nonnegative balance at startup.
Both work as desktop `-- --mission=<id> --cash=N` too. Example:

```
?mission=broadway_dash&cash=12450&solo=1&quality=low&name=Agent
```

The clock waits while the hero is frozen for city loading or Go to travel;
opening a menu pauses it only when the existing single-player pause does.
Givers use a 10 m horizontal radius and allow 30 m of street elevation
variation around the geographic reference. They trigger on entry: after finishing, leave the marker and re-enter,
or press Retry job. They never repeatedly restart under a stationary hero.

## Public API and co-op

`class_name Wallet extends Node`, available at `Game.wallet`, `Game/Wallet`
or the `wallet` group:

- `balance: int` (read it; mutate through the methods to save and signal).
- `add(amount: int, reason: String) -> void`: positive earnings only.
- `spend(amount: int) -> bool`: rejects negative prices and overdrafts.
- `signal changed(balance: int)`.
- `static format_cash(amount: int) -> String`.

`class_name Mission extends Resource` has exported `id`, `title`, `intro`,
`reward`, `giver: Vector3`, and `steps: Array[Dictionary]`. Step constructors:

- `Mission.go_to(position: Vector3, radius: float, text: String)`.
- `Mission.defeat_gang_at(position: Vector3, count: int, text: String)`.
- `Mission.reach_in_time(position: Vector3, seconds: float, text: String, radius := 35.0)`.
- `Mission.collect(items: Array[Vector3], text: String, radius := 9.0)`.

`class_name MissionDirector extends Node`, at `Game.missions`,
`Game/Missions`, or group `mission_director`:

- `start(id: String) -> bool`, `start_mission(mission: Mission) -> bool`.
- `retry() -> bool`, `side_job() -> bool`, `finish(success: bool) -> void`.
- `current_target() -> Vector3`: absolute world position, `Vector3.INF` idle.
- `signal mission_started(id: String)`.
- `signal mission_step_changed(id: String, target_world_position: Vector3)`.
- `signal mission_finished(id: String, success: bool)`.
- `markers() -> Array[Dictionary]`: `position`, `label`, `color` for current
  checkpoints/pickups or idle givers. All positions are in world meters.

Missions and money belong to each local player, never PlayerSync. Each
peer's EncounterDirector already owns and replicates its locally spawned
thugs, including a client's mission crews. Friends can damage those thugs
through Combat's existing owner-routed hits. Only the initiating player's
tracked crew advances their objective; unrelated gang defeats do not count.
Mission crews spawn only when their tile's collision is ready and the hero
is within 100 m. If a tracked thug disappears before completion, the mission
fails so despawning cannot award cash. Abandoning removes surviving members of your mission crew through the
normal replicated removal path; retry creates a fresh crew. Defeated bodies
keep their usual cleanup lifecycle.
The mission definitions, timer and pickups are local, so friends do not see
your markers or collect your items. A live two-browser mission fight and
host migration during a mission have not been verified.

## Coordinates

WGS84 coordinates were checked on 2026-11-16 against the linked place
records, then converted using `Geo.to_world`. Giver and checkpoint offsets
are authored around those locations; y is gameplay altitude above sea level,
not latitude/longitude elevation. Bridge tower checkpoints reuse the verified OSM tower coordinates already
in `tools/citygen/bridges.py` (credited in CREDITS.md).
Ground encounters use EncounterDirector's
raycast; rooftop goals use generous airborne radii around the roofs, so
flight can deliver without landing on a spire.

| Landmark | Latitude, longitude | Reference |
| --- | --- | --- |
| Times Square | 40.7575, -73.9858 | [Place coordinates](https://en.wikipedia.org/wiki/Times_Square) |
| Empire State Building | 40.7483, -73.9856 | [Building coordinates](https://en.wikipedia.org/wiki/Empire_State_Building) |
| One World Trade Center | 40.71306, -74.01333 | [Building coordinates](https://en.wikipedia.org/wiki/One_World_Trade_Center) |
| Brooklyn Bridge | 40.7057, -73.9964 | [Bridge coordinates](https://en.wikipedia.org/wiki/Brooklyn_Bridge) |
| Bethesda Terrace | 40.774123, -73.971135 | [Terrace coordinates](https://en.wikipedia.org/wiki/Bethesda_Terrace_and_Fountain) |

These are hand-authored gameplay locations checked against reference facts;
no artwork, map extract or new downloaded asset is bundled.

## Tests

`godot --headless --path . res://tests/missions_test.tscn` checks wallet
persistence/validation/signals, progress and targets, origin shifts,
timeout/retry, single payouts, collectible de-duplication, giver entry, and
tracked EncounterDirector gangs with local assist rewards, arrests and
capped fines, police defeats paying no bounty, and timed checkpoints while
the hero follows a DriveVehicle in Drive mode. It uses synthetic
ground and a settings file of its own, without downloads.
