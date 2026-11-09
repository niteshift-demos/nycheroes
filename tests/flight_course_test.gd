extends Node
## Headless check of the flight ring course (FlightCourse), in the real city:
## - Checkpoints on their own: only the next ring counts, only forwards,
##   within RING_RADIUS; further off but within MISS_RADIUS is a miss; the
##   clock starts and stops at the crossing point inside a tick.
## - R starts the course: the hero waits in the air before the START ring,
##   flying, until the city there has loaded.
## - Every ring and the way between them is clear of the city's collision
##   (buildings, bridges, the ground) by CLEARANCE.
## - Flown with HeroInput alone (FlightCoursePilot steering like a player),
##   missing ring 2 on purpose: the miss is reported and ring 2 stays next;
##   then all rings in order to the finish; the world origin has shifted
##   since the rings were made (the course is 1.2-2.9 km from Times Square)
##   and they're still where they belong; the finish time matches the
##   physics ticks counted here.
## - R mid-course restarts it: back before the START ring, clock at zero.
## Uses a settings file of its own, not the player's.
## Run: godot --headless --path . res://tests/flight_course_test.tscn -- --solo=1 --peds=0 --traffic=0 --gangs=0 [--tiles=DIR]
## (the editor binary reads data/tiles; add --tiles_url=https://nycheroes.party/tiles/ to stream them instead)

const SETTINGS_FILE := "user://flight_course_test_settings.cfg"
const MAX_LOAD_WAIT := 90.0
## The course must finish within this (physics seconds), miss and all.
const MAX_FLIGHT := 120.0
## Free space around each ring's tube and along the way between rings (m).
const CLEARANCE := 12.0
const MISS_RING := 2

var _world: Game
var _city: CityStreamer
var _hero: Hero
var _course: FlightCourse
var _pilot := FlightCoursePilot.new()
var _checks: Array[String] = []
var _failed := 0
var _flying := false
var _ticks_since_start := -1
var _missed: Array[int] = []
var _passed: Array[int] = []
var _shifts := 0


func _ready() -> void:
	process_physics_priority = -10  # (where PlayerInput would fill the hero's input)
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Tester")  # (no name prompt)
	_check_checkpoints()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_hero = _world.get_node("Hero")
	_course = _world.get_node("FlightCourse")
	_course.ring_missed.connect(func(index: int) -> void:
		_missed.append(index)
		_pilot.on_missed(index))
	_course.ring_passed.connect(func(index: int, _at: float) -> void:
		_passed.append(index)
		if index == 0:
			_ticks_since_start = 0)
	WorldOrigin.shifted.connect(func(_delta: Vector3) -> void: _shifts += 1)
	await _press_r()
	_check(_course.state == FlightCourse.State.READY and _course.next_ring == 0, "R starts the course, ready at the START ring")
	_check(_hero.frozen and _hero.mode.name == &"Flight", "the hero waits in the air, flying, while the city there loads")
	_check(_hero.world_position().distance_to(FlightCourse.start_position()) < 0.5,
		"before the START ring (%.1f m from the start spot)" % _hero.world_position().distance_to(FlightCourse.start_position()))
	if not await _wait_until(func() -> bool: return not _hero.frozen and _city.pending_count() == 0, MAX_LOAD_WAIT):
		_check(false, "the city loaded around the start")
		_finish()
		return
	await _check_clearance()
	await _press_r()  # (the clearance check moved the hero about)
	await _wait_until(func() -> bool: return not _hero.frozen, MAX_LOAD_WAIT)
	await _fly_course()
	await _check_restart()
	_finish()


