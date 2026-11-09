extends Node
## Plays the wall kick for a video, in the real city (scenes/world.tscn, with
## its normal pedestrians and traffic), by feeding the hero ordinary
## per-tick HeroInput (stick, jump) instead of the keyboard, and turning the
## hero camera like a player's mouse would. Nothing else is touched: no
## teleports after the start, no changed speeds, cooldowns or time scale.
## Jump presses are timed like a player's: when a wall comes within reach.
##
## The spot: a 6.7 m wide gap between two tall buildings just west of 6th
## Avenue in Midtown (found by tools/capture/alley_scan.tscn), next to the
## front of the southern building. The shot: a kick off that front, mashing
## jump at the same wall (no climbing it), then kicking back and forth up the
## gap until the third kick, after which jump does nothing and the hero drops;
## then once more, as touching down gave the kicks back.
##
## Record (native Godot Movie Maker, 30 fps, see docs/ROADMAP.md):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/wallkick/frame.png \
##     res://tools/capture/wall_kick_capture.tscn -- \
##     --spawn=422.6,19.2,-264.4,61 --name=Kicker --solo=1 --gangs=0 --time=12:30 \
##     --tiles_url=https://nycheroes.party/tiles/
## It prints "[capture] start frame N" once the city has loaded and the hero
## has stood still for a moment, and quits after "[capture] end frame N".

## Manhattan's avenues run about 29 degrees east of north.
const AVENUE := Vector3(0.485, 0.0, -0.875)
const CROSS := Vector3(0.875, 0.0, 0.485)
## Middle of the gap at its back (world meters, ground level).
const GAP := Vector3(417.0, 18.6, -279.0)
## Camera turn rate, like a steady mouse (rad/s).
const CAMERA_TURN := 0.9

var _world: Game
var _hero: Hero
var _on_foot: OnFootMode
var _camera: ThirdPersonCamera
var _city: CityStreamer
var _yaw_target := 0.0
var _pitch_target := -0.12
var _toward_front := -CROSS
## Where the gap's walls are: the southern wall faces +AVENUE, the northern -AVENUE.
var _gap_entry := Vector3.ZERO


func _ready() -> void:
	# The options menu's "Show FPS and stats" off (it's on by default on
	# desktop), as a player recording a clip would have it.
	Settings.set_value("show_stats", false)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_on_foot = _hero.get_mode(&"OnFoot") as OnFootMode
	_camera = _world.get_node("HeroCamera")
	_city = _world.get_node("City")
	process_physics_priority = -20  # before the hero, like PlayerInput
	_run.call_deferred()


func _process(delta: float) -> void:
	_camera.yaw = rotate_toward(_camera.yaw, _yaw_target, CAMERA_TURN * delta)
	_camera.pitch = move_toward(_camera.pitch, _pitch_target, CAMERA_TURN * 0.5 * delta)


func _run() -> void:
	var front_yaw := _yaw_of(-CROSS)
	_yaw_target = front_yaw + 1.35  # nearly side-on to the building's front
	_camera.yaw = _yaw_target
	_camera.pitch = _pitch_target
	while _hero.frozen or _city.pending_count() > 0:
		await _tick({})
	await _idle(2.5)
	print("[capture] start frame %d" % Engine.get_frames_drawn())
	_gap_entry = GAP + CROSS * 3.0 - AVENUE * 4.0  # 0.9 m off the southern wall

	# 1. Run at the building's front, jump, kick off it.
	print("[capture] kick off the front")
	await _run_at_wall_and_jump(-CROSS, 2.6)
	await _until_kick(-CROSS, 1.0)
	await _hold_until_landed({})
	await _idle(0.8)

	# 2. Again, but keep pushing into the same wall and mashing jump.
	print("[capture] mash jump at the same wall")
	await _run_at_wall_and_jump(-CROSS, 2.6)
	await _until_kick(-CROSS, 1.0)
	var mash := 0.0
	while not _hero.is_on_floor():
		mash += get_physics_process_delta_time()
		var press := fmod(mash, 0.2) < 0.05
		await _tick({move = -CROSS, jump = press})
	print("[capture] landed after mashing: kicks this trip %d" % (_on_foot.wall_kicks_per_jump - _on_foot.wall_kicks_left))
	await _idle(0.8)

	# 3. Over to the gap, camera looking into it and up.
	print("[capture] to the gap")
	_yaw_target = front_yaw + 0.1
	_pitch_target = 0.3
	await _walk_to(_gap_entry + CROSS * 6.0, 1.0)
	await _walk_to(_gap_entry, 0.6)
	await _idle(0.8)

	# 4. Kick back and forth up the gap, until the kicks run out.
	print("[capture] up the gap")
	await _gap_chain()
	await _hold_until_landed({})
	await _idle(1.0)

	# 5. Touching down gave the kicks back: again, from the same spot.
	print("[capture] up the gap again")
	await _walk_to(_gap_entry, 0.6)
	await _idle(0.8)
	await _gap_chain()
	await _hold_until_landed({})
	await _idle(2.0)
	print("[capture] end frame %d" % Engine.get_frames_drawn())
	get_tree().quit()


