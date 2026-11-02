extends Node3D
## Synthetic physics checks, no city data. Run air_dash_test.tscn headless.

var _hero: Hero
var _failures := 0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = 9.0
	add_child(floor_body)
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(_hero)
	_hero.frozen = false
	_hero.position = Vector3(0.0, 15.0, 0.0)
	await _ticks(2)
	var start := _hero.position
	var vertical := _hero.velocity.y
	_hero.input.move = Vector3.RIGHT
	_hero.input.dash_pressed = true
	await _ticks(2)
	_check(_hero.velocity.x > 40.0, "directional burst responds in one tick")
	_check(_hero.velocity.y < vertical, "gravity continues; no extra jump height")
	_check(not _hero.dash_available, "charge spent")
	await _ticks(14)
	_check(_hero.dash_remaining == 0.0, "burst ends within 0.2 seconds")
	_check(_hero.position.x - start.x < 11.0, "burst distance bounded")
	_check(_hero.horizontal_speed() < 12.0, "burst does not permanently boost air speed")
	_hero.set_mode(&"Flight")
	_hero.input.dash_pressed = true
	await _ticks(2)
	_check(_hero.dash_remaining == 0.0, "flight toggle cannot refill")
	_hero.set_mode(&"OnFoot")
	_hero.input.clear()
	await _ticks(100)
	_check(_hero.is_on_floor() and _hero.dash_available, "stable dry landing refills")
	_hero.input.dash_pressed = true
	await _ticks(2)
	_check(_hero.dash_available, "ground press cannot spend dash")
	_hero.position.y = 15.0
	await _ticks(2)
	_hero.input.aim = Vector3.FORWARD
	_hero.input.dash_pressed = true
	await _ticks(2)
	_check(_hero.velocity.z < -40.0, "neutral stick uses camera heading")
	var velocity := _hero.velocity
	_hero._on_origin_shifted(Vector3(4000.0, 0.0, 0.0))
	_check(_hero.velocity == velocity, "origin shift preserves dash direction and speed")
	var sync := PlayerSync.new()
	var state := sync._encode(_hero)
	_check(state.size() == 13 and int(state[5]) & PlayerSync.DASHING != 0, "dash feedback encoded without changing packet shape")
	var remote: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	remote.remote_id = 123
	add_child(remote)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(100.0, state)
	sync._follow(remote, snapshots)
	_check(remote.dash_remaining > 0.0 and remote.velocity == _hero.velocity, "remote copy shows burst and motion")
	state = state.duplicate()
	state[5] = int(state[5]) & ~PlayerSync.DASHING
	var stopped := SnapshotBuffer.new()
	stopped.push(200.0, state)
	sync._follow(remote, stopped)
	_check(remote.dash_remaining == 0.0, "remote burst clears on next snapshot")
	remote.queue_free()
	sync.free()
	# Sweep a thin wall; a burst must not teleport through it.
	_hero.dash_remaining = 0.0
	_hero.position = Vector3(0.0, 15.0, 0.0)
	_hero.velocity = Vector3.ZERO
	_hero.dash_available = true
	_hero.dash_recovery = 0.0
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.1, 20.0, 20.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(2.0, 15.0, 0.0)
	add_child(wall)
	await _ticks(2)
	_hero.input.move = Vector3.RIGHT
	_hero.input.dash_pressed = true
	await _ticks(15)
	_check(_hero.position.x < 2.0 and _hero.dash_remaining == 0.0, "wall stops burst without tunneling")
	print("[air dash] %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	print("[air dash] %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
