extends Node
## Headless check of flight's air brake in the real city: boosting along an
## open avenue then braking (with the stick and boost still held) stops the
## hero in the distance FlightMode.stopping_distance() predicts and holds it in
## a hover, much shorter than just letting go; braking while descending keeps
## descending and lands; and the brake is in the state PlayerSync sends.
## Exits non-zero on failure.
## Run: godot --headless --path . res://tests/flight_brake_test.tscn
## (without a local tile copy: -- --tiles_url=https://nycheroes.party/tiles/)

const AVENUE := Vector3(0.485, 0.0, -0.875)
## Start of a 700 m stretch of avenue with no buildings in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)

var _world: Game
var _hero: Hero
var _flight: FlightMode
var _city: CityStreamer
var _players: PlayerSync
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _failures: PackedStringArray = []
var _mark := Vector3.ZERO  # world position where the step started
var _predicted := 0.0
var _stopped_at := -1.0
var _sent_braking := false
var _max_height_change := 0.0


func _ready() -> void:
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	_world = world
	world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = world.get_node("Hero")
	_flight = _hero.get_mode(&"Flight") as FlightMode
	_city = world.get_node("City")
	_players = world.get_node("Players")
	process_physics_priority = -20  # before the hero: scripted input is used at once
	_check_formula()
	_steps = [
		_step("wait for the city to load", 180.0, Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0),
		_step("go to the open avenue", 0.5, func(_i: HeroInput, t: float) -> void:
			if t < 0.02:
				_teleport(OPEN_AVENUE)),
		_step("take off and climb", 2.5, func(i: HeroInput, t: float) -> void:
			i.fly_toggle_pressed = t < 0.02
			i.vertical = 1.0),
		_step("boost along the avenue", 4.0, _boost),
		_step("let go (no brake)", 3.0, Callable(), Callable(), _check_drift),
		_step("boost again", 4.0, _boost),
		_step("brake, stick and boost still held", 2.0, func(i: HeroInput, _t: float) -> void:
			_boost(i, 0.0)
			i.brake_held = true, Callable(), _check_brake),
		_step("let go: still hovering", 1.0, Callable(), Callable(), func() -> void:
			_expect(_hero.velocity.length() < 0.5, "hovering after the brake (%.2f m/s)" % _hero.velocity.length())),
		_step("boost a third time", 2.0, _boost),
		_step("brake while descending", 1.5, func(i: HeroInput, _t: float) -> void:
			i.brake_held = true
			i.vertical = -1.0, Callable(), func() -> void:
				var flat := Vector2(_hero.velocity.x, _hero.velocity.z).length()
				_expect(flat < 0.5, "braking while descending stops across (%.2f m/s)" % flat)
				_expect(absf(_hero.velocity.y + _flight.cruise_speed) < 1.0,
					"braking while descending still descends at cruise speed (%.1f m/s)" % _hero.velocity.y)),
		_step("keep braking down to the street", 15.0, func(i: HeroInput, _t: float) -> void:
			i.brake_held = true
			i.vertical = -1.0, func() -> bool: return _hero.mode.name == &"OnFoot",
			func() -> void: _expect(_hero.mode.name == &"OnFoot", "landed on the street (now %s)" % _hero.mode.name)),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)
	if _hero.input.brake_held and _hero.mode.name == &"Flight":
		if _predicted < 0.0:  # first braking tick: what the HUD would say
			_predicted = _flight.stopping_distance(_flight.speed_to_shed())
		if _stopped_at < 0.0 and _hero.velocity.length() < 0.5:
			_stopped_at = _time
		_max_height_change = maxf(_max_height_change, absf(_hero.world_position().y - _mark.y))
		# (Sent state is read before this tick moves the hero: the last tick's.)
		var flags: int = _players._encode(_hero)[5]
		_sent_braking = _sent_braking or (_flight.braking and flags & PlayerSync.BRAKING != 0)

	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	print("%-36s %5.1fs  mode %-7s speed %6.1f  at %s" % [step.name, _time, _hero.mode.name,
		_hero.velocity.length(), _hero.world_position().round()])
	if step.check.is_valid():
		step.check.call()
	if _index + 1 >= _steps.size():
		_expect(_sent_braking, "PlayerSync sends the braking flag")
		if _failures.is_empty():
			print("PASS")
			get_tree().quit(0)
		else:
			print("FAIL:\n  " + "\n  ".join(_failures))
			get_tree().quit(1)
		return
	_begin(_index + 1)


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	_mark = _hero.world_position()
	_predicted = -1.0
	_stopped_at = -1.0
	_max_height_change = 0.0


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable(), check := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until, check = check}


func _boost(input: HeroInput, _t: float) -> void:
	input.stick = Vector2(0.0, -1.0)
	input.aim = AVENUE
	input.sprint_held = true


var _drift := 0.0

func _check_drift() -> void:
	_drift = _mark.distance_to(_hero.world_position())
	print("  letting go drifted %.1f m and still moves at %.2f m/s" % [_drift, _hero.velocity.length()])
	_expect(_hero.velocity.length() > 0.05, "letting go alone hasn't quite stopped")


func _check_brake() -> void:
	var travelled := _mark.distance_to(_hero.world_position())
	print("  braked in %.1f m (predicted %.1f m), stopped after %.2f s, height change %.1f m" % [
		travelled, _predicted, _stopped_at, _max_height_change])
	_expect(_predicted > 30.0, "braking from boost speed (predicted %.1f m)" % _predicted)
	_expect(absf(travelled - _predicted) < maxf(_predicted * 0.08, 2.0),
		"stopping distance %.1f m matches the prediction %.1f m" % [travelled, _predicted])
	_expect(_stopped_at > 0.0 and _stopped_at < 1.2, "stopped within 1.2 s (%.2f s)" % _stopped_at)
	_expect(_hero.velocity.length() < 0.5, "hovering with the stick still pushed")
	_expect(_max_height_change < 3.0, "kept its height (%.1f m)" % _max_height_change)
	_expect(travelled < _drift * 0.8, "braking (%.1f m) stops well short of letting go (%.1f m)" % [travelled, _drift])
	_expect(_hero.mode.name == &"Flight", "still flying")


## stopping_distance() against stepping the brake's rule at 60 ticks a second.
func _check_formula() -> void:
	for start: float in [33.0, 150.0, 187.5]:
		var speed := start
		var distance := 0.0
		var dt := 1.0 / 60.0
		while speed > 0.0:
			var next := maxf(speed - (_flight.brake_deceleration + _flight.brake_damping * speed) * dt, 0.0)
			distance += (speed + next) * 0.5 * dt
			speed = next
		var predicted := _flight.stopping_distance(start)
		print("formula: from %5.1f m/s stops in %5.1f m (stepped %5.1f m)" % [start, predicted, distance])
		_expect(absf(distance - predicted) < maxf(predicted * 0.06, 0.5),
			"stopping_distance(%.1f) %.1f m matches stepping %.1f m" % [start, predicted, distance])


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
		push_error("FAILED: " + what)


func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO
