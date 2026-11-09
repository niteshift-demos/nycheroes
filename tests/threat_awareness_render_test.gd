extends Node
## Native renderer check of the actual overlay against world collision and origin shifts.
## godot --path . --resolution 1280x720 res://tests/threat_awareness_render_test.tscn -- --solo=1
## Uses a synthetic scene; the separate play reproduction exercises the full city.

class QuietHud extends GameHud:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		pass

var _failed := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This test needs a renderer; run without --headless")
		get_tree().quit(1)
		return
	var hero := load("res://scenes/hero/hero.tscn").instantiate() as Hero
	add_child(hero)
	hero.frozen = false
	hero.set_physics_process(false)
	var thug := load("res://scenes/npc/thug.tscn").instantiate() as Thug
	add_child(thug)
	thug.set_physics_process(false)
	thug.setup(hero, 0, 0.0)
	thug.state = Thug.State.CHASE
	thug.position = Vector3(0.0, 0.0, 8.0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.add_to_group("floating")
	camera.position = Vector3(0.0, 2.0, 4.0)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	camera.current = true
	var hud := QuietHud.new()
	hud.hero = hero
	add_child(hud)
	var overlay := ThreatAwareness.new()
	hud.add_child(overlay)
	await _frames()
	_check(overlay.shown_count == 1, "clear off-screen pursuer has an arrow")
	var wall := StaticBody3D.new()
	wall.collision_layer = Combat.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.position = Vector3(0.0, 1.5, 4.0)
	await _frames()
	_check(overlay.shown_count == 0, "world collision hides the pursuer")
	wall.queue_free()
	await _frames()
	_check(overlay.shown_count == 1, "removing cover restores the arrow")
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	await _frames()
	_check(overlay.shown_count == 1, "origin shift preserves the cue")
	if not _failed:
		print("Threat overlay renderer: 4 checks passed")
	get_tree().quit(1 if _failed else 0)


func _frames() -> void:
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed = true
		push_error(label)
	print("%s: %s" % ["ok" if ok else "FAILED", label])
