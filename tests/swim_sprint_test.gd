extends Node
## Headless check of super swimming in the real Hudson: holding sprint builds
## speed up gradually (not at once) to swim_super_speed, a fresh sprint press
## kicks off a surge to about swim_surge_speed, a second press during the
## cooldown does nothing, a fast swimmer turns in a wide arc, the hero stays in
## the water all the while (skimming higher in a surge), jumping out ends a
## surge, and a co-op copy of the hero sees the surge (PlayerSync's SURGING
## flag). Exits non-zero if any check fails.
## Run: godot --headless --path . res://tests/swim_sprint_test.tscn
## (with no local tiles, add -- --tiles_url=https://nycheroes.party/tiles/)

## Up the Hudson, roughly parallel to the shores (Manhattan's avenues' heading).
const UPRIVER := Vector3(0.485, 0.0, -0.875)
## A spot in the Hudson River, west of Midtown (world meters).
const HUDSON := Vector3(-2200.0, 5.0, 0.0)

var _world: Game
var _hero: Hero
var _on_foot: OnFootMode
var _city: CityStreamer
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _stats := {}
var _failures: Array[String] = []
## Values a later check compares against.
var _surge_peak := 0.0
var _heading_before := Vector3.ZERO


func _ready() -> void:
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	_world = world
	world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = world.get_node("Hero")
	_on_foot = _hero.get_mode(&"OnFoot") as OnFootMode
	_city = world.get_node("City")
	process_physics_priority = -20  # before the hero reads its input
	_steps = [
		_step("wait for the city to load", 60.0, Callable(), Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0),
		_step("drop into the Hudson", 15.0, func(_i: HeroInput, t: float) -> void:
			if t < 0.02:
				_world.place_hero(HUDSON, 0.0, true),
			func() -> void:
				_check(_hero.is_in_water(), "in the water after dropping in"),
			func() -> bool: return _time > 4.0 and not _hero.frozen),
		_step("paddle upriver", 2.0, func(i: HeroInput, _t: float) -> void: _move(i, UPRIVER),
			func() -> void:
				_check(absf(_speed() - _on_foot.swim_speed) < 0.5, "paddles at swim speed (%.1f)" % _speed())),
		# The first press of sprint surges at once: paddle speed plus the kick.
		_step("press and hold sprint", 0.3, func(i: HeroInput, _t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = true,
			func() -> void:
				_check(_stats.max_speed > _on_foot.swim_speed + _on_foot.swim_surge_kick - 1.0,
					"sprint press kicks off a surge (max %.1f)" % _stats.max_speed)
				_check(_stats.surge_ticks > 0, "surge is on")
				_check(_speed() < _on_foot.swim_super_speed - 1.0,
					"then builds up toward super swimming, not at once (%.1f)" % _speed())
				_check(_stats.dry_ticks == 0, "stays in the water while surging")
				_check(_stats.max_height > _stats.start_height + 0.15,
					"rides higher in a surge (%.2f m up)" % (_stats.max_height - _stats.start_height))),
		_step("hold sprint to full super swimming", 3.5, func(i: HeroInput, _t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = true,
			func() -> void:
				_check(absf(_speed() - _on_foot.swim_super_speed) < 0.5,
					"reaches super swimming speed (%.1f)" % _speed())
				_check(_stats.dry_ticks == 0, "stays in the water at super speed")),
		# Tapping sprint again once the cooldown is over: a surge from super speed.
		_step("tap sprint again: surge", 0.5, func(i: HeroInput, t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = t < 0.05 or t > 0.1,
			func() -> void:
				_surge_peak = _stats.max_speed
				_check(_surge_peak > _on_foot.swim_surge_speed - 2.0 and _surge_peak <= _on_foot.swim_surge_speed + 0.01,
					"surge from super speed reaches the cap (%.1f)" % _surge_peak)
				_check(_stats.dry_ticks == 0, "stays in the water in the big surge")),
		_step("surge runs out", 1.0, func(i: HeroInput, _t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = true,
			func() -> void:
				_check(_on_foot.surge_time == 0.0, "surge has ended")
				_check(_speed() < _on_foot.swim_super_speed + 1.0, "back to super swimming speed (%.1f)" % _speed())),
		# The cooldown (2.5 s from the last surge) isn't over yet: no kick.
		_step("tap sprint during the cooldown", 0.5, func(i: HeroInput, t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = t < 0.05 or t > 0.1,
			func() -> void:
				_check(_stats.surge_ticks == 0, "no surge during the cooldown")
				_check(_stats.max_speed < _on_foot.swim_super_speed + 1.0,
					"no kick during the cooldown (max %.1f)" % _stats.max_speed)),
		_step("turn hard at super speed", 0.5, func(i: HeroInput, t: float) -> void:
			if t < 0.02:
				_heading_before = _heading()
			_move(i, UPRIVER.cross(Vector3.UP))  # hard right
			i.sprint_held = true,
			func() -> void:
				var turned := _heading_before.angle_to(_heading())
				_check(turned > 0.5 and turned < 1.4, "turns in a wide arc at speed (%.2f rad in 0.5 s)" % turned)),
		_step("let go and drift to a stop", 2.5, Callable(),
			func() -> void:
				_check(_speed() < 0.5, "drifts to a stop (%.1f)" % _speed())),
		_step("surge, then jump out", 1.2, func(i: HeroInput, t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = true
			i.jump_held = t > 0.2 and t < 0.3,
			func() -> void:
				_check(_stats.surge_ticks > 0, "surged before the jump")
				_check(_on_foot.surge_time == 0.0, "jumping out ends the surge")
				_check(_stats.dry_ticks > 0, "leapt out of the water")),
		_step("co-op copy sees a surge", 2.0, func(i: HeroInput, t: float) -> void:
			_move(i, UPRIVER)
			i.sprint_held = t > 1.6,  # back in the water first, then a fresh press
			func() -> void: _check_copy()),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	var step := _steps[_index]
	_time += delta
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)

	if not _hero.frozen:
		_stats.max_speed = maxf(_stats.max_speed, _speed())
		_stats.max_height = maxf(_stats.max_height, _hero.world_position().y)
		if _on_foot.surge_time > 0.0:
			_stats.surge_ticks += 1
		if not _hero.is_in_water():
			_stats.dry_ticks += 1

	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	print("%-36s %5.1fs  speed %5.1f  max %5.1f  surge ticks %3d  dry ticks %3d  at %s" % [
		step.name, _time, _speed(), _stats.max_speed, _stats.surge_ticks, _stats.dry_ticks,
		_hero.world_position().round()])
	if step.check.is_valid():
		step.check.call()
	if _index + 1 >= _steps.size():
		if _failures.is_empty():
			print("PASS: swim sprint")
		else:
			print("FAIL: swim sprint\n  " + "\n  ".join(_failures))
		get_tree().quit(1 if not _failures.is_empty() else 0)
		return
	_begin(_index + 1)


## Hands the hero's state to a stand-in co-op copy the way PlayerSync does
## for another player's game, and checks the copy shows the surge.
func _check_copy() -> void:
	var players: PlayerSync = _world.get_node("Players")
	_check(_on_foot.surge_time > 0.0, "surging when the state is sent")
	var state := players._encode(_hero)
	_check(int(state[5]) & PlayerSync.SURGING != 0, "sent state has the SURGING flag")
	var copy: Hero = PlayerSync.HERO_SCENE.instantiate()
	copy.remote_id = 99
	copy.frozen = true
	players.add_child(copy)
	var buffer := SnapshotBuffer.new()
	buffer.push(float(state[0]), state)
	players._follow(copy, buffer)
	var copy_on_foot := copy.get_mode(&"OnFoot") as OnFootMode
	_check(copy_on_foot.surge_time > 0.0, "the copy is surging")
	_check(copy.is_in_water(), "the copy is in the water")
	copy.queue_free()


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	var y := _hero.world_position().y
	_stats = {max_speed = 0.0, max_height = y, start_height = y, surge_ticks = 0, dry_ticks = 0}


func _step(step_name: String, seconds: float, apply := Callable(), check := Callable(), until := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, check = check, until = until}


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _speed() -> float:
	return Vector2(_hero.velocity.x, _hero.velocity.z).length()


func _heading() -> Vector3:
	return Vector3(_hero.velocity.x, 0.0, _hero.velocity.z).normalized()


func _move(input: HeroInput, direction: Vector3) -> void:
	input.move = direction
	input.stick = Vector2(0.0, -1.0)
