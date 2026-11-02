extends Node3D
## Synthetic arena: charge/release payoff, cancellation, recovery, interruption,
## world shifts and the co-op payload, without city downloads.
## Run: godot --headless --path . res://tests/heavy_attack_test.tscn

var hero: Hero
var failures := 0

func _ready() -> void:
	check(InputMap.action_get_events("heavy_attack").any(
		func(event: InputEvent) -> bool: return event is InputEventKey and event.physical_keycode == KEY_G), "G is bound to heavy")
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	add_child(ground)
	ground.add_to_group("floating")
	hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	hero.position = Vector3(0.0, 0.05, 0.0)
	await ticks(5)
	var melee := hero.get_mode(&"Melee") as MeleeMode
	hero.velocity.x = 60.0
	hero.input.heavy_held = true
	await ticks(6)
	check(hero.horizontal_speed() <= 1.81, "charging caps movement even from super speed")
	check(melee.heavy_charging, "hold begins charge")
	hero.input.heavy_held = false
	await ticks(3)
	check(hero.mode.name == &"OnFoot", "early release cancels")
	var targets: Array[Thug] = []
	for x in [-0.8, 0.8]:
		var thug: Thug = load("res://scenes/npc/thug.tscn").instantiate()
		add_child(thug)
		thug.position = Vector3(x, 0.0, -2.0)
		thug.set_physics_process(false)
		targets.append(thug)
	hero.input.heavy_held = true
	await ticks(60)
	check(melee.heavy_charge >= 0.99, "charge caps at full power")
	var before := hero.world_position()
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	check(hero.world_position().distance_to(before) < 0.01, "world shift preserves charging hero")
	var sync := PlayerSync.new()
	var state := sync._encode(hero)
	check(state.size() == 16 and state[13] and state[14] and state[15] >= 0.99, "co-op sends charge and heavy pose")
	var copy: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	copy.remote_id = 2
	add_child(copy)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(float(state[0]), state)
	sync._follow(copy, snapshots)
	var copy_melee := copy.get_mode(&"Melee") as MeleeMode
	check(copy.mode == copy_melee and copy_melee.heavy_charging and copy_melee.heavy_charge >= 0.99,
		"remote hero follows the heavy pose and charge")
	copy.queue_free()
	sync.free()
	hero.input.heavy_held = false
	await ticks(1)
	hero.input.attack_held = true
	await ticks(20)
	check(targets[0].is_down() and targets[1].is_down(), "full release launches multiple thugs")
	check(hero.mode == melee and melee.heavy_recovery > 0.0, "light attack cannot skip recovery")
	hero.input.clear()
	await ticks(55)
	var partial: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	add_child(partial)
	partial.global_position = hero.global_position + Vector3(0.0, 0.0, -2.0)
	partial.set_physics_process(false)
	hero.input.heavy_held = true
	await ticks(25)
	hero.input.heavy_held = false
	await ticks(20)
	check(partial.health > 0.0 and partial.health < 100.0 and not partial.is_down(), "partial release deals damage without full launch")
	await ticks(50)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4.0, 4.0, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.global_position = hero.global_position + Vector3(0.0, 1.0, -1.0)
	await ticks(2)
	var health_before := partial.health
	Combat.strike(hero.global_position + Vector3(0.0, 1.1, -1.8), 3.0, 100.0, Vector3.ZERO, true, Vector3.FORWARD)
	check(partial.health == health_before, "heavy blow cannot hit through world walls")
	wall.queue_free()
	partial.queue_free()
	hero.input.heavy_held = true
	await ticks(30)
	hero.take_hit(10.0, Vector3.ZERO)
	await ticks(2)
	check(hero.mode.name == &"OnFoot" and not melee.heavy_charging, "incoming hit interrupts charge")
	await ticks(30)
	check(hero.mode.name == &"OnFoot", "holding after interruption does not auto restart")
	hero.input.clear()
	await ticks(2)
	hero.input.heavy_held = true
	await ticks(30)
	hero.input.jump_held = true
	await ticks(2)
	check(hero.mode.name == &"OnFoot", "jump cancels windup")
	print("Heavy attack: %d failure(s)" % failures)
	get_tree().quit(1 if failures else 0)

func ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
