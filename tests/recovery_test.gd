extends Node
## Headless check of out-of-combat recovery (Hero.recovering): no health comes
## back while thugs are near or hitting, it starts only after
## Hero.RECOVERY_DELAY clear of the fight, comes back at Hero.RECOVERY_RATE, a
## hit stops it and starts the wait over, and a knockout still happens (health
## stays at zero until the hero gets up). Exits non-zero on a failed check.
## Run: godot --headless --path . res://tests/recovery_test.tscn
## (no local tiles: add -- --tiles_url=https://nycheroes.party/tiles/)

const AVENUE := Vector3(0.485, 0.0, -0.875)
## A long stretch of 6th Avenue with nothing in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _failures: PackedStringArray = []
var _mark := 0.0  # health when a step started
var _peak := 0.0
var _healed_while_down := false


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	process_physics_priority = -20
	_steps = [
		_step("wait for the city to load", 90.0, Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0),
		_step("thugs attack", 10.0, func(t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
				_spawn_gang(OPEN_AVENUE + AVENUE * 3.0, 2),
			func() -> bool: return _hero.health <= 85.0),
		_step("no recovery in the fight", 4.0, func(t: float) -> void:
			if t == 0.0:
				_mark = _hero.health
			_check(_hero.in_combat, "in combat with thugs close")
			_check(not _hero.recovering, "no recovery with thugs close")
			_check(_hero.health <= _mark + 0.01, "health didn't rise in the fight")
			_mark = minf(_mark, _hero.health)),
		_step("leave the fight", Hero.RECOVERY_DELAY - 0.3, func(t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE + AVENUE * 250.0)
				_mark = _hero.health
			elif t > 0.5:  # (a hit landing as we left may still stagger)
				_check(not _hero.in_combat, "out of combat once away")
			_check(not _hero.recovering, "waits before recovering")
			_check(_hero.health <= _mark + 0.01, "no health during the wait")),
		_step("recover", 4.0, func(t: float) -> void:
			if t == 0.0:
				_mark = _hero.health),
		_step("check recovery", 0.0, func(_t: float) -> void:
			_check(_hero.recovering, "recovering after the wait")
			var gained := _hero.health - _mark
			print("  gained %.1f health in 4 s (rate %.1f/s)" % [gained, Hero.RECOVERY_RATE])
			_check(gained > 2.0 * Hero.RECOVERY_RATE and gained < 4.5 * Hero.RECOVERY_RATE, "restrained rate")),
		_step("a hit interrupts", 10.0, func(t: float) -> void:
			if t == 0.0:
				_spawn_gang(_hero.world_position() + AVENUE * 3.0, 1)
				_peak = _hero.health,
			func() -> bool: return _hero.hurt_time > 0.0),
		_step("check interrupted", 0.0, func(_t: float) -> void:
			_check(_hero.health < _peak, "the hit took health")
			_check(not _hero.recovering and _hero.recovery_clear == 0.0, "the hit restarted the wait")),
		_step("knocked out anyway", 15.0, func(t: float) -> void:
			if t == 0.0:
				_hero.health = 8.0,
			func() -> bool: return _hero.mode.name == &"KnockedOut"),
		_step("no recovery while down", 6.0, func(_t: float) -> void:
			if _hero.mode.name == &"KnockedOut" and (_hero.recovering or _hero.health > 0.0):
				_healed_while_down = true,
			func() -> bool: return _hero.mode.name == &"OnFoot"),
		_step("check knockout", 0.0, func(_t: float) -> void:
			_check(not _healed_while_down, "no health while knocked out")
			_check(_hero.mode.name == &"OnFoot" and _hero.health == Hero.MAX_HEALTH, "got up at full health")),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_index = 0
	var step := _steps[_index]
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_time)
	_time += delta
	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	if step.until.is_valid() and not step.until.call() and _index > 0:
		_check(false, "%s within %.0f s" % [step.name, step.seconds])
	print("%-28s %5.1fs  mode %-10s health %5.1f  in combat %-5s  clear %.1f  recovering %s" % [
		step.name, _time, _hero.mode.name, _hero.health, _hero.in_combat, _hero.recovery_clear, _hero.recovering])
	_index += 1
	_time = 0.0
	if _index >= _steps.size():
		if _failures.is_empty():
			print("PASS")
		else:
			print("FAIL:\n  " + "\n  ".join(_failures))
		get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	if not ok and not _failures.has(what):
		_failures.append(what)
		print("  failed: " + what)


func _spawn_gang(world_center: Vector3, count: int) -> void:
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


func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until}
