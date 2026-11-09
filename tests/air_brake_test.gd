extends Node3D
## Headless pass/fail check of the flight air brake (FlightMode, HeroInput's
## brake_held), on a bare hero high in empty air with one wall put in its
## way, so the numbers don't depend on which city tiles have loaded:
## - From full sustained boost (~187 m/s), letting go drifts ~75 m; holding
##   the brake stops dead (exactly 0 m/s) in under 30 m and under 2 s.
## - From cruise (33 m/s) the brake stops within 6 m.
## - Precision hover: brake + stick (even with boost held) moves at
##   precision_speed in any direction, climbing included.
## - The limit: braking 12 m before a wall at full boost still hits it;
##   braking 45 m before it stops short without touching.
## - On foot the brake does nothing (and `braking` stays false).
## - Co-op: PlayerSync sends `braking` and a copy of the hero shows it.
## Run: godot --headless --path . res://tests/air_brake_test.tscn

const HERO_SCENE := preload("res://scenes/hero/hero.tscn")
const START := Vector3(0.0, 400.0, 0.0)
const NORTH := Vector3(0.0, 0.0, -1.0)

var _hero: Hero
var _flight: FlightMode
var _failures: Array[String] = []
var _apply := Callable()


func _ready() -> void:
	_hero = HERO_SCENE.instantiate()
	add_child(_hero)
	_flight = _hero.get_mode(&"Flight") as FlightMode
	_hero.frozen = false
	# Before the hero each tick, so the scripted input is used right away.
	process_physics_priority = -20
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	_hero.input.clear()
	_hero.input.aim = NORTH
	if _apply.is_valid():
		_apply.call(_hero.input)


func _run() -> void:
	# Letting go at full boost: the old way to stop.
	var coast := await _stop_from_boost(false)
	print("let go at %.1f m/s: %.1f m, %.2f s to under 0.5 m/s" % [coast.speed, coast.distance, coast.time])
	_check(coast.speed > 180.0, "full boost reaches ~187 m/s (got %.1f)" % coast.speed)

	var braked := await _stop_from_boost(true)
	print("braked at %.1f m/s: %.1f m, %.2f s to a dead stop" % [braked.speed, braked.distance, braked.time])
	_check(braked.distance < 30.0, "brake stops from full boost in under 30 m (%.1f)" % braked.distance)
	_check(braked.distance < coast.distance * 0.5, "brake stops in under half the drift of letting go")
	_check(braked.time < 2.0, "brake reaches a dead stop in under 2 s (%.2f)" % braked.time)
	_check(_hero.velocity == Vector3.ZERO, "brake holds a dead stop (exactly 0 m/s)")
	_check(_flight.braking, "`braking` is set while the brake is held")

	# From cruise speed.
	await _fly_at(Vector2(0.0, -1.0), false, 3.0)
	var cruise := _hero.velocity.length()
	var from := _hero.world_position()
	_apply = func(i: HeroInput) -> void: i.brake_held = true
	await _ticks(60)
	var cruise_stop := _hero.world_position().distance_to(from)
	print("braked at cruise %.1f m/s: %.1f m" % [cruise, cruise_stop])
	_check(cruise_stop < 6.0, "brake stops from cruise within 6 m (%.1f)" % cruise_stop)

	# Precision hover: forward with boost held, then straight up.
	_apply = func(i: HeroInput) -> void:
		i.brake_held = true
		i.sprint_held = true
		i.stick = Vector2(0.0, -1.0)
	await _ticks(60)
	var creep := _hero.velocity
	print("precision hover forward: %.2f m/s %s" % [creep.length(), creep.normalized().round()])
	_check(absf(creep.length() - _flight.precision_speed) < 0.1, "precision hover moves at precision_speed with boost held")
	_check(creep.normalized().dot(NORTH) > 0.99, "precision hover goes where the stick points")
	_apply = func(i: HeroInput) -> void:
		i.brake_held = true
		i.vertical = 1.0
	await _ticks(60)
	print("precision hover up: %.2f m/s" % _hero.velocity.y)
	_check(absf(_hero.velocity.y - _flight.precision_speed) < 0.1, "precision hover climbs at precision_speed")
	_apply = Callable()
	await _ticks(2)
	_check(not _flight.braking, "`braking` clears when the brake is let go")

	# The limit: too late before a wall still hits it; early enough doesn't.
	var late := await _brake_before_wall(12.0)
	var early := await _brake_before_wall(45.0)
	print("brake 12 m before a wall: hit %s; 45 m before: hit %s, stopped %.1f m short" % [late.hit, early.hit, early.gap])
	_check(late.hit, "braking 12 m before a wall at full boost still hits it")
	_check(not early.hit and early.gap > 1.0, "braking 45 m before a wall stops short of it")

	# Co-op: the copy of our hero shows the brake.
	await _co_op_flag()

	# On foot the brake does nothing.
	_hero.set_mode(&"OnFoot")
	_hero.global_position = START
	_hero.velocity = Vector3(0.0, 0.0, -9.0)
	_apply = func(i: HeroInput) -> void:
		i.brake_held = true
		i.stick = Vector2(0.0, -1.0)
		i.move = NORTH
	await _ticks(10)
	print("on foot with the brake held: mode %s, braking %s" % [_hero.mode.name, _flight.braking])
	_check(_hero.mode.name == &"OnFoot" and not _flight.braking, "the brake doesn't act on foot")

	if _failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: " + failure)
		get_tree().quit(1)


