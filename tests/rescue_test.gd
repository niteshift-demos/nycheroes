extends Node3D
## Synthetic ground; no city downloads. Tests actual input-to-rescue advancement,
## pause, movement/altitude/KO limits, helper expiry, scoring and origin shifts.
## godot --headless --path . res://tests/rescue_test.tscn

var failures := 0

func check(ok: bool, message: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _ready() -> void:
	var hero: Hero = preload("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.set_physics_process(false)
	hero.frozen = false
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100, 1, 100)
	collision.shape = floor_shape
	ground.add_child(collision)
	ground.position.y = -0.5
	add_child(ground)
	await get_tree().physics_frame
	hero.velocity = Vector3.DOWN
	hero.move_and_slide()
	hero.velocity = Vector3.ZERO
	var input := PlayerInput.new()
	input.set_physics_process(false)
	var rescue := RescueDirector.new()
	rescue.hero = hero
	rescue.player_input = input
	rescue.city = CityStreamer.new()
	add_child(rescue)
	rescue.set_process(false)
	var binding := InputMap.action_get_events("rescue")[0] as InputEventKey
	check(binding.physical_keycode == KEY_V, "Rescue uses V without consuming course retry R")
	rescue.calls[Net.local_id()] = [1, Vector3.ZERO, 0, 0.0, false]
	Input.action_press("rescue")
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "holding rescue lifts debris")
	Input.action_release("rescue")
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "release keeps progress without advancing")
	Input.action_press("rescue")
	hero.position.y = 1.0
	hero.velocity = Vector3.ZERO
	hero.move_and_slide()
	check(not RescueDirector.can_help(hero, Vector3.ZERO), "jumping within reach cannot rescue")
	hero.position.y = 0.0
	hero.velocity = Vector3.DOWN
	hero.move_and_slide()
	hero.velocity = Vector3.ZERO
	hero.position.x = 6.0
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "out of reach cannot rescue")
	hero.position = Vector3(0, 6, 0)
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "flying over civilian cannot rescue")
	hero.position = Vector3.ZERO
	hero.velocity = Vector3(5, 0, 0)
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "running through does not rescue")
	hero.velocity = Vector3.ZERO
	hero.health = 0.0
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "knocked out cannot rescue")
	hero.health = Hero.MAX_HEALTH
	input.enabled = false
	rescue._process(1.0)
	check(is_equal_approx(rescue.calls[1][3], 1.0), "menus cannot rescue")
	input.enabled = true
	WorldOrigin.shift(Vector3(2000, 0, 500))
	rescue._process(0.5)
	check(is_equal_approx(rescue.calls[1][3], 1.5), "reach survives floating origin shift")
	check((rescue._visuals[1] as Node3D).position.is_equal_approx(WorldOrigin.to_local(Vector3.ZERO)), "visual remains at world spot after shift")
	Input.action_release("rescue")
	var helper: Hero = preload("res://scenes/hero/hero.tscn").instantiate()
	helper.remote_id = 2
	add_child(helper)
	helper.set_physics_process(false)
	helper.global_position = hero.global_position
	helper.frozen = false
	helper.remote_grounded = true
	helper.set_mode(&"OnFoot")
	rescue._helpers[2] = [1, Time.get_ticks_msec() - 1]
	rescue._process(0.5)
	check(is_equal_approx(rescue.calls[1][3], 1.5), "expired co-op intent cannot rescue")
	rescue._helpers[2] = [99, Time.get_ticks_msec() + 500]
	rescue._process(0.5)
	check(is_equal_approx(rescue.calls[1][3], 1.5), "old encounter intent cannot rescue new civilian")
	rescue._helpers[2] = [1, Time.get_ticks_msec() + 500]
	rescue._process(0.5)
	check(is_equal_approx(rescue.calls[1][3], 2.0), "nearby co-op helper advances owner progress")
	rescue._helpers.clear()
	Input.action_press("rescue")
	rescue._process(2.0)
	check(rescue.calls[1][4] and rescue.saved_count == 1, "completion saves civilian and awards one rescue")
	rescue._process(1.0)
	check(rescue.saved_count == 1, "continuing to hold cannot score twice")
	check(not rescue._visuals[1].get_node("Debris").visible, "completion clears debris")
	Input.action_release("rescue")
	rescue.city.free()
	input.free()
	print("Rescue checks: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
