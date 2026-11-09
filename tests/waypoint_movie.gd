extends Node
## Plays the real game (scenes/world.tscn at its default Times Square start)
## through the ordinary controls, for recording the waypoint with Godot's
## Movie Maker. Not a test: it presses keys and holds actions as a player
## would (G, F, Space, W and the look actions; Input.parse_input_event and
## Input.action_press), aiming the camera by holding the look actions until
## it points where a player watching the HUD's compass would point it. No
## teleporting and nothing set directly on the hero, the camera or the
## waypoint. The script:
##   1. stands on Broadway, takes off (F) and climbs (Space);
##   2. looks up at the sky and presses G: nothing to mark (the boundary);
##   3. looks down the avenue and presses G: a waypoint some 300 m off;
##   4. looks around (the compass arrow swings), then flies there (W),
##      steering by the compass: arriving clears it, and it quits.
## Its own settings file, so the player's are untouched.
## Record (Linux, under Xvfb; see docs/ROADMAP.md, "Personal waypoint"):
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --write-movie OUT.avi --fixed-fps 30 res://tests/waypoint_movie.tscn \
##     -- --solo=1 --tiles_url=https://nycheroes.party/tiles/

const SETTINGS_FILE := "user://waypoint_movie_settings.cfg"
## Seconds of game time (Movie Maker steps it 1/30 s a frame) for each step.
const IDLE := 1.5
const CLIMB := 3.5
const MAX_FLIGHT := 30.0
const OUTRO := 2.5
## Camera pitch for marking: down the avenue, a few hundred meters off.
const MARK_PITCH := -0.07
const SKY_PITCH := 1.0

var _world: Game
var _hero: Hero
var _camera: ThirdPersonCamera
var _waypoint: Waypoint
var _city: CityStreamer
var _log: Array[String] = []


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Hero")  # (no name prompt)
	Settings.set_value("show_stats", false)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_waypoint = _world.get_node("Waypoint")
	_city = _world.get_node("City")
	_waypoint.mark_failed.connect(func(reason: String) -> void: _note("mark failed: " + reason))
	_waypoint.changed.connect(func() -> void:
		_note("waypoint %s" % ("set %.0f m off" % _waypoint.ground_distance() if _waypoint.is_set() else "cleared")))
	_waypoint.reached.connect(func(what: String) -> void: _note("reached " + what))
	_play()


func _play() -> void:
	while _city.loaded_counts[0] == 0 or _city.pending_count() > 0 or _hero.frozen \
			or is_instance_valid(_world.get_node_or_null("HUD/LoadingScreen")):
		await get_tree().process_frame
	_note("city ready at frame %d" % Engine.get_frames_drawn())
	await _seconds(IDLE)
	await _key(KEY_F)  # fly
	Input.action_press(&"jump")  # climb
	await _seconds(CLIMB)
	Input.action_release(&"jump")
	await _look_to(_camera.yaw, SKY_PITCH)
	await _key(KEY_G)  # the sky: nothing to mark
	await _seconds(2.2)
	await _look_to(_camera.yaw, MARK_PITCH)
	await _key(KEY_G)  # down the avenue
	await _seconds(1.2)
	# A look around: the compass arrow swings, the marker slides to the edge.
	var ahead := _camera.yaw
	await _look_to(ahead - 2.2, 0.0)
	await _seconds(0.8)
	await _look_to(ahead, MARK_PITCH)
	var started := _time()
	Input.action_press(&"move_forward")
	while _waypoint.is_set() and _time() - started < MAX_FLIGHT:
		_steer()
		await get_tree().process_frame
	Input.action_release(&"move_forward")
	_release_look()
	_note("flight took %.1f s" % (_time() - started))
	await _seconds(OUTRO)
	print("\n".join(_log))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	get_tree().quit()


## Holds the look actions until the camera points that way (a player's
## mouse or stick).
func _look_to(yaw: float, pitch: float) -> void:
	while true:
		var yaw_off := wrapf(yaw - _camera.yaw, -PI, PI)
		var pitch_off := pitch - _camera.pitch
		if absf(yaw_off) < 0.03 and absf(pitch_off) < 0.03:
			break
		_press_look(yaw_off, pitch_off)
		await get_tree().process_frame
	_release_look()


## While flying there: turns toward the compass arrow, keeps the pitch for
## a gentle descent onto the spot.
func _steer() -> void:
	var to := _waypoint.world_position - _hero.world_position()
	var ground := Vector2(to.x, to.z).length()
	var pitch := clampf(atan2(to.y + 2.0, maxf(ground, 1.0)), -0.5, 0.1)
	_press_look(-_waypoint.bearing_from_view(), pitch - _camera.pitch)


func _press_look(yaw_off: float, pitch_off: float) -> void:
	var turn := clampf(yaw_off * 2.5, -1.0, 1.0)  # (positive yaw turns left)
	var tilt := clampf(pitch_off * 2.5, -1.0, 1.0)
	_set_action(&"look_left", maxf(turn, 0.0))
	_set_action(&"look_right", maxf(-turn, 0.0))
	_set_action(&"look_up", maxf(tilt, 0.0))
	_set_action(&"look_down", maxf(-tilt, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, maxf(strength, 0.3))  # (past the 0.15 dead zone)
	else:
		Input.action_release(action)


func _release_look() -> void:
	for action: StringName in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		Input.action_release(action)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = keycode
		key.keycode = keycode
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame
	_note("pressed %s" % OS.get_keycode_string(keycode))


func _seconds(seconds: float) -> void:
	var until := _time() + seconds
	while _time() < until:
		await get_tree().process_frame


## Game time: Movie Maker's fixed 1/30 s steps, not the wall clock.
var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta


func _time() -> float:
	return _elapsed


func _note(text: String) -> void:
	var line := "[movie %6.2f s, frame %d] %s" % [_elapsed, Engine.get_frames_drawn(), text]
	_log.append(line)
	print(line)
