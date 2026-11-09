class_name OnFootMode
extends HeroMode
## Running, super speed, jumps and charged super jumps, wall kicks, falling,
## and swimming.

@export_group("Running")
@export var run_speed := 9.0
@export var super_speed := 60.0
@export var acceleration := 45.0
## Acceleration above running speed, so super speed builds up.
@export var super_acceleration := 25.0
@export var braking := 60.0
## Turn rate in rad/s at running speed and at full super speed.
@export var turn_rate := 14.0
@export var super_turn_rate := 2.5

@export_group("Jumping")
@export var jump_speed := 12.0
@export var super_jump_min_speed := 30.0
@export var super_jump_max_speed := 80.0
## Extra forward speed a fully charged super jump adds toward the stick direction.
@export var super_jump_leap := 25.0
## Hold time from the start of a super jump charge to full power.
@export var charge_time := 1.0
## Letting go of jump sooner than this is a normal jump.
@export var tap_time := 0.18
@export var air_acceleration := 18.0
## Grace period for jumping just after running off a ledge.
@export var coyote_time := 0.12

@export_group("Wall kick")
## Pressing jump in the air with a wall within this reach (m, from the body's
## middle; the capsule's radius is 0.25) kicks off it.
@export var wall_kick_reach := 0.9
## Speed straight out from the wall, and upward, of a kick.
@export var wall_kick_push := 11.0
@export var wall_kick_lift := 13.0
## Kicks per trip through the air: a short wall-to-wall chain, not a ladder.
@export var wall_kicks_per_jump := 3
## Each kick off the same wall as the last lifts this much less (multiplied),
## so bouncing back to one wall loses height instead of climbing it.
@export var same_wall_lift_scale := 0.45
## Shortest time between kicks (s).
@export var wall_kick_cooldown := 0.3

@export_group("Super speed ram")
## Running faster than this bowls over any thug in the way.
@export var ram_speed := 25.0
@export var ram_radius := 1.8

@export_group("Swimming")
@export var swim_speed := 5.0
@export var swim_super_speed := 25.0
@export var water_jump_speed := 16.0
## How far below the water's surface the hero's feet float.
@export var float_height := -1.2

## True while jump is held on the ground; charge goes 0..1 once it's a super jump.
var charging := false
var charge := 0.0

var _hold_time := 0.0
var _air_time := 0.0
var _web_cooldown := 0.0
var _scare_cooldown := 0.0
var _jump_handed_over := false
## Counts every wall kick (network-visible, like MeleeMode.punch_id): the
## animator and sounds kick when it changes, for copies of other players too.
var wall_kick_id := 0
## Kicks left before touching down again.
var wall_kicks_left := 3
var _kick_cooldown := 0.0
var _kick_normal := Vector3.ZERO  # the wall last kicked off, this trip through the air
var _kick_lift_scale := 1.0


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	charging = _jump_handed_over
	charge = 0.0
	_jump_handed_over = false


func physics_update(delta: float) -> StringName:
	if hero.input.fly_toggle_pressed:
		return &"Flight"
	if hero.attack_pressed and hero.hurt_time <= 0.0 and not hero.is_in_water():
		return &"Melee" if hero.is_on_floor() else &"Dive"
	if _wants_web(delta) and (hero.get_mode(&"Swing") as SwingMode).try_attach():
		return &"Swing"

	_kick_cooldown -= delta
	if hero.is_in_water():
		_reset_wall_kicks()
		_swim(delta)
	elif hero.is_on_floor():
		_reset_wall_kicks()
		_run(delta)
	else:
		_fall(delta)
	var intended := hero.velocity
	hero.move_and_slide()
	var before := hero.global_position.y
	if LedgeClimb.climb(hero, intended, delta):  # curbs
		hero.eased_step(hero.global_position.y - before)
	return &""


func _wants_web(delta: float) -> bool:
	# A press always tries; holding the button keeps retrying in the air.
	_web_cooldown -= delta
	var retry := hero.input.web_held and _web_cooldown <= 0.0 and not hero.is_on_floor()
	if hero.web_pressed or retry:
		_web_cooldown = 0.25
		return true
	return false


func _run(delta: float) -> void:
	_air_time = 0.0
	var input := hero.input
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	var speed := horizontal.length()
	var wish := input.move.limit_length(1.0)
	if hero.hurt_time > 0.0:
		wish = Vector3.ZERO  # staggered by a hit

	if charging and charge > 0.0:
		# Crouched for a super jump: plant the feet.
		horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)
	elif wish.length() > 0.05:
		var wish_dir := wish.normalized()
		var direction := horizontal / speed if speed > 0.5 else wish_dir
		var fast := clampf(inverse_lerp(run_speed, super_speed, speed), 0.0, 1.0)
		direction = _turn(direction, wish_dir, lerpf(turn_rate, super_turn_rate, fast) * delta)
		var target := (super_speed if input.sprint_held else run_speed) * wish.length()
		var rate := acceleration
		if target < speed:
			rate = braking
		elif speed >= run_speed:
			rate = super_acceleration
		horizontal = direction * move_toward(speed, target, rate * delta)
		hero.face_toward(direction)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, braking * delta)

	hero.velocity = Vector3(horizontal.x, 0.0, horizontal.z)
	_update_jump(delta)
	_ram(horizontal, delta)


