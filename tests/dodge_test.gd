extends Node3D
## Synthetic physics arena; exercises the production Hero and PlayerSync.
## Run: godot --headless --path . res://tests/dodge_test.tscn
var hero: Hero
var failures := 0


func check(value: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if value else "FAIL", message])
	if not value:
		failures += 1


func ticks(count: int) -> void:
	for n in count:
		await get_tree().physics_frame


func _ready() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	add_child(ground)
	ground.add_to_group("floating")
	hero = preload("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	await ticks(10)
	check(hero.can_dodge(), "grounded hero can dodge")
	var start := hero.position
	hero.input.dodge_held = true
	await ticks(3)
	check(hero.mode.name == &"Dodge", "fresh press enters dodge")
	hero.take_hit(10.0, Vector3.ZERO)
	check(hero.health == 100.0, "early grounded dodge avoids hit")
	await ticks(10)
	check(not (hero.mode as DodgeMode).avoiding(), "avoidance ends before step ends")
	hero.take_hit(10.0, Vector3.ZERO)
	check(hero.health == 90.0, "recovery takes damage")
	await ticks(90)
	check(hero.mode.name == &"OnFoot", "held button never repeats after cooldown")
	check(hero.position.z > start.z + 0.5, "stationary dodge backsteps")
	hero.input.dodge_held = false
	await ticks(2)
	hero.input.move = Vector3.RIGHT
	hero.input.dodge_held = true
	await ticks(3)
	check(hero.mode.name == &"Dodge" and hero.velocity.x > 0.0, "fresh press dodges in movement direction")
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	check(hero.velocity.x > 0.0, "origin shift preserves dodge direction")
	var sync := PlayerSync.new()
	var state: Array = sync._encode(hero)
	check(PlayerSync.MODES[state[4]] == &"Dodge" and state.size() == 13, "network encodes appended dodge mode without changing packet shape")
	var copy: Hero = preload("res://scenes/hero/hero.tscn").instantiate()
	copy.remote_id = 42
	add_child(copy)
	var buffer := SnapshotBuffer.new()
	buffer.push(float(state[0]), state)
	sync._follow(copy, buffer)
	check(copy.mode.name == &"Dodge", "network copy displays dodge")
	copy.queue_free()
	sync.free()
	hero.input.dodge_held = false
	await ticks(25)
	hero.input.dodge_held = true
	await ticks(2)
	check(hero.mode.name != &"Dodge", "cooldown blocks a second press")
	hero.input.clear()
	await ticks(90)
	hero.input.attack_held = true
	await ticks(3)
	hero.input.dodge_held = true
	await ticks(2)
	check(hero.mode.name == &"Dodge", "dodge cancels melee")
	hero.input.fly_toggle_pressed = true
	hero.input.jump_held = true
	await ticks(3)
	check(hero.mode.name == &"Dodge", "jump and flight cannot cancel recovery")
	hero.input.clear()
	await ticks(100)
	hero.hurt_time = 0.2
	check(not hero.can_dodge(), "stagger prevents dodge")
	hero.hurt_time = 0.0
	hero.frozen = true
	check(not hero.can_dodge(), "frozen hero cannot dodge")
	hero.frozen = false
	# A solid wall must stop the step, even during avoidance.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.0, 5.0, 10.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = hero.position + Vector3(1.2, 2.0, 0.0)
	add_child(wall)
	hero.input.clear()
	await ticks(2)
	hero.input.move = Vector3.RIGHT
	hero.input.dodge_held = true
	await ticks(15)
	check(hero.position.x < wall.position.x - 0.7, "solid wall stops dodge")
	hero.input.clear()
	await ticks(80)
	hero.position.y = 5.0
	await ticks(2)
	check(not hero.can_dodge(), "airborne hero cannot dodge")
	hero.position.y = -2.0
	check(not hero.can_dodge(), "underwater hero cannot dodge")
	print("Dodge checks finished: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
