extends Node
## Headless check of the incoming-punch warning (ThreatWarning, in the HUD):
## it shows only while a thug really winds up a punch at our hero, it fills
## up in step with the swing and is there for most of it before the punch
## lands, the player can act on it in time (stepping out of reach makes the
## punch miss; hitting the thug cuts the swing and the warning short), and
## thugs not swinging at us get none. Exits non-zero on failure.
## Run: godot --headless --path . res://tests/threat_warning_test.tscn

const AVENUE := Vector3(0.485, 0.0, -0.875)
## A long open stretch of 6th Avenue (world meters), as in combat_test.
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")
## The warning must be up at least this long before the punch lands (s): a
## reaction is about a quarter second.
const MIN_LEAD := 0.35

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _warning: ThreatWarning
var _checks: Array[String] = []
var _failed := false
var _phase := "load"
var _time := 0.0
var _thug: Thug
var _others: Array[Thug] = []
# Per phase: when the warning first showed, its last progress, and health then.
var _warned_at := -1.0
var _last_progress := -1.0
var _health_at_warning := 0.0
var _progress_steady := true
var _shown_while_not_punching := false
var _most_warnings := 0


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	_hero.input.clear()
	_time += delta
	if _warning == null:
		_warning = _world.find_child("ThreatWarning", true, false) as ThreatWarning
	match _phase:
		"load":
			if not _hero.frozen and _city.pending_count() == 0:
				_check(_warning != null, "the HUD has a ThreatWarning")
				_check(_warning != null and _warning.size == _warning.get_viewport_rect().size,
					"it covers the screen (%s)" % (_warning.size if _warning else Vector2.ZERO))
				_check(_warning != null and _warning.incoming().is_empty(), "no warning with no thugs about")
				_start("take a punch")
			elif _time > 60.0:
				_check(false, "the city loaded")
				_finish()
		"take a punch":
			_hero.health = Hero.MAX_HEALTH  # (regen meanwhile; only drops matter)
			_watch(false)
			if _hero.hurt_time > 0.0 and _warned_at >= 0.0:
				var lead := _time - _warned_at
				_check(lead >= MIN_LEAD, "warned %.2f s before the punch landed (thug windup %.2f s)" % [lead, Thug.PUNCH_HIT_TIME])
				_check(_last_progress > 0.85, "the warning was nearly full as it landed (%.2f)" % _last_progress)
				_check(_progress_steady, "the warning filled steadily")
				_check(not _shown_while_not_punching, "no warning while the thug only ran up")
				_start("step out of reach")
			elif _hero.hurt_time > 0.0:
				_check(false, "a warning before the punch landed")
				_start("step out of reach")
			elif _time > 12.0:
				_check(false, "the thug punched within 12 s")
				_finish()
		"step out of reach":
			if _watch(true):
				# React as a player would: run straight away from the thug.
				var away := _hero.global_position - _thug.global_position
				away.y = 0.0
				_hero.input.move = away.normalized()
				_hero.input.stick = Vector2(0.0, -1.0)
				_hero.input.sprint_held = true
			if _warned_at >= 0.0 and _time - _warned_at > Thug.PUNCH_HIT_TIME + 0.2:
				_check(_hero.health >= _health_at_warning,
					"running away on the warning dodged the punch (health %d -> %d)" % [int(_health_at_warning), int(_hero.health)])
				_start("hit first")
			elif _time > 12.0:
				_check(false, "the thug swung within 12 s")
				_finish()
		"hit first":
			if _watch(true):
				var toward := _thug.global_position - _hero.global_position
				toward.y = 0.0
				_hero.input.aim = toward.normalized()
				_hero.face_toward(toward)
				_hero.input.attack_held = true
			if _warned_at >= 0.0 and _time - _warned_at > Thug.PUNCH_HIT_TIME + 0.2:
				_check(_thug.health < 100.0, "the hero's punch landed on the thug")
				_check(_hero.health >= _health_at_warning,
					"punching back on the warning cut the swing short (health %d -> %d)" % [int(_health_at_warning), int(_hero.health)])
				_start("a gang")
			elif _time > 12.0:
				_check(false, "the thug swung within 12 s")
				_finish()
		"a gang":
			_hero.health = Hero.MAX_HEALTH
			var shown := _warning.incoming()
			_most_warnings = maxi(_most_warnings, shown.size())
			for threat: Array in shown:
				var thug: Thug = threat[0]
				if thug.state != Thug.State.PUNCH:
					_shown_while_not_punching = true
			if _time > 8.0:
				_check(_most_warnings >= 1, "the gang's punches were warned of")
				_check(_most_warnings <= Combat.MAX_ATTACKERS, "at most %d warnings at once (%d)" % [Combat.MAX_ATTACKERS, _most_warnings])
				_check(not _shown_while_not_punching, "only swinging thugs were marked")
				_check(_far_thugs_unmarked(), "far thugs got no warning")
				_finish()


## Watches the warning for _thug; returns true from the tick it first shows.
func _watch(react: bool) -> bool:
	var progress := -1.0
	for threat: Array in _warning.incoming():
		if threat[0] == _thug:
			progress = threat[1]
		if (threat[0] as Thug).state != Thug.State.PUNCH:
			_shown_while_not_punching = true
	if progress >= 0.0:
		if _warned_at < 0.0:
			_warned_at = _time
			_health_at_warning = _hero.health
		elif progress < _last_progress:
			_progress_steady = false
		_last_progress = progress
	return react and _warned_at >= 0.0


func _far_thugs_unmarked() -> bool:
	for threat: Array in _warning.incoming():
		if (threat[0] as Thug).global_position.distance_to(_hero.global_position) > ThreatWarning.RANGE:
			return false
	return true


func _start(phase: String) -> void:
	print("-- " + phase)
	_phase = phase
	_time = 0.0
	_warned_at = -1.0
	_last_progress = -1.0
	_progress_steady = true
	_shown_while_not_punching = false
	for thug in Combat.thugs.duplicate():
		thug.queue_free()
	_hero.health = Hero.MAX_HEALTH
	_hero.hurt_time = 0.0
	_teleport(OPEN_AVENUE)
	if phase == "a gang":
		_spawn(OPEN_AVENUE + AVENUE * 6.0, 4)
		_others = _spawn(OPEN_AVENUE + AVENUE * 30.0, 2)  # (on the same street, further off,
		for thug in _others:  # holding still)
			thug.frozen = true
	else:
		_thug = _spawn(OPEN_AVENUE + AVENUE * 6.0, 1)[0]


func _spawn(world_center: Vector3, count: int) -> Array[Thug]:
	var made: Array[Thug] = []
	for k in count:
		var thug: Thug = THUG_SCENE.instantiate()
		add_child(thug)
		var spot := world_center + Vector3(AVENUE.z, 0.0, -AVENUE.x) * (k - (count - 1) * 0.5) * 1.6
		spot.y = _hero.world_position().y
		var ground := _city.ground_height_at(spot, 6.0)
		if not is_nan(ground):
			spot.y = ground
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(_hero, k, TAU * k / count)
		made.append(thug)
	return made


func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _check(ok: bool, what: String) -> void:
	print(("ok      " if ok else "FAILED  ") + what)
	_failed = _failed or not ok


func _finish() -> void:
	print("threat warning: %s" % ("FAILED" if _failed else "all ok"))
	get_tree().quit(1 if _failed else 0)
