extends Node3D
## Synthetic rooftop physics checks; no city download needed.
## Run: godot --headless --path . res://tests/flight_airbrake_test.tscn

var _hero: Hero
var _failures := 0


func _ready() -> void:
	_hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(_hero)
	_hero.frozen = false
	_hero.position = Vector3(0.0, 150.0, 0.0)
	_hero.set_mode(&"Flight")
	_hero.input.aim = Vector3.FORWARD
	_hero.input.stick = Vector2(0.0, -1.0)
	_hero.input.sprint_held = true
	await _ticks(480)
	_check(_hero.velocity.length() > 185.0, "normal sustained boost is preserved")
	var start := _hero.position
	_hero.input.stick = Vector2.ZERO
	_hero.input.brake_held = true
	await _ticks(90)
	_check(_hero.velocity.length() < 0.01, "brake stops full boost despite held sprint")
	_check(_hero.position.distance_to(start) < 115.0, "full boost stops within 115 m")
	_hero.input.stick = Vector2(0.0, -1.0)
	_hero.input.aim = Vector3(0.0, -0.8, -0.6)
	_hero.input.vertical = -1.0
	await _ticks(60)
	_check(is_equal_approx(_hero.horizontal_speed(), 6.0) and is_equal_approx(_hero.velocity.y, -4.0), "brake gives level steering and 4 m/s descent")
	_hero.input.brake_held = false
	_hero.input.vertical = 0.0
	_hero.input.aim = Vector3.FORWARD
	await _ticks(120)
	_check(_hero.velocity.length() > 145.0, "releasing brake restores boost")
	_hero.input.clear()
	_check(not _hero.input.brake_held, "cleared input releases brake")
	# Test fixture places a broad roof under the normal collision body.
	var roof := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 2.0, 100.0)
	shape.shape = box
	roof.add_child(shape)
	add_child(roof)
	_hero.position = Vector3(0.0, 8.0, 0.0)
	_hero.velocity = Vector3.ZERO
	_hero.input.brake_held = true
	_hero.input.vertical = -1.0
	await _ticks(180)
	_check(_hero.mode.name == &"OnFoot" and _hero.is_on_floor(), "braked descent lands on roof and exits flight")
	_check(InputMap.action_get_events(&"air_brake").size() == 2, "keyboard and gamepad brake bindings exist")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	_check(Input.is_action_pressed(&"air_brake"), "physical Q activates brake")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()
	_check(Input.is_action_pressed(&"air_brake"), "left trigger activates brake")
	trigger = trigger.duplicate()
	trigger.axis_value = 0.0
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()
	_check(not Input.is_action_pressed(&"air_brake"), "released controls clear brake action")
	print("Flight air brake: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		_failures += 1