## Flies north at full sustained boost, then lets go or brakes: returns the
## speed it started stopping at, and the distance and time it took.
func _stop_from_boost(braking: bool) -> Dictionary:
	await _fly_at(Vector2(0.0, -1.0), true, 8.0)
	var speed := _hero.velocity.length()
	var from := _hero.world_position()
	var time := 0.0
	_apply = func(i: HeroInput) -> void: i.brake_held = braking
	while _hero.velocity.length() > (0.0 if braking else 0.5) and time < 10.0:
		await get_tree().physics_frame
		time += get_physics_process_delta_time()
	await get_tree().physics_frame  # one more tick: the hero has moved
	return {speed = speed, distance = _hero.world_position().distance_to(from), time = time}


## Starts flying at START (fresh) and holds the stick (with boost) for `seconds`.
func _fly_at(stick: Vector2, boost: bool, seconds: float) -> void:
	_hero.set_mode(&"OnFoot")
	_hero.global_position = START
	_hero.velocity = Vector3.ZERO
	_hero.set_mode(&"Flight")
	_apply = func(i: HeroInput) -> void:
		i.stick = stick
		i.sprint_held = boost
	await _ticks(roundi(seconds * Engine.physics_ticks_per_second))


## Boosts north at full speed with a wall `gap` meters ahead at the moment
## the brake goes on; returns whether the hero touched it, and how far short
## it stopped.
func _brake_before_wall(gap: float) -> Dictionary:
	await _fly_at(Vector2(0.0, -1.0), true, 8.0)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 200.0, 2.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	# The hero's capsule is 0.35 m thick; the wall's face is `gap` ahead of it.
	wall.global_position = _hero.global_position + NORTH * (gap + 0.35 + 1.0)
	await get_tree().physics_frame  # (the brake goes on this same tick)
	var hit := false
	_apply = func(i: HeroInput) -> void: i.brake_held = true
	for tick in 120:
		await get_tree().physics_frame
		hit = hit or _hero.is_on_wall()
	var face := wall.global_position.z + 1.0
	var gap_left := _hero.global_position.z - 0.35 - face
	wall.queue_free()
	await get_tree().physics_frame
	return {hit = hit, gap = gap_left}


func _co_op_flag() -> void:
	await _fly_at(Vector2.ZERO, false, 0.1)
	_apply = func(i: HeroInput) -> void: i.brake_held = true
	await _ticks(2)
	var sync := PlayerSync.new()
	var copy: Hero = HERO_SCENE.instantiate()
	copy.remote_id = 2
	add_child(copy)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(Time.get_ticks_msec(), sync._encode(_hero))
	sync._follow(copy, snapshots)
	var copy_flight := copy.get_mode(&"Flight") as FlightMode
	print("co-op copy: mode %s, braking %s" % [copy.mode.name, copy_flight.braking])
	_check(copy.mode.name == &"Flight" and copy_flight.braking, "a co-op copy shows the brake")
	_apply = Callable()
	await _ticks(2)
	# (A fresh buffer: one state, shown at once rather than DELAY behind.)
	snapshots = SnapshotBuffer.new()
	snapshots.push(Time.get_ticks_msec(), sync._encode(_hero))
	sync._follow(copy, snapshots)
	_check(not copy_flight.braking, "a co-op copy's brake clears when ours does")
	copy.queue_free()
	sync.free()


func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
