extends Node
## Plays the time trial in the real game for a video (not a pass/fail test),
## driving the hero through HeroInput the way a player would (TrialPilot) and
## pressing the real R key for Retry. Recorded with Godot's Movie Maker:
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --write-movie OUT.png \
##     --fixed-fps 30 --resolution 1280x720 res://tests/time_trial_recording.tscn \
##     -- --solo=1 --gangs=0 [--tiles_url=https://nycheroes.party/tiles/]
## (see docs/recordings/time_trial.md). From the documented Times Square start:
## 1. runs into the green start gate (the clock starts), then takes off and
##    flies over checkpoint 1 above the rooftops' height limit: it isn't
##    cleared (the HUD still says 0 of 4, its marker points back down);
## 2. presses R: back before the start, the clock reset;
## 3. runs the course on foot with super speed, slowing for the corner, to
##    the finish, and holds on the result.
## Prints "[rec] start frame N" and "[rec] end frame N" (frames drawn) so the
## loading screen before it can be cut from the video.

const SETTINGS_FILE := "user://time_trial_recording_settings.cfg"
## Seconds of the city standing still before the run, and after the finish.
const LEAD_IN := 1.0
const HOLD := 3.5

enum Phase { LOADING, LEAD_IN, TAKE_OFF, CLIMB, LOOK_BACK, RETRY, RUN, RESULT }

var _world: Game
var _city: CityStreamer
var _hero: Hero
var _camera: ThirdPersonCamera
var _trial: TimeTrial
var _pilot: TrialPilot
var _phase := Phase.LOADING
var _time := 0.0
var _pitch := -0.15


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Hero")  # (no name prompt)
	Settings.set_value("show_stats", false)  # (the options menu's switch: a clean picture)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_trial = _world.get_node("TimeTrial")
	_pilot = TrialPilot.new(_hero, _camera)
	process_physics_priority = -20  # before the hero reads its input


func _physics_process(delta: float) -> void:
	_time += delta
	var input := _hero.input
	match _phase:
		Phase.LOADING:
			if _hero.frozen or _city.pending_count() > 0 or _world.get_node("HUD").has_node("LoadingScreen"):
				_time = 0.0
				return
			_next(Phase.LEAD_IN)
			print("[rec] start frame %d" % Engine.get_frames_drawn())
		Phase.LEAD_IN:
			input.clear()
			if _time > LEAD_IN:
				_next(Phase.TAKE_OFF)
		Phase.TAKE_OFF:
			# Toward checkpoint 1, through the start gate on the way.
			_pilot.steer(_trial.gate_position(1), delta)
			if _trial.state == TimeTrial.State.RUNNING:
				input.fly_toggle_pressed = true
				_next(Phase.CLIMB)
		Phase.CLIMB:
			input.clear()
			var ahead := _trial.gate_position(1)
			_pilot.turn_camera(TimeTrial.AVENUE, delta)
			_pitch = 0.05
			input.stick = Vector2(0.0, -1.0)
			input.vertical = 1.0 if _time < 1.6 else 0.0
			input.aim = _camera.aim_direction()
			var past := (_hero.world_position() - ahead).dot(TimeTrial.AVENUE)
			if past > 45.0 or _time > 9.0:
				print("[rec] flew over checkpoint 1 at %.0f m over the street; cleared: %d" % [
					_hero.world_position().y - ahead.y, _trial.next_gate - 1])
				_next(Phase.LOOK_BACK)
		Phase.LOOK_BACK:
			input.clear()  # (hovering)
			input.aim = _camera.aim_direction()
			_pilot.turn_camera(-TimeTrial.AVENUE, delta, 2.0)
			_pitch = -0.45
			if _time > 2.2:
				_press_key(KEY_R)
				_next(Phase.RETRY)
		Phase.RETRY:
			input.clear()
			_pitch = -0.15
			if _time > 0.1 and Input.is_physical_key_pressed(KEY_R):
				_release_key(KEY_R)
			if _hero.frozen:
				_time = 0.0
			elif _time > 1.2:
				_next(Phase.RUN)
		Phase.RUN:
			var gate := 0 if _trial.state != TimeTrial.State.RUNNING else _trial.next_gate
			_pilot.steer(_trial.gate_position(gate), delta)
			if _trial.state == TimeTrial.State.FINISHED:
				input.clear()
				print("[rec] finished in %s, splits %s" % [TimeTrial.format_time(_trial.elapsed), _trial.splits])
				_next(Phase.RESULT)
		Phase.RESULT:
			input.clear()
			if _time > HOLD:
				print("[rec] end frame %d" % Engine.get_frames_drawn())
				get_tree().quit()


func _process(delta: float) -> void:
	_camera.pitch = lerpf(_camera.pitch, _pitch, 1.0 - exp(-3.0 * delta))


func _next(phase: Phase) -> void:
	_phase = phase
	_time = 0.0


## A real key press, through Input like the keyboard's (Game handles R).
func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)


func _release_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
