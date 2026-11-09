extends Node
## Headless check of the combo counter (ComboChain): punches that whiff count
## nothing, landed punches chain (each string's jab, cross and finisher marked
## landed), the chain drops after ComboChain.WINDOW without a landed hit and
## breaks at once when a thug's hit lands on the hero, a slam adds every thug
## it hurts, and the count rides in PlayerSync's
## state for other players. Exits non-zero on any failure.
## Run: godot --headless --path . res://tests/combo_test.tscn -- --tiles_url=https://nycheroes.party/tiles
## (or --tiles=DIR with a local build).

const AVENUE := Vector3(0.485, 0.0, -0.875)
## A long open stretch of 6th Avenue (world meters), as in combat_test.
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _players: PlayerSync
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _failures: PackedStringArray = []


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_players = _world.get_node("Players")
	process_physics_priority = -20
	_steps = [
		_step("wait for the city to load", 60.0, Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0, func() -> void:
			_check(not _hero.frozen, "the city loaded")),
		_step("whiff with nobody near", 1.6, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE)
			i.aim = AVENUE
			i.attack_held = fmod(t, 0.3) < 0.12, Callable(), func() -> void:
			_check(_hero.combo.count == 0 and _hero.combo.best == 0, "whiffs add nothing (count %d)" % _hero.combo.count)
			_check(_hero.combo.punches.has(ComboChain.Punch.MISSED), "a whiffed punch is marked missed")),
		_step("land a punch string", 1.5, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_spawn_gang(_hero.world_position() + AVENUE * 2.5, 3, 400.0)
			i.aim = AVENUE
			i.attack_held = fmod(t, 0.3) < 0.12, Callable(), func() -> void:
			_check(_hero.combo.best >= 3, "three landed punches chain (best %d)" % _hero.combo.best)
			_check(_hero.combo.count == 0 or _hero.combo.time_left > 0.0, "a live chain has time left")),
		_step("chain drops after the window", ComboChain.WINDOW + 0.6, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_land_fresh_hit()
				_teleport(OPEN_AVENUE + AVENUE * 150.0), Callable(), func() -> void:
			_check(_hero.combo.count == 0, "the chain dropped (count %d)" % _hero.combo.count)
			_check(_hero.combo.last_end == ComboChain.End.DROPPED, "it ended as dropped")),
		_step("a thug's hit breaks the chain", 4.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_spawn_gang(_hero.world_position() + AVENUE * 2.5, 3, 400.0)
			i.aim = AVENUE
			i.attack_held = t < 0.4 and fmod(t, 0.3) < 0.12,
			func() -> bool: return _hero.combo.last_end == ComboChain.End.BROKEN and _hero.combo.since_end < 0.1,
			func() -> void:
			_check(_hero.combo.last_end == ComboChain.End.BROKEN, "a thug landing a hit broke the chain")
			_check(_hero.combo.count == 0, "nothing left of the broken chain")),
		_step("a slam counts every thug hurt", 3.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE + AVENUE * 300.0)
				_spawn_gang(_hero.world_position() + AVENUE * 1.5, 3, 400.0)
				_hero.combo.count = 0
				_hero.slam_pending = true
				_hero.global_position.y += 3.0  # the slam lands a dive from just above
			i.aim = AVENUE,
			func() -> bool: return _hero.combo.count > 0, func() -> void:
			_check(_hero.combo.count >= 2 and _hero.combo.last_heavy, "the slam added the thugs it hurt (%d)" % _hero.combo.count)),
		_step("count goes to other players", 0.1, Callable(), Callable(), func() -> void:
			var flags: int = _players._encode(_hero)[5]
			_check((flags >> PlayerSync.COMBO_SHIFT) & PlayerSync.COMBO_MAX == mini(_hero.combo.count, PlayerSync.COMBO_MAX),
				"PlayerSync sends the count")
			_check(flags & (PlayerSync.COMBO_SHIFT - 1) <= PlayerSync.GROUNDED | PlayerSync.FROZEN | PlayerSync.CHARGING | PlayerSync.IN_WATER,
				"the count leaves the old flags alone")
			var copy := ComboChain.new()
			copy.set_remote_count((flags >> PlayerSync.COMBO_SHIFT) & PlayerSync.COMBO_MAX)
			_check(copy.count == _hero.combo.count, "a copy reads it back")),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_index = 0
	var step := _steps[_index]
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)
	_time += delta
	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	if step.check.is_valid():
		step.check.call()
	print("%-34s %5.1fs  combo %2d  best %2d  last end %d (%d hits)  punches %s  mode %s  health %d" % [
		step.name, _time, _hero.combo.count, _hero.combo.best, _hero.combo.last_end, _hero.combo.last_count,
		_hero.combo.punches, _hero.mode.name, int(_hero.health)])
	_index += 1
	_time = 0.0
	if _index >= _steps.size():
		if _failures.is_empty():
			print("combo_test: all checks passed")
		else:
			printerr("combo_test: %d failed:\n  %s" % [_failures.size(), "\n  ".join(_failures)])
		get_tree().quit(1 if not _failures.is_empty() else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


## One more landed hit, so the next step starts with a live chain.
func _land_fresh_hit() -> void:
	if _hero.combo.count == 0:
		_hero.combo.land(1, false)


func _spawn_gang(world_center: Vector3, count: int, health: float) -> void:
	for k in count:
		var thug: Thug = THUG_SCENE.instantiate()
		add_child(thug)
		var spot := world_center + Vector3(AVENUE.z, 0.0, -AVENUE.x) * (k - (count - 1) * 0.5) * 1.2
		spot.y = _hero.world_position().y
		var ground := _city.ground_height_at(spot, 6.0)
		if not is_nan(ground):
			spot.y = ground
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(_hero, k, TAU * k / count)
		thug.health = health


func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable(), check := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until, check = check}
