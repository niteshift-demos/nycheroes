extends Node3D
## Synthetic geometry, real hero physics. No city tiles or network required.
## godot --headless --path . res://tests/wall_run_test.tscn

var hero: Hero
var failures := 0


func _ready() -> void:
	_box(Vector3(0.0, 99.5, 0.0), Vector3(80.0, 1.0, 200.0))
	_box(Vector3(2.5, 110.0, 0.0), Vector3(1.0, 20.0, 200.0))
	hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	await _reset()
	hero.input.move = Vector3(0.2, 0.0, -1.0).normalized()
	hero.input.sprint_held = true
	await _ticks(10)
	_check(hero.wall_running, "directional sprint engages in air")
	var before := hero.world_position()
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	await _ticks(2)
	_check(hero.wall_running and hero.world_position().distance_to(before) < 1.0, "run survives origin shift")
	hero.input.jump_held = true
	await _ticks(1)
	_check(not hero.wall_running and hero.velocity.x < -9.0 and hero.velocity.y > 12.0, "fresh jump kicks away and up")
	hero.input.jump_held = false
	await _ticks(1)
	hero.global_position = WorldOrigin.to_local(Vector3(1.5, 105.0, 0.0))
	await _ticks(2)
	_check(not hero.wall_running, "same airtime cannot reattach after kick")
	await _reset()
	hero.input.move = Vector3(0.2, 0.0, -1.0).normalized()
	hero.input.sprint_held = true
	await _ticks(75)
	_check(not hero.wall_running and (hero.mode as OnFootMode).wall_remaining <= 0.0, "run expires after 1.1 seconds")
	await _reset()
	hero.input.move = Vector3.RIGHT
	hero.input.sprint_held = true
	await _ticks(5)
	_check(not hero.wall_running, "head-on pushing cannot run upward")
	await _reset()
	hero.input.move = Vector3(0.2, 0.0, -1.0).normalized()
	hero.input.sprint_held = true
	await _ticks(8)
	hero.input.sprint_held = false
	await _ticks(1)
	_check(not hero.wall_running, "releasing sprint drops immediately")
	var sync := PlayerSync.new()
	var encoded := sync._encode(hero)
	_check(encoded.size() == 13 and int(encoded[5]) & PlayerSync.WALL_RUNNING == 0, "wire format remains compatible")
	hero.wall_running = true
	_check(int(sync._encode(hero)[5]) & PlayerSync.WALL_RUNNING != 0, "wall visual state is network visible")
	var copy: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	copy.remote_id = 2
	add_child(copy)
	var snapshots := SnapshotBuffer.new()
	hero.wall_run_side = -1.0
	var state := sync._encode(hero)
	snapshots.push(float(state[0]), state)
	sync._follow(copy, snapshots)
	_check(copy.wall_running and copy.wall_run_side == -1.0, "remote snapshot restores wall pose and shoulder")
	copy.queue_free()
	sync.free()
	print("wall_run_test: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _reset() -> void:
	hero.input.clear()
	hero.global_position = WorldOrigin.to_local(Vector3(1.5, 100.05, 0.0))
	hero.velocity = Vector3.ZERO
	await _ticks(12)
	hero.global_position.y = 105.0
	hero.velocity = Vector3.ZERO
	await _ticks(1)


func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1


func _box(at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("floating")
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	add_child(body)
