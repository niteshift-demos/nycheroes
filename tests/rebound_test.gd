extends Node3D
## Synthetic real-physics landing checks, without city downloads.
## Run: godot --headless --path . res://tests/rebound_test.tscn

var hero: Hero
var failures := 0

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2000, 1, 2000)
	collision.shape = shape
	floor_body.position.y = 9.5
	floor_body.add_child(collision)
	floor_body.add_to_group("floating")
	add_child(floor_body)
	hero = preload("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	await _drop("timed", true, false, false, 12.0)
	await _drop("origin shift", true, false, false, 12.0)
	await _drop("early hold", false, true, false, 12.0)
	await _drop("expired press", false, false, false, 12.0)
	await _drop("stationary", true, false, false, 0.0)
	await _drop("dive priority", true, false, true, 12.0)
	await _drop("hard timed", true, false, false, 60.0)
	await _drop("speed cap", true, false, false, 120.0)
	await _drop("ordinary hard landing", false, false, false, 12.0)
	print("REBOUND CHECKS: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _drop(label: String, timed: bool, early: bool, slam: bool, speed: float) -> void:
	hero.input.clear()
	hero.global_position = Vector3(0, 60 if label.contains("hard") else 18, 0)
	hero.velocity = Vector3(speed, 0, 0)
	hero.slam_pending = slam
	hero.rebound_feedback = 0.0
	hero.set_mode(&"OnFoot")
	var bounced := false
	var impact := false
	for tick in 240:
		hero.input.jump_held = (label == "expired press" and hero.rebound_eta >= 0.0 and hero.rebound_eta < 0.5) or early or (timed and hero.rebound_eta >= 0.0 and hero.rebound_eta < 0.09)
		await get_tree().physics_frame
		if label == "origin shift" and tick == 8:
			WorldOrigin.shift(Vector3(500, 0, 0))
		if hero.rebound_feedback > 0.0:
			bounced = true
			var sync := PlayerSync.new()
			var state := sync._encode(hero)
			_check((int(state[5]) & PlayerSync.GROUNDED) == 0 and (state[2] as Vector3).y > 0.0, label + " network takeoff")
			sync.free()
			_check(hero.velocity.y >= 18.0 and hero.velocity.y <= Hero.REBOUND_MAX_RISE, label + " bounded lift")
			_check(hero.horizontal_speed() >= minf(speed, Hero.REBOUND_MAX_SPEED) - 1.0 and hero.horizontal_speed() <= Hero.REBOUND_MAX_SPEED, label + " momentum")
			await get_tree().physics_frame
			_check(hero.velocity.y > 0.0, label + " leaves floor next tick")
			break
		if hero.is_on_floor():
			impact = true
			break
	var expected := timed and not slam and speed >= Hero.REBOUND_MIN_SPEED
	_check(bounced == expected and (bounced or impact), label)
	print("%s: bounced=%s grounded=%s" % [label, bounced, impact])
	if WorldOrigin.offset != Vector3.ZERO:
		WorldOrigin.shift(-WorldOrigin.offset)
	hero.input.clear()
	for i in 3:
		await get_tree().physics_frame

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