## Jumps beside the southern wall and kicks back and forth across the gap,
## pressing jump as each wall comes within reach, then keeps mashing jump
## once the kicks have run out.
func _gap_chain() -> void:
	var at := _hero.world_position() - GAP
	print("[capture] start of the chain at %.1f across, %.1f along the gap" % [at.dot(AVENUE), at.dot(CROSS)])
	await _tick({jump = true})
	await _tick({jump = true})
	await _tick({})
	# Heading north across the gap, away from the southern wall beside the hero.
	var toward := AVENUE
	var presses := 0
	var since_press := 1.0
	var after_last := -1.0
	for n in 600:
		since_press += get_physics_process_delta_time()
		if _hero.is_on_floor() and n > 20:
			print("[capture] landed")
			break
		var wall := _on_foot.find_wall()
		if OS.has_environment("CAPTURE_DEBUG") and n % 3 == 0:
			var p := _hero.world_position() - GAP
			print("[debug] n %d across %.2f along %.2f up %.2f v %s wall %s floor %s" % [n, p.dot(AVENUE), p.dot(CROSS), p.y, _hero.velocity.snapped(Vector3.ONE * 0.1), wall.snapped(Vector3.ONE * 0.01), _hero.is_on_floor()])
		# Press as a wall comes within reach: the one beside the hero first,
		# then the one ahead each time across the gap.
		var press := since_press > 0.32 and wall != Vector3.ZERO and (presses == 0 or wall.dot(toward) < -0.5)
		if after_last >= 0.0:
			# Out of kicks: keep mashing jump at the wall; nothing more happens.
			after_last += get_physics_process_delta_time()
			press = since_press > 0.25
			if after_last > 1.5:
				break
		var heading := toward
		if press and after_last < 0.0:
			# Kick off the wall within reach, back across the gap.
			heading = AVENUE if wall.dot(AVENUE) > 0.0 else -AVENUE
		if not press:
			await _tick({move = toward})
			continue
		var id := _on_foot.wall_kick_id
		await _tick({move = heading, jump = true})
		presses += 1
		since_press = 0.0
		var kicked := _on_foot.wall_kick_id != id
		print("[capture] press %d: %s, %.1f m up, kicks left %d" % [presses, "kick" if kicked else "nothing (no kicks left)",
			_hero.world_position().y - GAP.y, _on_foot.wall_kicks_left])
		if kicked:
			toward = heading
		elif after_last < 0.0:
			after_last = 0.0


func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## One physics tick of input: move (world direction), jump held.
func _tick(input: Dictionary) -> void:
	var i := _hero.input
	i.clear()
	var move: Vector3 = input.get("move", Vector3.ZERO)
	var speed: float = input.get("speed", 1.0)
	i.move = move * speed
	# The stick that gives this move with the camera's current yaw.
	var local := Basis(Vector3.UP, _camera.yaw).inverse() * i.move
	i.stick = Vector2(local.x, local.z)
	i.jump_held = input.get("jump", false)
	i.aim = _camera.aim_direction()
	await get_tree().physics_frame


func _idle(seconds: float) -> void:
	for n in roundi(seconds * Engine.physics_ticks_per_second):
		await _tick({})


## Runs toward the wall in `direction` until it's `distance` m ahead, then
## jumps (a tap).
func _run_at_wall_and_jump(direction: Vector3, distance: float) -> void:
	for n in 600:
		if _distance_ahead(direction) < distance:
			break
		await _tick({move = direction})
	for n in 4:
		await _tick({move = direction, jump = true})


## Holds toward the wall and presses jump once it's within reach.
func _until_kick(direction: Vector3, timeout: float) -> void:
	var ticks := roundi(timeout * Engine.physics_ticks_per_second)
	for n in ticks:
		if _hero.is_on_floor() and n > 10:
			print("[capture] landed before reaching the wall")
			return
		if _on_foot.find_wall() != Vector3.ZERO and not _hero.is_on_floor():
			var id := _on_foot.wall_kick_id
			await _tick({move = direction, jump = true})
			print("[capture] kick: %s, %.1f m up" % [_on_foot.wall_kick_id != id, _hero.world_position().y - GAP.y])
			return
		await _tick({move = direction})


func _hold_until_landed(input: Dictionary) -> void:
	for n in 600:
		if _hero.is_on_floor():
			return
		await _tick(input)


## Walks (at `speed` of the stick) to a world point on the ground.
func _walk_to(world_point: Vector3, speed: float) -> void:
	for n in 900:
		var offset := world_point - _hero.world_position()
		offset.y = 0.0
		if offset.length() < 0.1:
			break
		await _tick({move = offset.normalized(), speed = minf(speed, offset.length() * 0.8 + 0.15)})
	for n in 30:
		await _tick({})


## How far ahead (m) a wall is from the hero's middle in `direction`.
func _distance_ahead(direction: Vector3) -> float:
	var from := _hero.global_position + Vector3.UP * 0.9
	var hit := _hero.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, from + direction * 40.0, Hero.WORLD_LAYER))
	return from.distance_to(hit.position) if hit else INF
