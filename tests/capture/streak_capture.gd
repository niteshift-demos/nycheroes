extends Node
## Plays the real game (scenes/world.tscn, as launched normally) for a video
## of the combat streak, pressing only the ordinary input actions a player
## would (move_forward, sprint, attack, and the look_left/look_right stick to
## turn the camera toward the nearest thug the HUD marker points at). Nothing
## in the game is changed or cheated: thugs are the EncounterDirector's own
## gangs, damage, AI and timing are untouched. After a gang is cleared it lets
## go of everything for a few seconds, so the streak can time out; thugs that
## land punches break it as they normally would. Logs what happens (frame,
## game time, streak, hits, health) as JSON lines for choosing the clip.
##
## Record with Godot's Movie Maker (from the repository root):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/streak/movie.avi \
##     res://tests/capture/streak_capture.tscn -- --tiles_url=https://nycheroes.party/tiles/ \
##     --solo=1 --name=Agent
## (--capture_seconds=N: game seconds of play after the city loads; default 75.)

## Within this distance of the target thug, punch.
const PUNCH_RANGE := 2.4
## Farther than this, sprint (super speed) to close in.
const SPRINT_RANGE := 30.0
## Thugs farther than this are ignored (spawns are 55-110 m away).
const HUNT_RANGE := 160.0
## After a gang is down, let go of the controls this long (s) before hunting.
const REST_TIME := 4.5

var _world: Node
var _hero: Hero
var _camera: ThirdPersonCamera
var _encounters: EncounterDirector
var _frame := 0
var _play_time := -1.0  # game seconds since the city loaded (-1: still loading)
var _rest := 0.0
var _seconds := 75.0
var _log: FileAccess
var _last_count := 0


func _ready() -> void:
	_seconds = LaunchOptions.get_string("capture_seconds", "75").to_float()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_encounters = _world.get_node("Encounters")
	process_physics_priority = -20  # before PlayerInput reads the actions
	_log = FileAccess.open(LaunchOptions.get_string("capture_log", "user://streak_capture.jsonl"), FileAccess.WRITE)
	Combat.streak.ended.connect(func(count: int, reason: StringName) -> void:
		_event({ended = count, reason = reason}))


func _process(_delta: float) -> void:
	_frame += 1


func _physics_process(delta: float) -> void:
	_release_all()
	var city: CityStreamer = _world.get_node("City")
	if _play_time < 0.0:
		if not _hero.frozen and city.pending_count() == 0:
			_play_time = 0.0
			_event({started = true})
		return
	_play_time += delta
	if _play_time >= _seconds:
		_event({finished = true, best = Combat.streak.best, down = Combat.defeated_count})
		_log.close()
		get_tree().quit()
		return
	if Combat.streak.count != _last_count:
		if Combat.streak.count > _last_count:
			_event({hits = Combat.streak.count - _last_count, streak = Combat.streak.count})
		_last_count = Combat.streak.count
	if _play_time < 2.0 or _hero.mode.name == &"KnockedOut":
		return
	if _rest > 0.0:
		_rest -= delta
		return
	var thug := _encounters.nearest_thug(_hero.world_position())
	var to := Vector3.ZERO
	if thug:
		to = thug.global_position - _hero.global_position
		to.y = 0.0
	if thug == null or to.length() > HUNT_RANGE:
		if Combat.streak.count > 0:
			_rest = REST_TIME  # gang cleared: hands off, let the streak run out
			_event({rest = REST_TIME})
		return
	# Turn the camera toward the thug with the look stick, as a player would.
	var want := atan2(-to.x, -to.z)
	var error := wrapf(want - _camera.yaw, -PI, PI)
	var turn := clampf(absf(error) * 2.5, 0.0, 1.0)
	if turn > 0.05:
		Input.action_press(&"look_left" if error > 0.0 else &"look_right", turn)
	var distance := to.length()
	if distance > PUNCH_RANGE:
		Input.action_press(&"move_forward", 1.0 if absf(error) < 0.6 else 0.4)
		if distance > SPRINT_RANGE and absf(error) < 0.3:
			Input.action_press(&"sprint")
	elif fmod(_play_time, 0.3) < 0.12:  # tap attack about three times a second
		Input.action_press(&"attack")


func _release_all() -> void:
	for action: StringName in [&"look_left", &"look_right", &"move_forward", &"sprint", &"attack"]:
		Input.action_release(action)


func _event(data: Dictionary) -> void:
	data.merge({frame = _frame, t = snappedf(maxf(_play_time, 0.0), 0.01),
		health = int(_hero.health), streak = Combat.streak.count, mode = String(_hero.mode.name)})
	if _log:
		_log.store_line(JSON.stringify(data))
