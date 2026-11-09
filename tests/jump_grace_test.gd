extends Node3D
## Synthetic collision fixtures exercise normal HeroInput at 60 Hz, without city data.
## Run: godot --headless --path . res://tests/jump_grace_test.tscn

const DT := 1.0 / 60.0
var _hero: Hero
var _failures := 0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 2.0, 10.0)
	shape.shape = box
	floor_body.position.y = 9.0
	floor_body.add_child(shape)
	add_child(floor_body)
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(_hero)
	_hero.set_physics_process(false)
	_hero.frozen = false
	await _checks()
	print("Jump grace: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _checks() -> void:
	await _reset(Vector3(0.0, 10.05, 0.0))
	await _ticks(3, true)
	await _ticks(1)
	_check(_hero.velocity.y > 11.0, "ground tap still jumps")
	await _ticks(1, true)
	_check(_hero.velocity.y < 11.8, "ground jump cannot grant another jump in the air")

	await _reset(Vector3(0.0, 10.05, 0.0))
	await _ticks(80, true)
	await _ticks(1)
	_check(_hero.velocity.y > 79.0, "held ground jump keeps full super jump power")

	await _reset(Vector3(4.7, 10.05, 0.0))
	await _walk_off()
	await _ticks(2)
	await _ticks(1, true)
	_check(_hero.velocity.y > 11.0, "press shortly after walking off a ledge jumps")
	await _ticks(1)
	var before := _hero.velocity.y
	await _ticks(1, true)
	_check(_hero.velocity.y < before, "ledge grace is consumed by the first jump")

	await _reset(Vector3(4.7, 10.05, 0.0))
	await _walk_off()
	await _ticks(10)
	await _ticks(1, true)
	_check(_hero.velocity.y < 0.0, "late ledge press cannot jump")

	await _reset(Vector3(0.0, 10.12, 0.0), false)
	await _ticks(1, true)
	await _ticks(20)
	_check(_hero.velocity.y > 0.0 and _hero.position.y > 10.2, "released pre-landing tap is buffered")
	await _ticks(70)
	_check(_hero.is_on_floor(), "one buffered tap never auto-bounces twice")

	await _reset(Vector3(0.0, 10.12, 0.0), false)
	await _ticks(20, true)
	var on_foot := _hero.get_mode(&"OnFoot") as OnFootMode
	_check(on_foot.charging and _hero.is_on_floor(), "held pre-landing press starts charging on touchdown")
	_check(on_foot.charge < 0.16, "time in the air adds no charge")
	await _ticks(65, true)
	await _ticks(1)
	_check(_hero.velocity.y > 79.0, "buffered hold can still charge a full super jump")

	await _reset(Vector3(0.0, 14.0, 0.0), false)
	await _ticks(1, true)
	await _ticks(55)
	_check(_hero.is_on_floor() and is_zero_approx(_hero.velocity.y), "old airborne press expires before landing")

	await _reset(Vector3(0.0, 10.12, 0.0), false)
	await _ticks(1, true)
	_hero.set_mode(&"Flight")
	_hero.set_mode(&"OnFoot")
	await _ticks(30)
	_check(_hero.is_on_floor(), "changing modes clears a pending landing jump")

	await _reset(Vector3(0.0, 10.05, 0.0))
	on_foot.begin_jump()
	_hero.set_mode(&"Melee")
	on_foot.begin_jump()
	_hero.set_mode(&"OnFoot")
	await _ticks(3, true)
	await _ticks(1)
	_check(_hero.velocity.y > 11.0, "melee jump handoff still works")


func _reset(at: Vector3, settle := true) -> void:
	_hero.set_mode(&"Flight")
	_hero.set_mode(&"OnFoot")
	_hero.position = at
	_hero.velocity = Vector3.ZERO
	_hero.input.clear()
	_hero.move_and_slide()
	await _ticks(12 if settle else 1)


func _ticks(count: int, held := false, move := Vector3.ZERO) -> void:
	for tick in count:
		await get_tree().physics_frame
		_hero.input.clear()
		_hero.input.jump_held = held
		_hero.input.move = move
		_hero._physics_process(DT)


func _walk_off() -> void:
	for tick in 90:
		await _ticks(1, false, Vector3.RIGHT)
		if not _hero.is_on_floor():
			return
	_check(false, "fixture must reach ledge")


func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failures += 1
