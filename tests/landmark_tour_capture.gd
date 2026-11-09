extends Node
## Not a test: a deterministic player for recording landmark exploration with
## Godot's Movie Maker. It runs the real game (scenes/world.tscn, its launch
## options as given) and plays it only through ordinary inputs, each physics
## tick: the movement keys, Shift (super speed / boost), F (flight), Space and
## C (climb and descend) and the gamepad's right stick (look), steered toward
## the landmarks. Nothing in the game is changed: no teleports, cheats or time
## scaling (the driver reads the hero's and the camera's state to steer).
##
## The route: from ?spawn on Seventh Avenue, south of Times Square, it runs
## north at super speed into Times Square, takes off, climbs over midtown and
## flies east to Radio City Music Hall, 30 Rockefeller Plaza and St.
## Patrick's Cathedral, then slows down over the cathedral and quits.
## Uses a settings file of its own: a name (no prompt), stats text off.
##
## Record (Linux, under a virtual display; see docs/ROADMAP.md, Exploration):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/tour.avi \
##     res://tests/landmark_tour_capture.tscn -- --solo=1 --spawn=-80,20,140,0 \
##     --tiles_url=https://nycheroes.party/tiles/
## Without --write-movie it plays in real time, the same way.

const SETTINGS_FILE := "user://landmark_tour_settings.cfg"
## Flying this high (m above sea level) clears midtown's towers on the way
## (30 Rockefeller Plaza is 259 m).
const CRUISE_ALTITUDE := 285.0
## The camera looks down this much while flying (radians), to see the streets.
const CRUISE_PITCH := -0.32
## Waits after the loading screen is gone before moving (s).
const SETTLE := 1.5
## Takes off this long after Times Square is discovered (s).
const TAKE_OFF_DELAY := 0.8
## Holds over the last landmark this long before quitting (s).
const LINGER := 8.5
const ROUTE: Array[String] = ["Radio City Music Hall", "30 Rockefeller Plaza", "St. Patrick's Cathedral"]

enum Phase { LOADING, SETTLE, RUN, TAKE_OFF, FLY, LINGER, DONE }

var _world: Game
var _hero: Hero
var _camera: ThirdPersonCamera
var _discovery: LandmarkDiscovery
var _phase := Phase.LOADING
var _phase_time := 0.0
var _target := 0
var _time := 0.0
var _since_found := 0.0


func _ready() -> void:
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Explorer")
	Settings.set_value("show_stats", false)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.hero
	_camera = _world.hero_camera
	_discovery = _world.discovery
	_discovery.discovered.connect(func(n: int, found: int, total: int) -> void:
		print("[tour] %.2f s: discovered %s (%d/%d) at %s, %.0f m up" % [_time, LandmarkDiscovery.LANDMARKS[n].name,
			found, total, _hero.world_position().snapped(Vector3.ONE), _hero.world_position().y]))