## The plane tests on their own, with made-up paths.
func _check_checkpoints() -> void:
	var course := FlightCourse.new()
	course.state = FlightCourse.State.READY
	add_child(course)
	var passed: Array = []
	var missed: Array = []
	course.ring_passed.connect(func(index: int, at: float) -> void: passed.append([index, at]))
	course.ring_missed.connect(func(index: int) -> void: missed.append(index))
	var dt := 1.0 / 60.0
	var c1 := FlightCourse.RINGS[1]
	var n1 := FlightCourse.ring_normal(1)
	course._check_crossing(c1 - n1 * 2.0, c1 + n1 * 2.0, dt)
	_check(passed.is_empty() and missed.is_empty(), "flying through ring 1 before the START ring counts for nothing")
	var c0 := FlightCourse.RINGS[0]
	var n0 := FlightCourse.ring_normal(0)
	course._check_crossing(c0 + n0 * 2.0, c0 - n0 * 2.0, dt)
	_check(passed.is_empty(), "through the START ring backwards counts for nothing")
	# Through the start a quarter of the way along a tick: the clock has run
	# the other three quarters of it.
	course._check_crossing(c0 - n0 * 1.0, c0 + n0 * 3.0, dt)
	_check(passed.size() == 1 and course.state == FlightCourse.State.RUNNING and is_equal_approx(course.elapsed, dt * 0.75),
		"forwards through START starts the clock at the crossing (%.5f s)" % course.elapsed)
	var side := n1.cross(Vector3.UP).normalized()
	course._check_crossing(c1 + side * 20.0 - n1, c1 + side * 20.0 + n1, dt)
	_check(missed == [1] and course.next_ring == 1, "20 m off ring 1's middle is a miss, and ring 1 stays next")
	course._check_crossing(c1 + side * 80.0 - n1, c1 + side * 80.0 + n1, dt)
	_check(missed == [1], "80 m off is nowhere near it: not even a miss")
	course._check_crossing(c1 + side * 11.0 - n1, c1 + side * 11.0 + n1, dt)
	_check(passed.size() == 2 and course.next_ring == 2, "11 m off its middle is through it")
	course.free()


## Every ring, and the way from each to the next, is clear of the city.
func _check_clearance() -> void:
	var space := _hero.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = FlightCourse.RING_RADIUS + FlightCourse.TUBE + CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = CityStreamer.COLLISION_LAYER
	var path := SphereShape3D.new()
	path.radius = CLEARANCE
	var blocked: Array[String] = []
	for n in FlightCourse.RINGS.size():
		var center := FlightCourse.RINGS[n]
		# Hold the hero over the ring until its streets have loaded with collision.
		_hero.frozen = true
		_hero.global_position = WorldOrigin.to_local(center + Vector3.UP * 30.0)
		await _wait_until(func() -> bool: return _city.has_collision_at(center) and _city.pending_count() == 0, MAX_LOAD_WAIT)
		await _wait(0.3)
		var ground := _city.ground_height_at(center)
		if is_nan(ground):
			blocked.append("ring %d: no collision loaded under it" % n)
		elif center.y - FlightCourse.RING_RADIUS - FlightCourse.TUBE - ground < CLEARANCE:
			blocked.append("ring %d: %.0f m over what's below" % [n, center.y - ground])
		query.shape = sphere
		query.motion = Vector3.ZERO
		query.transform = Transform3D(Basis.IDENTITY, WorldOrigin.to_local(center))
		if not space.intersect_shape(query, 1).is_empty():
			blocked.append("ring %d is touching the city" % n)
		if n > 0:
			var from := FlightCourse.RINGS[n - 1]
			query.shape = path
			query.transform = Transform3D(Basis.IDENTITY, WorldOrigin.to_local(from))
			query.motion = center - from
			var room := space.cast_motion(query)
			if room.size() == 2 and room[0] < 1.0:
				blocked.append("the way from ring %d to ring %d is blocked %.0f%% along" % [n - 1, n, room[0] * 100.0])
	_check(blocked.is_empty(), "every ring and the way between them is clear of the city by %.0f m (%s)" % [
		CLEARANCE, ", ".join(blocked) if blocked else "all %d rings" % FlightCourse.RINGS.size()])
	_hero.frozen = false


