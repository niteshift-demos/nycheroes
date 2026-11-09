extends Node
## Headless check of health coming back between fights (HealthRecovery): the
## wait before it starts, its rate, never past full health, thugs near or a
## hit stopping it, nothing back while knocked out, getting up with
## KO_HEALTH (not full) and the wait starting over, and the HUD's state for
## each. Exits non-zero on any failure.
## Run: godot --headless --path . res://tests/recovery_test.tscn

const AVENUE := Vector3(0.485, 0.0, -0.875)
## A long stretch of 6th Avenue with nothing in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _failures := 0


func _ready() -> void:
	_check_rules()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	await _run()
	print("recovery_test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


## The rules on their own, tick by tick.
func _check_rules() -> void:
	var recovery := HealthRecovery.new()
	var health := 50.0
	recovery.interrupt()
	for tick in 60 * 5:  # 5 s of a 6 s wait
		health = recovery.step(1.0 / 60.0, health, 100.0, false)
	_check(health == 50.0 and not recovery.recovering, "rules: nothing back during the wait (%.1f)" % health)
	for tick in 60 * 2:
		health = recovery.step(1.0 / 60.0, health, 100.0, false)
	_check(recovery.recovering and health > 50.0 and health <= 50.0 + HealthRecovery.RATE * 1.05,
		"rules: slow recovery after the wait (%.2f)" % health)
	health = recovery.step(1.0 / 60.0, health, 100.0, true)
	_check(not recovery.recovering and recovery.in_combat and recovery.wait == HealthRecovery.DELAY,
		"rules: fighting stops it and restarts the wait")
	recovery.wait = 0.0
	health = 99.9
	for tick in 60:
		health = recovery.step(1.0 / 60.0, health, 100.0, false)
	_check(health == 100.0 and not recovery.recovering, "rules: never past full (%.3f)" % health)


func _run() -> void:
	if not await _wait_until(func() -> bool: return not _hero.frozen and _city.pending_count() == 0, 60.0):
		_check(false, "the city loaded")
		return
	_teleport(OPEN_AVENUE)
	await _seconds(0.5)

	# Hurt, alone: the HUD counts down, then health creeps back.
	_hero.health = 50.0
	_hero.recovery.interrupt()
	await _seconds(HealthRecovery.DELAY - 0.6)
	_check(is_equal_approx(_hero.health, 50.0) and not _hero.recovery.recovering and not _hero.recovery.in_combat,
		"no recovery during the wait (health %.1f, wait %.1f s)" % [_hero.health, _hero.recovery.wait])
	await _seconds(2.6)
	var gained := _hero.health - 50.0
	_check(_hero.recovery.recovering and gained > 4.0 and gained < 10.0,
		"slow recovery after %.0f s out of combat (+%.1f)" % [HealthRecovery.DELAY, gained])

	# A gang 25 m off: in combat, so it stops at once (before any punch lands).
	var before := _hero.health
	_spawn_gang(_hero.world_position() + AVENUE * 25.0, 3)
	await _seconds(0.2)
	_check(_hero.recovery.in_combat and not _hero.recovery.recovering and _hero.health <= before + 0.01,
		"thugs near stop it (health %.1f -> %.1f)" % [before, _hero.health])

	# Standing still among them: hits land, nothing comes back, down we go.
	_hero.health = 15.0
	var knocked := await _wait_until(func() -> bool: return _hero.mode.name == &"KnockedOut", 30.0)
	_check(knocked, "knocked out by the gang")
	var highest := 0.0
	var ever_recovering := false
	var ticks := 0
	while _hero.mode.name == &"KnockedOut" and ticks < 6 * Engine.physics_ticks_per_second:
		highest = maxf(highest, _hero.health)
		ever_recovering = ever_recovering or _hero.recovery.recovering
		await get_tree().physics_frame
		ticks += 1
	_check(highest == 0.0 and not ever_recovering, "nothing comes back while down (highest %.1f)" % highest)
	_check(is_equal_approx(_hero.health, HealthRecovery.KO_HEALTH) and not _hero.recovery.recovering,
		"up with %.0f health, not full, and not recovering yet (%.1f)" % [HealthRecovery.KO_HEALTH, _hero.health])

	# Away from the thugs (far past their notice range): the wait, then recovery.
	_teleport(OPEN_AVENUE + AVENUE * 400.0)
	await _seconds(0.2)
	_check(not _hero.recovery.in_combat and not _hero.recovery.recovering and _hero.recovery.wait > HealthRecovery.DELAY - 0.5,
		"away from the gang: the wait starts over (%.1f s left)" % _hero.recovery.wait)
	await _seconds(HealthRecovery.DELAY + 1.0)
	_check(_hero.recovery.recovering and _hero.health > HealthRecovery.KO_HEALTH,
		"then recovers (%.1f)" % _hero.health)

	# Co-op: other players are told (PlayerSync's flags); their copies don't run it.
	var sync := PlayerSync.new()
	var state := sync._encode(_hero)
	sync.free()
	_check(int(state[5]) & PlayerSync.RECOVERING != 0, "co-op: our hero's state says it's recovering")

	# A hit interrupts it.
	_hero.take_hit(1.0, Vector3.ZERO)
	_check(not _hero.recovery.recovering and _hero.recovery.wait == HealthRecovery.DELAY, "a hit interrupts it")

	# Near full: it stops at 100, through a world origin shift.
	_hero.health = Hero.MAX_HEALTH - 1.0
	_hero.recovery.wait = 0.0
	WorldOrigin.shift(Vector3(300.0, 0.0, 0.0))
	await _seconds(1.5)
	_check(_hero.health == Hero.MAX_HEALTH and not _hero.recovery.recovering,
		"stops at full health (%.2f)" % _hero.health)


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


## Waits `seconds` of game time (physics ticks).
func _seconds(seconds: float) -> void:
	var ticks := int(round(seconds * Engine.physics_ticks_per_second))
	for tick in ticks:
		await get_tree().physics_frame


func _wait_until(condition: Callable, timeout: float) -> bool:
	var ticks := int(timeout * Engine.physics_ticks_per_second)
	for tick in ticks:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
