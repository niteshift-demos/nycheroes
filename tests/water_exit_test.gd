extends Node3D
## Synthetic collision regression using the production hero and normal HeroInput.
## Run: godot --headless --path . res://tests/water_exit_test.tscn

var _hero: Hero
var _failures := 0


func _ready() -> void:
	await _case("low shore", 0.8, false, true)
	await _case("partly submerged shore", -0.35, false, true)
	await _case("underwater shelf", -1.0, false, false)
	await _case("high seawall", 3.0, false, false)
	await _case("blocked headroom", 0.8, true, false)
	await _case("raised lake", 0.8, false, true, 37.0)
	await _case("shifted origin", 0.8, false, true, 0.0, true)
	await _jump_case()
	print("water_exit_test: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _box(at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.position = at
	body.add_to_group("floating")
	return body


func _case(label: String, height: float, roof: bool, expected: bool, water := 0.0, shift := false) -> void:
	var shore := _box(Vector3(51.0, water + height - 2.0, 0.0), Vector3(100.0, 4.0, 8.0))
	var ceiling: StaticBody3D
	if roof:
		ceiling = _box(Vector3(0.0, water + 1.0, 0.0), Vector3(1.8, 0.2, 6.0))
	var lake: StaticBody3D
	if water > 0.0:
		lake = _box(Vector3(0.0, water - 0.1, 0.0), Vector3(30.0, 0.2, 30.0))
		lake.collision_layer = CityStreamer.WATER_LAYER
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(_hero)
	_hero.position = Vector3(0.0, water - 1.2, 0.0)
	_hero.frozen = false
	_hero._prev_jump = true
	if shift:
		WorldOrigin.shift(Vector3(500.0, 0.0, -500.0))
	for tick in 120:
		_hero.input.clear()
		_hero.input.move = Vector3.RIGHT
		# Hold before touching the wall: no dependence on a one-tick press.
		_hero.input.jump_held = true
		await get_tree().physics_frame
	var exited := not _hero.is_in_water() and _hero.is_on_floor()
	_check(exited == expected, "%s: exited=%s y=%.2f" % [label, exited, _hero.global_position.y])
	_hero.queue_free()
	shore.queue_free()
	if ceiling:
		ceiling.queue_free()
	if lake:
		lake.queue_free()
	await get_tree().physics_frame
	if shift:
		WorldOrigin.shift(-WorldOrigin.offset)


func _jump_case() -> void:
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(_hero)
	_hero.position.y = -1.2
	_hero.frozen = false
	var highest := -INF
	for tick in 60:
		_hero.input.jump_held = tick == 2
		await get_tree().physics_frame
		highest = maxf(highest, _hero.position.y)
	_check(highest > 1.5, "open water jump: peak=%.2f" % highest)
	_hero.queue_free()


func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["OK" if ok else "FAIL", message])
	if not ok:
		_failures += 1