func _fly_course() -> void:
	_pilot.miss_ring = MISS_RING
	_missed.clear()
	_passed.clear()
	_ticks_since_start = -1
	_flying = true
	var done := await _wait_until(func() -> bool: return _course.state == FlightCourse.State.FINISHED, MAX_FLIGHT)
	_flying = false
	_hero.input.clear()
	_check(done, "the course was flown to the finish (rings passed %s)" % str(_passed))
	_check(_missed.has(MISS_RING), "flying past ring %d is a miss (misses %s)" % [MISS_RING, str(_missed)])
	var in_order := _passed.size() == FlightCourse.RINGS.size()
	for n in _passed.size():
		in_order = in_order and _passed[n] == n
	_check(in_order, "every ring passed once, in order, the missed one after turning back (%s)" % str(_passed))
	_check(_shifts > 0, "the world origin shifted since the rings were made (%d shifts; offset %s)" % [_shifts, WorldOrigin.offset])
	var worst := 0.0
	for n in FlightCourse.RINGS.size():
		var ring := _course.get_node("Ring%d" % n) as Node3D
		worst = maxf(worst, WorldOrigin.to_world(ring.global_position).distance_to(FlightCourse.RINGS[n]))
	_check(worst < 0.01, "the rings stayed where they belong through the shifts (%.4f m off at worst)" % worst)
	var counted := _ticks_since_start / float(Engine.physics_ticks_per_second)
	var tick := 1.0 / Engine.physics_ticks_per_second
	_check(done and absf(_course.elapsed - counted) <= tick,
		"the time (%s, %.3f s) matches the physics ticks flown (%.3f s)" % [FlightCourse.format_time(_course.elapsed), _course.elapsed, counted])
	_check(_course.best_time == _course.elapsed and float(Settings.get_value(FlightCourse.SETTING_BEST, 0.0)) == _course.elapsed,
		"the first finish is the best time, remembered")
	_check(not _course.get_node("Ring0").visible and not _course.get_node("Ring6").visible, "the finished course's rings are gone")


func _check_restart() -> void:
	_course.start()
	await _wait_until(func() -> bool: return not _hero.frozen, MAX_LOAD_WAIT)
	_pilot = FlightCoursePilot.new()
	_flying = true
	await _wait_until(func() -> bool: return _course.next_ring >= 2, 40.0)
	var elapsed_then := _course.elapsed
	await _press_r()
	_flying = false
	_hero.input.clear()
	_check(elapsed_then > 0.0 and _course.state == FlightCourse.State.READY and _course.next_ring == 0 and _course.elapsed == 0.0,
		"R mid-course restarts it: ready at START, clock at zero (it had run %.2f s)" % elapsed_then)
	_check(_hero.world_position().distance_to(FlightCourse.start_position()) < 0.5 and _hero.mode.name == &"Flight",
		"and the hero is back before the START ring, flying")
	_course.stop()
	_check(_course.state == FlightCourse.State.OFF and not _course.get_node("Ring0").visible, "leaving the course takes the rings away")


func _physics_process(_delta: float) -> void:
	if _ticks_since_start >= 0 and _course.state == FlightCourse.State.RUNNING:
		_ticks_since_start += 1
	if not _flying or _hero.frozen:
		return
	var plan := _pilot.plan(_hero, _course)
	var input := _hero.input
	input.aim = plan.aim
	input.stick = Vector2(0.0, -1.0 if plan.forward else 0.0)
	input.move = Vector3.ZERO
	input.vertical = 0.0
	input.sprint_held = plan.sprint


func _press_r() -> void:
	var press := InputEventAction.new()
	press.action = &"flight_course"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().physics_frame
	var release := InputEventAction.new()
	release.action = &"flight_course"
	Input.parse_input_event(release)
	await get_tree().physics_frame


func _wait_until(condition: Callable, seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while not condition.call():
		if Time.get_ticks_msec() - started > seconds * 1000.0:
			return false
		await get_tree().physics_frame
	return true


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok      " if ok else "FAILED  ") + what)
	if not ok:
		_failed += 1


func _finish() -> void:
	print("\n".join(_checks))
	print("%d checks, %d failed" % [_checks.size(), _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	get_tree().quit(1 if _failed else 0)