## At super speed, thugs in the way get bowled over and bystanders scatter.
func _ram(horizontal: Vector3, delta: float) -> void:
	var speed := horizontal.length()
	if speed < ram_speed:
		return
	var direction := horizontal / speed
	var center := hero.global_position + direction * 0.8 + Vector3.UP
	Combat.strike(center, ram_radius, 100.0, direction * speed * 0.7 + Vector3.UP * speed * 0.35, true)
	_scare_cooldown -= delta
	if _scare_cooldown <= 0.0:
		_scare_cooldown = 0.3
		Combat.raise_danger(hero.world_position(), 14.0)


## Starts a jump as if jump had just been pressed on the ground: a tap jumps,
## holding charges a super jump. Other modes call this to hand a jump press
## over just before switching to OnFoot.
func begin_jump() -> void:
	charging = true
	_hold_time = 0.0
	_jump_handed_over = true


func _update_jump(delta: float) -> void:
	if hero.jump_pressed:
		charging = true
		_hold_time = 0.0
	if not charging:
		return
	if hero.input.jump_held:
		_hold_time += delta
		charge = clampf((_hold_time - tap_time) / charge_time, 0.0, 1.0)
		return

	if _hold_time < tap_time:
		hero.velocity.y = jump_speed
	else:
		hero.velocity.y = lerpf(super_jump_min_speed, super_jump_max_speed, charge)
		hero.velocity += hero.input.move.limit_length(1.0) * charge * super_jump_leap
	charging = false
	charge = 0.0


func _fall(delta: float) -> void:
	_air_time += delta
	charging = false
	charge = 0.0
	if hero.jump_pressed:
		# Coyote time is for running off a ledge, not a second press while
		# already jumping up (which can be a wall kick).
		if _air_time < coyote_time and hero.velocity.y <= 0.0:
			hero.velocity.y = jump_speed
		elif _try_wall_kick():
			return

	# Steer a little, but never slow a fast jump down below its own speed.
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	var limit := maxf(horizontal.length(), run_speed)
	horizontal = (horizontal + hero.input.move.limit_length(1.0) * air_acceleration * delta).limit_length(limit)
	hero.velocity.x = horizontal.x
	hero.velocity.z = horizontal.z
	hero.velocity.y = maxf(hero.velocity.y - Hero.GRAVITY * delta, -Hero.MAX_FALL_SPEED)
	hero.face_toward(horizontal, 10.0 * delta)


func _reset_wall_kicks() -> void:
	wall_kicks_left = wall_kicks_per_jump
	_kick_normal = Vector3.ZERO
	_kick_lift_scale = 1.0


## Jump pressed in the air beside a wall: spring off it, up and away. Limited
## per trip through the air, with a cooldown, and weaker off the same wall
## twice, so it links walls across an alley but can't climb a tower.
func _try_wall_kick() -> bool:
	if wall_kicks_left <= 0 or _kick_cooldown > 0.0 or hero.hurt_time > 0.0:
		return false
	var normal := find_wall()
	if normal == Vector3.ZERO:
		return false
	if _kick_normal != Vector3.ZERO and normal.dot(_kick_normal) > 0.7:
		_kick_lift_scale *= same_wall_lift_scale
	else:
		_kick_lift_scale = 1.0
	_kick_normal = normal
	wall_kicks_left -= 1
	_kick_cooldown = wall_kick_cooldown
	wall_kick_id += 1
	# Keep the speed along the wall (capped), swap the speed into it for a push out.
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	var along := (horizontal - normal * horizontal.dot(normal)).limit_length(run_speed)
	# The stick steers the kick a little, but holding into the wall doesn't blunt it.
	var steer := hero.input.move.limit_length(1.0)
	steer -= normal * minf(steer.dot(normal), 0.0)
	var out := normal * wall_kick_push + steer * 3.0
	hero.velocity = Vector3(along.x + out.x, wall_kick_lift * _kick_lift_scale, along.z + out.z)
	hero.face_toward(normal)
	return true


## The outward normal (flat, unit) of the nearest wall within reach of the
## body's middle, or zero. Probes the way the hero moves first, then all round.
func find_wall() -> Vector3:
	var space := hero.get_world_3d().direct_space_state
	var center := hero.global_position + Vector3.UP * 0.9
	var best := Vector3.ZERO
	var best_distance := INF
	var heading := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	var base := atan2(-heading.x, -heading.z) if heading.length_squared() > 0.25 else hero.facing
	for k in 8:
		var yaw := base + k * TAU / 8.0
		var direction := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var query := PhysicsRayQueryParameters3D.create(center, center + direction * wall_kick_reach, Hero.WORLD_LAYER)
		query.exclude = [hero.get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		if absf(normal.y) > 0.35:
			continue  # a roof or a slope, not a wall
		var distance := center.distance_to(hit.position)
		if distance < best_distance:
			best_distance = distance
			best = Vector3(normal.x, 0.0, normal.z).normalized()
	return best


func _swim(delta: float) -> void:
	charging = false
	charge = 0.0
	var input := hero.input
	var wish := input.move.limit_length(1.0)
	var top_speed := swim_super_speed if input.sprint_held else swim_speed
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z).move_toward(wish * top_speed, 30.0 * delta)

	# Bob back up to the surface, and leap out with jump.
	var rise := (hero.water_level + float_height - hero.global_position.y) * 4.0
	var vertical := lerpf(hero.velocity.y, rise, 1.0 - exp(-6.0 * delta))
	if hero.jump_pressed:
		vertical = water_jump_speed
	hero.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	hero.face_toward(wish, 8.0 * delta)


static func _turn(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(angle, -max_angle, max_angle))
