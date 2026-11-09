extends Node3D
## Synthetic collision checks for forgiving web aim and honest range feedback.
## Run: godot --headless --path . res://tests/swing_assist_test.tscn

var _failures := 0


func _ready() -> void:
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.global_position = Vector3(0, 1, 0)
	hero.input.aim = Vector3.FORWARD
	var swing := hero.get_mode(&"Swing") as SwingMode
	await get_tree().physics_frame
	_check(swing.find_anchor().is_empty(), "empty air never supplies an anchor")
	_box(Vector3(0, -1, 0), Vector3(400, 2, 400))
	var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(12.5)) * cos(deg_to_rad(47.5)) + Vector3.UP * sin(deg_to_rad(47.5))
	var wall := _box(hero.global_position + Vector3.UP * SwingMode.HAND_HEIGHT + direction * 50.0, Vector3(1, 6, 1))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var found := swing.find_anchor()
	_check(not found.is_empty(), "a narrow real surface between the old rays is found")
	_check(swing.try_attach(), "the preview's real wall can be attached")
	_check(swing.web_point.distance_to(wall.position) < 4.0, "the visible web ends at the collision surface")
	_check(swing.rope_length >= SwingMode.MIN_ROPE, "the physical rope still clears the ground")
	wall.position *= 5.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not swing.try_attach(), "a wall beyond 120 m cannot attach")
	_check(swing.preview.is_empty(), "a failed attachment clears stale feedback")
	wall.position = Vector3(0, 3, -25)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(swing.find_anchor().is_empty(), "a wall below minimum anchor height cannot attach")
	swing.preview = {point = Vector3.ONE}
	swing.anchor = Vector3(10, 30, 40)
	swing.web_point = Vector3(15, 30, 40)
	WorldOrigin.shifted.emit(Vector3(10, 0, 0))
	_check(swing.preview.is_empty() and swing.anchor == Vector3(0, 30, 40) and swing.web_point == Vector3(5, 30, 40), "origin shifts move attachments and invalidate previews")
	print("Swing assist: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body


func _check(condition: bool, message: String) -> void:
	print("%s: %s" % ["OK" if condition else "FAIL", message])
	if not condition:
		_failures += 1
