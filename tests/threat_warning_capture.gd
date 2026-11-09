extends Node
## Plays a short street fight for recording the incoming-punch warning
## (ThreatWarning) with Godot's Movie Maker. It runs the real game
## (world.tscn, its HUD, city streaming and EncounterDirector's gangs) and
## plays it only through ordinary controls, pressed as Input actions the way
## a keyboard or gamepad would (move, sprint, attack, and the look stick for
## the camera), so PlayerInput turns them into HeroInput as usual. Nothing
## about the hero, the thugs or time is changed.
##
## The script steers by what the player would see: toward the nearest thug
## (the HUD's THUGS marker), and reacts to the warning on screen. It:
## 1. runs to the gang the game spawned and lets them surround the hero,
## 2. stands and takes a punch, the warning closing as it lands,
## 3. then reacts to each warning a player's reaction time after it shows,
##    taking turns: punch the swinging thug (a hit cuts its swing short), or
##    run straight away from it (out of reach, the punch misses). It never
##    attacks otherwise, so every thug that goes down went down to a
##    reaction. When a gang is down it runs on to the next one.
## The debug stats line is turned off (the options menu's "Show FPS and
## stats", in a settings file of its own), as a player would for a video.
## Prints "[capture] start <frame>" when the fight footage begins (after the
## city has loaded) and "[capture] end <frame>", so the loading can be trimmed
## off the front of the movie without retiming anything.
##
## Run (see docs/ROADMAP.md, "Incoming punch warning"):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/threat/movie.avi \
##     res://tests/threat_warning_capture.tscn -- --tiles_url=https://nycheroes.party/tiles/ \
##     --name=Hero --solo=1 --time=15 --quality=medium

## Give up on any one part after this long (s); the fight is a little random.
const PART_LIMIT := 9.0
## Close enough to the gang to stop and let them come.
const ARRIVE_DISTANCE := 3.0
## How long the fight footage runs (s), then a short tail.
const FOOTAGE := 29.0
## How long after a warning shows the hero reacts (s): about a player's
## reaction time, well inside the windup (Thug.PUNCH_HIT_TIME).
const REACTION_TIME := 0.18
const REACTIONS: Array[String] = ["punch", "dodge"]

var _world: Node
var _hero: Hero
var _camera: ThirdPersonCamera
var _warning: ThreatWarning
var _part := "load"
var _time := 0.0
var _total := 0.0
var _hurt := false
var _react_until := -1.0
var _reacted := 0
var _away := Vector3.ZERO
var _settle := 0.0
var _seen_at := -1.0
var _reaction := ""
var _gangs_met := 0
var _start_frame := 0
var _warned := {}  # thug -> true while its warning shows (for the log)


func _ready() -> void:
	Settings.use_file("user://threat_warning_capture_settings.cfg")
	Settings.set_value("show_stats", false)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_camera = _world.find_children("*", "ThirdPersonCamera", true, false)[0] as ThirdPersonCamera
	_hero.hurt.connect(func(damage: float) -> void:
		_hurt = true
		print("[capture]   punched for %d at frame %d (%s), health %d" % [damage, Engine.get_frames_drawn(), _part, _hero.health]))
	Combat.thug_defeated.connect(func(_thug: Thug) -> void:
		print("[capture]   thug down at frame %d (%s)" % [Engine.get_frames_drawn(), _part]))
	process_physics_priority = -20  # (before PlayerInput reads the actions)


func _physics_process(delta: float) -> void:
	_time += delta
	_total += delta
	_release_all()
	if _warning == null:
		_warning = _world.find_child("ThreatWarning", true, false) as ThreatWarning
	if _warning and _part != "load":
		_log_warnings()
	match _part:
		"load":
			var loading := _world.find_child("LoadingScreen", true, false)
			if loading == null and not _hero.frozen and _nearest_thug() != null:
				_settle += delta
				if _settle > 2.0:  # (a moment for the first frames' shaders)
					_next("approach")
			elif _total > 600.0:
				print("[capture] the city or a gang never showed up")
				get_tree().quit(1)
		"approach":
			var thug := _nearest_thug()
			if thug == null:
				return
			_look_at(thug.global_position)
			var distance := _flat(thug.global_position - _hero.global_position).length()
			if distance > ARRIVE_DISTANCE:
				Input.action_press("move_forward")
				if distance > 30.0:
					Input.action_press("sprint")  # (super speed; not into them: it bowls them over)
			if distance <= ARRIVE_DISTANCE or _time > 14.0:
				_next("take a punch" if _gangs_met == 0 else "react")
				_gangs_met += 1
		"take a punch":
			_look_at_gang()
			if (_hurt and _time > 0.5) or _time > PART_LIMIT:
				_next("react")
		"react":
			_react(delta)
			if _footage() > FOOTAGE:
				_next("tail")
			elif _react_until < 0.0 and _nearest_distance() > 15.0:
				_next("approach")  # this gang is down: on to the next (the THUGS marker)
		"tail":
			_look_at_gang()
			if _time > 1.0:
				print("[capture] end %d" % Engine.get_frames_drawn())
				get_tree().quit()


