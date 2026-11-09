class_name WaterExit
## Collision-tested exits from water onto low shores. All probes use scene
## coordinates and are discarded each tick, so origin shifts need no cache fix.

## High seawalls still require a jump or flight; swimming is no wall climb.
const MAX_SHORE_HEIGHT := 1.0
const REACH := 0.85
const CLEARANCE := 0.08


static func try_exit(hero: Hero, direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return false
	if hero.global_position.y < hero.water_level - 1.7:
		return false  # surface first rather than pulling up from deep underwater
	var start := hero.global_transform
	var rise := hero.water_level + MAX_SHORE_HEIGHT + CLEARANCE - start.origin.y
	if rise <= 0.0:
		return false
	var up := Vector3.UP * rise
	# Probe within arm's reach before contact too: a shoreline mesh may
	# have no vertical wall face. Sweep the capsule, including headroom.
	if hero.test_move(start, up):
		return false
	var raised := start.translated(up)
	var across := Vector3(direction.x, 0.0, direction.z).normalized() * REACH
	if hero.test_move(raised, across):
		return false
	var ahead := raised.translated(across)
	var landing := KinematicCollision3D.new()
	if not hero.test_move(ahead, Vector3.DOWN * (MAX_SHORE_HEIGHT - Hero.WATER_LINE), landing):
		return false
	if landing.get_normal().y < LedgeClimb.MIN_FLOOR_NORMAL_Y:
		return false
	var destination := ahead.origin + landing.get_travel()
	if destination.y < hero.water_level + Hero.WATER_LINE + CLEARANCE:
		return false  # underwater shelves are not shore exits
	hero.global_position = destination
	hero.velocity.y = 0.0
	hero.eased_step(destination.y - start.origin.y)
	return true
