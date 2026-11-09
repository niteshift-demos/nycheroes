extends Node3D
## Synthetic physics checks for checkpoint safety, cooldown, combat, and origins.
## godot --headless --path . res://tests/safe_return_test.tscn

var _failures := 0
var _hero: Hero


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.add_to_group("floating")
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 2, 80)
	floor_shape.shape = box
	floor_body.position.y = 1.0
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	_hero.position = Vector3(0, 2.02, 0)
	add_child(_hero)
	_hero.frozen = false
	await _ticks(20)
	var recovery := _hero.safe_return
	_hero.input.return_pressed = true
	await _ticks(1)
	_check(recovery.message.contains("first"), "return without a checkpoint is refused")
	_hero.input.checkpoint_pressed = true
	await _ticks(1)
	_check(recovery.checkpoint != Vector3.INF, "standing on dry static ground saves")
	var saved := recovery.checkpoint
	_hero.health = 73.0
	_hero.input.move = Vector3.RIGHT
	await _ticks(60)
	_hero.input.clear()
	var health_before := _hero.health
	_hero.input.return_pressed = true
	await _ticks(1)
	_check(_hero.world_position().distance_to(saved) < 0.1, "return restores the saved position")
	_check(_hero.velocity.is_zero_approx(), "return clears momentum")
	_check(_hero.health - health_before < 0.5, "return does not heal")
	_hero.input.return_pressed = true
	await _ticks(1)
	_check(recovery.message.contains("cooling"), "repeated return observes cooldown")
	await _ticks(10)
	_hero.input.checkpoint_pressed = true
	await _ticks(1)
	_check(recovery.cooldown > 14.0, "saving again cannot bypass return cooldown")
	saved = recovery.checkpoint
	_check(not recovery.safe_at(Vector3(39.9, 2, 0)), "unsupported footprint at an edge is refused")
	_check(not recovery.safe_at(Vector3(0, -3, 0)), "underwater ground is refused")
	_check(not recovery.safe_at(Vector3(0, 20, 0)), "airborne ground is refused")
	WorldOrigin.shift(Vector3(500, 0, 0))
	await _ticks(2)
	_check(recovery.checkpoint == saved, "origin shift leaves saved world coordinates intact")
	_check(recovery.safe_at(WorldOrigin.to_local(saved)), "saved ground remains valid after origin shift")
	_hero.input.attack_held = true
	_hero.input.return_pressed = true
	await _ticks(1)
	_check(recovery.message.contains("combat"), "attacking blocks return")
	_hero.input.clear()
	_hero.take_hit(1, Vector3.ZERO)
	_check(recovery.combat_delay == SafeReturn.COMBAT_DELAY, "taking damage resets combat lock")
	recovery.combat_delay = 0.0
	recovery.cooldown = 0.0
	_hero.set_mode(&"OnFoot")
	_hero.input.clear()
	var thug: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	thug.frozen = true
	thug.position = _hero.position + Vector3.RIGHT * 20
	add_child(thug)
	_hero.input.return_pressed = true
	await _ticks(1)
	_check(recovery.message.contains("combat"), "nearby living thug blocks return")
	thug.queue_free()
	await _ticks(2)
	recovery.combat_delay = 0.0
	_hero.global_position += Vector3.RIGHT * 300
	_hero.input.return_pressed = true
	await _ticks(1)
	_check(recovery.message.contains("250"), "distant return is refused")
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	blocker.position = WorldOrigin.to_local(saved) + Vector3.UP
	blocker.add_child(shape)
	add_child(blocker)
	await _ticks(2)
	_check(not recovery.safe_at(WorldOrigin.to_local(saved)), "occupied destination is refused")
	print("SAFE RETURN: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _ticks(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _check(ok: bool, description: String) -> void:
	print("%s: %s" % ["OK" if ok else "FAIL", description])
	if not ok:
		_failures += 1