## Reacts to each warning a beat after it shows (REACTION_TIME, about a
## player's), taking turns: punch the swinging thug, or run straight away
## from it. Between warnings the hero just watches the gang (no attacks of
## its own), walking back up to it when it's further than a punch.
func _react(_delta: float) -> void:
	var threats := _warning.incoming()
	if _react_until < 0.0:
		_look_at_gang()
		if threats.is_empty():
			_seen_at = -1.0
			var distance := _nearest_distance()
			if distance > ARRIVE_DISTANCE and distance < 15.0:
				var thug := _nearest_thug()
				_look_at(thug.global_position)
				Input.action_press("move_forward")
			return
		if _seen_at < 0.0:
			_seen_at = _time
		if _time - _seen_at < REACTION_TIME:
			return
		var thug: Thug = threats[0][0]
		_reaction = REACTIONS[_reacted % REACTIONS.size()]
		_reacted += 1
		_react_until = _time + (0.3 if _reaction == "punch" else 0.5)
		_away = _flat(_hero.global_position - thug.global_position).normalized()
		print("[capture]   %s at frame %d, %.2f s after the warning showed" % [_reaction, Engine.get_frames_drawn(), _time - _seen_at])
	if _time < _react_until:
		if _reaction == "punch":
			Input.action_press("attack")
		else:
			_steer(_away)
	else:
		_react_until = -1.0
		_seen_at = -1.0


## Seconds of footage so far (since "[capture] start").
func _footage() -> float:
	return (Engine.get_frames_drawn() - _start_frame) / 30.0


func _nearest_distance() -> float:
	var thug := _nearest_thug()
	return _flat(thug.global_position - _hero.global_position).length() if thug else INF


func _log_warnings() -> void:
	var now := {}
	for threat: Array in _warning.incoming():
		now[threat[0]] = true
		if not _warned.has(threat[0]):
			print("[capture]   warning up at frame %d (%s), %d shown, thug %.1f m away" % [Engine.get_frames_drawn(), _part,
				_warning.incoming().size(), (threat[0] as Thug).global_position.distance_to(_hero.global_position)])
	_warned = now


func _next(part: String) -> void:
	if _part == "load":
		_start_frame = Engine.get_frames_drawn()
		print("[capture] start %d" % _start_frame)
	print("[capture] %s at frame %d (%.1f s in)" % [part, Engine.get_frames_drawn(), _total])
	_part = part
	_time = 0.0
	_hurt = false
	_react_until = -1.0
	_seen_at = -1.0


func _nearest_thug() -> Thug:
	var best: Thug = null
	var best_distance := INF
	for thug: Thug in Combat.thugs:
		if thug.is_down():
			continue
		var distance := thug.global_position.distance_to(_hero.global_position)
		if distance < best_distance:
			best_distance = distance
			best = thug
	return best


## Turns the camera toward the gang's middle (the standing thugs within 8 m),
## keeping the fight in view.
func _look_at_gang() -> void:
	var sum := Vector3.ZERO
	var count := 0
	for thug: Thug in Combat.thugs:
		if not thug.is_down() and thug.global_position.distance_to(_hero.global_position) < 8.0:
			sum += thug.global_position
			count += 1
	if count > 0:
		var middle := sum / count
		if _flat(middle - _hero.global_position).length() > 0.8:
			_look_at(middle)


## Pushes the look stick toward a point, as a player turning the camera would.
func _look_at(target: Vector3) -> void:
	var to := _flat(target - _hero.global_position)
	if to.length() < 0.3:
		return
	var desired := atan2(-to.x, -to.z)
	var difference := wrapf(desired - _camera.yaw, -PI, PI)
	var strength := clampf(absf(difference) * 1.5, 0.0, 1.0)
	if strength < 0.05:
		return
	Input.action_press("look_left" if difference > 0.0 else "look_right", strength)


## Pushes the movement stick toward a world direction (relative to the camera).
func _steer(direction: Vector3) -> void:
	var local := Basis(Vector3.UP, _camera.yaw).inverse() * direction
	if local.x > 0.2:
		Input.action_press("move_right", clampf(local.x, 0.0, 1.0))
	elif local.x < -0.2:
		Input.action_press("move_left", clampf(-local.x, 0.0, 1.0))
	if local.z > 0.2:
		Input.action_press("move_back", clampf(local.z, 0.0, 1.0))
	elif local.z < -0.2:
		Input.action_press("move_forward", clampf(-local.z, 0.0, 1.0))


func _release_all() -> void:
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint",
			&"attack", &"look_left", &"look_right"]:
		Input.action_release(action)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
