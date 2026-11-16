# Wanted levels and foot police

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
There are no guns, police cars or new pathfinding/navigation meshes.

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
navigation graph. Police cars and precinct-specific respawns are future work.
