extends Node
## Headless check of the rooftop run (RooftopCourse) in the real city: the
## hero starts on its START pad, then ordinary input (the driver presses jump,
## move and look like a gamepad would; tests/rooftop_course_driver.gd) jumps
## from roof to roof. Checks that the run arms on the start pad and starts on
## jumping off it; that each pad counts in order; that R puts the hero back
## on the start with the clock cleared; that a floating origin shift mid-run
## changes nothing; that taking off (F) ends the attempt and puts the hero
## back on the last roof reached; that a jump charged too little to reach the
## tower falls to the street, counts a fall and goes back to the last roof;
## and that landing on the FINISH pad finishes with the clock's time, kept as
## the best.
## Run: godot --headless --path . res://tests/rooftop_course_test.tscn
## (add `-- --tiles_url=https://nycheroes.party/tiles` without local tiles,
## or `-- --tiles=<dir>`). Exits non-zero on a failed check.

const Driver := preload("res://tests/rooftop_course_driver.gd")
const TIMEOUT := 240.0

var _world: Game
var _hero: Hero
var _city: CityStreamer
var _course: RooftopCourse
var _driver: Driver
var _failures := 0
var _time := 0.0
var _stage := &"load"
var _stage_time := 0.0
var _reached: Array[int] = []
var _fail_reasons: Array[String] = []
var _finished_time := 0.0


func _ready() -> void:
	Settings.set_value(RooftopCourse.BEST_KEY, 0.0)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	# No pedestrians or thugs: this is about jumping.
	_world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_course = _world.course
	_check(_course != null, "the course is in the game")
	_course.pad_reached.connect(func(index: int) -> void:
		_reached.append(index)
		print("[%.1f s] reached pad %d (clock %.1f s, falls %d)" % [_time, index, _course.elapsed, _course.falls]))
	_course.run_failed.connect(func(reason: String) -> void:
		_fail_reasons.append(reason)
		print("[%.1f s] failed: %s at %s" % [_time, reason, _hero.world_position()]))
	_course.run_finished.connect(func(seconds: float, best: bool) -> void:
		_finished_time = seconds
		print("[%.1f s] finished in %.1f s (best: %s)" % [_time, seconds, best]))
	_course.restart()


func _physics_process(delta: float) -> void:
	_time += delta
	_stage_time += delta
	if _time > TIMEOUT:
		_check(false, "finished within %d s (stuck at stage %s, leg %d)" % [TIMEOUT, _stage, _driver.leg if _driver else -1])
		_end()
		return
	match _stage:
		&"load":
			if not _hero.frozen and _city.pending_count() == 0 and _stage_time > 2.0:
				_check(_course.state == RooftopCourse.State.ARMED, "standing on the start pad arms the run")
				_drive([{"to": 1}])
				_next(&"first_jump")
		&"first_jump":
			if _driver.is_done():
				_check(_reached == [1], "jumping off the start and onto roof 2 counts it")
				_check(_course.state == RooftopCourse.State.RUNNING and _course.elapsed > 1.0, "the clock runs")
				_press(&"course_restart", true)
				_press(&"course_restart", false)
				_next(&"restarted")
		&"restarted":
			if _stage_time > 0.5 and not _hero.frozen:
				_check(_course.state == RooftopCourse.State.ARMED and _course.elapsed == 0.0, "R restarts the run, the clock cleared")
				_check(_flat_distance(_course.pad_world_position(0)) < 2.0, "R puts the hero on the start pad")
				_reached.clear()
				_drive([{"to": 1}, {"to": 2}])
				_next(&"to_roof_3")
		&"to_roof_3":
			if _driver.is_done():
				_check(_reached == [1, 2], "roofs 2 and 3 count in order")
				# A floating origin shift mid-run (as flying far would make).
				WorldOrigin.shift(Vector3(500.0, 0.0, -500.0))
				_press(&"fly_toggle", true)
				_next(&"flew")
		&"flew":
			_press(&"fly_toggle", false)
			if _stage_time > 0.2 and _fail_reasons.size() == 1:
				_check(_fail_reasons[0].contains("flying"), "taking off ends the attempt (%s)" % _fail_reasons[0])
				_next(&"back_after_flying")
		&"back_after_flying":
			if _stage_time > RooftopCourse.RETURN_DELAY + 0.5 and not _hero.frozen:
				_check(_flat_distance(_course.pad_world_position(2)) < 2.0, "after taking off, back on the last roof reached")
				_check(_course.falls == 1 and _course.state == RooftopCourse.State.RUNNING, "it counts as a fall; the run goes on")
				# On to roof 6; then a jump for the tower with too little charge.
				_drive([{"to": 3}, {"to": 4}, {"to": 5}, {"to": 6, "charge": 0.45}])
				_next(&"short_jump")
		&"short_jump":
			if _driver.is_done():
				_check(_reached == [1, 2, 3, 4, 5], "roofs 4 to 6 count (got %s)" % [_reached])
				_check(_fail_reasons.size() == 2 and _fail_reasons[1].contains("Fell"),
					"a jump charged too little falls to the street (%s)" % [_fail_reasons])
				_next(&"back_after_fall")
		&"back_after_fall":
			if _stage_time > RooftopCourse.RETURN_DELAY + 0.5 and not _hero.frozen:
				_check(_flat_distance(_course.pad_world_position(5)) < 2.0, "after the fall, back on roof 6")
				_check(_course.falls == 2, "two falls counted")
				_drive([{"to": 6}])
				_next(&"finish")
		&"finish":
			if _driver.is_done():
				_check(_course.state == RooftopCourse.State.FINISHED, "landing on the tower's pad finishes the run")
				_check(_finished_time > 10.0 and is_equal_approx(_course.best, _finished_time),
					"the time (%.1f s) is kept as the best" % _finished_time)
				_check(is_equal_approx(float(Settings.get_value(RooftopCourse.BEST_KEY, 0.0)), _finished_time),
					"the best time is saved")
				_end()


func _drive(legs: Array[Dictionary]) -> void:
	if _driver:
		_driver.queue_free()
	_driver = Driver.new()
	_driver.hero = _hero
	_driver.camera = _world.hero_camera
	_driver.course = _course
	_driver.legs = legs
	add_child(_driver)


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _next(stage: StringName) -> void:
	print("[%.1f s] %s" % [_time, stage])
	_stage = stage
	_stage_time = 0.0


func _flat_distance(world: Vector3) -> float:
	var at := _hero.world_position()
	return Vector2(at.x - world.x, at.z - world.z).length()


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _end() -> void:
	print("rooftop course: %s (%d failed)" % ["ALL PASSED" if _failures == 0 else "FAILED", _failures])
	set_physics_process(false)
	get_tree().quit(1 if _failures else 0)
