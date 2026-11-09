extends Node
## Plays the flight ring course in the real game for a video, with ordinary
## controls, for Godot's Movie Maker. Not a test: nothing is checked.
##
## It loads the main scene (scenes/world.tscn) as it is and changes nothing in
## it: no cheats, no time scaling, no invulnerability, nothing moved by hand.
## Launch options pick the course and settings (see the command below). Once
## the city has loaded and the hero is waiting at the start, it holds still
## for WARMUP seconds, prints the frame number where the flying starts (to
## cut the loading off the video) and then works a virtual gamepad every
## physics tick: the right stick (look_left/right/up/down) turns the camera
## toward where FlightCoursePilot wants to go, and move_forward and sprint
## push and boost, through Input.action_press, so PlayerInput reads them
## like a real pad. It flies past ring 2 on purpose (a miss), turns back
## through it, finishes, then presses R (flight_course) to show the restart,
## and quits a moment later.
##
## Uses a settings file of its own (with a player name, so no name prompt).
## Capture (Linux, under Xvfb):
##   xvfb-run -n 77 -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --write-movie /tmp/course/frame.png --fixed-fps 30 --resolution 1280x720 \
##     res://tests/flight_course_capture.tscn -- --course=1 --solo=1 --time=16:30 \
##     --tiles_url=https://nycheroes.party/tiles/
## then ffmpeg the PNGs from the printed start frame at 30 fps.

const SETTINGS_FILE := "user://flight_course_capture_settings.cfg"
## Seconds of standing still at the start before flying (the city settles).
const WARMUP := 2.0
## After finishing, fly on this long before pressing R, then this long after.
const AFTER_FINISH := 1.5
const AFTER_RESTART := 1.8
## Camera turn per radian off, on the stick (full stick turns 2.5 rad/s).
const LOOK_GAIN := 3.0
## The look actions' dead zone: the stick is pushed past it, so small turns
## still turn (Input.get_vector rescales what's past the dead zone).
const LOOK_DEADZONE := 0.15
const MISS_RING := 2

var _world: Game
var _city: CityStreamer
var _hero: Hero
var _camera: ThirdPersonCamera
var _course: FlightCourse
var _pilot := FlightCoursePilot.new()
var _phase := "loading"
var _clock := 0.0


func _ready() -> void:
	process_physics_priority = -20  # (before PlayerInput reads the controls)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Flyer")
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_city = _world.get_node("City")
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_course = _world.get_node("FlightCourse")
	_pilot.miss_ring = MISS_RING
	_course.ring_missed.connect(func(index: int) -> void:
		_pilot.on_missed(index)
		_log("missed ring %d" % index))
	_course.ring_passed.connect(func(index: int, at: float) -> void: _log("ring %d passed at %s" % [index, FlightCourse.format_time(at)]))
	_course.finished.connect(func(seconds: float, best: bool) -> void: _log("finished in %.3f s (best %s)" % [seconds, best]))
	_course.started.connect(func() -> void: _log("course (re)started"))


func _physics_process(delta: float) -> void:
	_clock += delta
	match _phase:
		"loading":
			if not _hero.frozen and _city.pending_count() == 0 and _course.state == FlightCourse.State.READY:
				_phase = "warmup"
				_clock = 0.0
				_log("city loaded, hero at the start")
		"warmup":
			if _clock >= WARMUP:
				_phase = "flying"
				_clock = 0.0
				_log("FLYING_STARTS frame=%d" % Engine.get_frames_drawn())
		"flying":
			_steer()
			if _course.state == FlightCourse.State.FINISHED:
				_phase = "finished"
				_clock = 0.0
		"finished":
			_steer_straight()
			if _clock >= AFTER_FINISH:
				_release_all()
				_tap_r()
				_phase = "restarted"
				_clock = 0.0
		"restarted":
			if _clock >= AFTER_RESTART:
				_log("CAPTURE_ENDS frame=%d" % Engine.get_frames_drawn())
				get_tree().quit()


func _steer() -> void:
	var plan := _pilot.plan(_hero, _course)
	_look_toward(plan.aim)
	_set_action(&"move_forward", 1.0 if plan.forward else 0.0)
	_set_action(&"sprint", 1.0 if plan.sprint else 0.0)


## After the finish: level out and coast on.
func _steer_straight() -> void:
	var ahead := _hero.velocity
	ahead.y = 0.0
	_look_toward(ahead.normalized() if ahead.length() > 1.0 else _camera.aim_direction())
	_set_action(&"move_forward", 1.0)
	_set_action(&"sprint", 0.0)


## Pushes the right stick so the camera turns toward `aim`.
func _look_toward(aim: Vector3) -> void:
	var yaw := atan2(-aim.x, -aim.z)
	var pitch := asin(clampf(aim.y, -1.0, 1.0))
	var x := clampf(-angle_difference(_camera.yaw, yaw) * LOOK_GAIN, -1.0, 1.0)  # (yaw goes down to the right)
	var y := clampf(-(pitch - _camera.pitch) * LOOK_GAIN, -1.0, 1.0)
	_stick(&"look_left", &"look_right", x)
	_stick(&"look_up", &"look_down", y)


func _stick(negative: StringName, positive: StringName, value: float) -> void:
	var push := 0.0 if absf(value) < 0.01 else LOOK_DEADZONE + (1.0 - LOOK_DEADZONE) * absf(value)
	_set_action(positive, push if value > 0.0 else 0.0)
	_set_action(negative, push if value < 0.0 else 0.0)


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for action: StringName in [&"move_forward", &"sprint", &"look_left", &"look_right", &"look_up", &"look_down"]:
		Input.action_release(action)


func _tap_r() -> void:
	var press := InputEventAction.new()
	press.action = &"flight_course"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = &"flight_course"
	Input.parse_input_event.call_deferred(release)


func _log(text: String) -> void:
	print("[capture] frame %d (wall clock %.1f s): %s" % [Engine.get_frames_drawn(), Time.get_ticks_msec() / 1000.0, text])