func _physics_process(delta: float) -> void:
	_time += delta
	_phase_time += delta
	if int(_time * 2.0) != int((_time - delta) * 2.0):  # (twice a second, for the record)
		print("[tour] %.1f s %s: %s %s, %.0f m/s, yaw %.2f pitch %.2f" % [_time, Phase.keys()[_phase],
			_hero.mode.name, _hero.world_position().snapped(Vector3.ONE), _hero.velocity.length(), _camera.yaw,
			_camera.pitch])
	match _phase:
		Phase.LOADING:
			if _world.get_node_or_null("HUD/LoadingScreen") == null and not _hero.frozen:
				_go(Phase.SETTLE)
		Phase.SETTLE:
			if _phase_time > SETTLE:
				_go(Phase.RUN)
		Phase.RUN:
			# North up Seventh Avenue into Times Square; a moment after it's
			# discovered, take off.
			_hold("move_forward", 1.0)
			_hold("sprint", 1.0)
			_steer(_discovery.positions[_index("Times Square")], 0.05)
			if _discovery.found[_index("Times Square")]:
				_since_found += delta
			if _since_found > TAKE_OFF_DELAY:
				_release_all()
				_tap("fly_toggle")
				_go(Phase.TAKE_OFF)
		Phase.TAKE_OFF:
			# Straight up with the boost, turning toward the first landmark.
			_hold("jump", 1.0)
			_hold("sprint", 1.0 if _hero.world_position().y < CRUISE_ALTITUDE - 150.0 else 0.0)
			_steer(_target_position(), CRUISE_PITCH)
			if _hero.world_position().y > CRUISE_ALTITUDE - 25.0:
				_hold("jump", 0.0)
				_go(Phase.FLY)
		Phase.FLY:
			var target := _target_position()
			var distance := Vector2(target.x - _hero.world_position().x, target.z - _hero.world_position().z).length()
			_steer(target, CRUISE_PITCH)
			_hold_altitude(CRUISE_ALTITUDE)
			_hold("move_forward", 1.0)
			_hold("sprint", 1.0 if distance > 220.0 else 0.0)  # boost, then cruise in
			if _discovery.found[_index(ROUTE[_target])]:  # on to the next
				_target += 1
				if _target >= ROUTE.size():
					_release_all()
					_go(Phase.LINGER)
		Phase.LINGER:
			# Let go of the stick (flight hovers), look down at the cathedral and
			# drift down a little.
			_steer(_discovery.positions[_index(ROUTE[-1])], -0.6)
			_hold_altitude(CRUISE_ALTITUDE - 40.0)
			if _phase_time > LINGER:
				_release_all()
				_go(Phase.DONE)
				print("[tour] done at %.2f s: %d/%d landmarks found" % [_time, _discovery.found_count(),
					_discovery.total()])
				get_tree().quit()


func _go(phase: Phase) -> void:
	print("[tour] %.2f s (frame %d): %s at %s" % [_time, Engine.get_frames_drawn(), Phase.keys()[phase],
		_hero.world_position().snapped(Vector3.ONE)])
	_phase = phase
	_phase_time = 0.0


func _index(landmark_name: String) -> int:
	for n in LandmarkDiscovery.LANDMARKS.size():
		if LandmarkDiscovery.LANDMARKS[n].name == landmark_name:
			return n
	return -1


func _target_position() -> Vector3:
	return _discovery.positions[_index(ROUTE[mini(_target, ROUTE.size() - 1)])]


## The right stick, turned toward a world position and to a pitch (as a player
## would, a little at a time: the stick's turn rate is the camera's).
func _steer(world_target: Vector3, pitch: float) -> void:
	var at := _hero.world_position()
	var want_yaw := atan2(-(world_target.x - at.x), -(world_target.z - at.z))
	var yaw_error := wrapf(want_yaw - _camera.yaw, -PI, PI)
	var turn := clampf(yaw_error * 1.6, -1.0, 1.0)
	_hold("look_left", maxf(turn, 0.0))
	_hold("look_right", maxf(-turn, 0.0))
	var pitch_turn := clampf((pitch - _camera.pitch) * 2.0, -1.0, 1.0)
	_hold("look_up", maxf(pitch_turn, 0.0))
	_hold("look_down", maxf(-pitch_turn, 0.0))


## Space and C (as analog as a trigger) to keep to an altitude while flying.
func _hold_altitude(altitude: float) -> void:
	var error := altitude - _hero.world_position().y
	var vertical := clampf(error / 15.0 - _hero.velocity.y / 20.0, -1.0, 1.0)
	_hold("jump", maxf(vertical, 0.0))
	_hold("descend", maxf(-vertical, 0.0))


func _hold(action: StringName, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


## A press, seen as "just pressed" by the next physics tick.
func _tap(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	get_tree().create_timer(0.1, true, true).timeout.connect(func() -> void:
		var release := InputEventAction.new()
		release.action = action
		release.pressed = false
		Input.parse_input_event(release))


func _release_all() -> void:
	for action: StringName in [&"move_forward", &"sprint", &"jump", &"descend", &"look_left", &"look_right",
			&"look_up", &"look_down"]:
		Input.action_release(action)
