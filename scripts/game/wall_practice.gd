class_name WallPractice
extends Node3D
## Optional rooftop training wall: a repeatable, tile-independent place to
## learn the real movement controls, with a scripted-input demo for recording.

const START := Vector3(420.95, 150.05, -210.0)
var game: Game
var _demo_time := -1.0
var _episode := -1
var _last_state := ""
var _label: Label


func _ready() -> void:
	# Keep this optional training view inexpensive on phones and software WebGL.
	# Streaming still loads collision and the normal game is unaffected.
	game.city.visible = false
	(game.hud.get_node("DebugLabel") as Label).visible = LaunchOptions.has("stats")
	game.encounters.max_gangs = 0
	add_to_group("floating")
	position = WorldOrigin.to_local(Vector3(420.0, 150.0, -220.0))
	_box(Vector3(-9.0, -0.5, -12.0), Vector3(24.0, 1.0, 64.0), Color(0.12, 0.18, 0.24))
	_box(Vector3(2.5, 6.0, -12.0), Vector3(1.0, 12.0, 64.0), Color(0.3, 0.39, 0.48))
	for z in range(-40, 20, 4):
		_box(Vector3(1.0, 0.015, z), Vector3(1.5, 0.02, 0.12), Color(0.2, 0.85, 0.95))
	var panel := VBoxContainer.new()
	panel.position = Vector2(24.0, 75.0)
	game.hud.add_child(panel)
	_label = Label.new()
	_label.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 48.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.y = 78.0
	_label.text = "ROOFTOP PRACTICE\nSprint + jump along the wall. Jump again to kick.\nOne short run and kick per airtime; land to recharge."
	panel.add_child(_label)
	var reset := Button.new()
	reset.text = "Reset run"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		_demo_time = -1.0
		game.player_input.enabled = true
		_reset())
	panel.add_child(reset)
	var demo := Button.new()
	demo.text = "Play traversal demo"
	demo.focus_mode = Control.FOCUS_NONE
	demo.pressed.connect(func() -> void:
		_demo_time = 0.0
		_episode = -1
		game.player_input.enabled = false)
	panel.add_child(demo)
	process_physics_priority = -5  # after PlayerInput, before Hero
	_reset()


func _box(at: Vector3, dimensions: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)


func _reset() -> void:
	game.hero.set_mode(&"OnFoot")
	game.hero.global_position = WorldOrigin.to_local(START)
	game.hero.velocity = Vector3.ZERO
	game.hero.facing = 0.0
	game.hero.frozen = false
	game.hero.input.clear()
	game.hero_camera.yaw = -0.28
	game.hero_camera.pitch = -0.12


func _physics_process(delta: float) -> void:
	if _demo_time < 0.0:
		if game.hero.global_position.y < 140.0:
			_reset()
		_report_state("manual")
		return
	_demo_time += delta
	var episode := int(_demo_time / 4.5)
	if episode >= 3:
		_demo_time = -1.0
		game.player_input.enabled = true
		_label.text = "YOUR TURN · Reset run, then sprint + jump along the wall."
		print("[wall practice] demo finished")
		return
	if episode != _episode:
		_episode = episode
		_reset()
		_label.text = ["WALL RUN + KICK · a fresh jump press launches away",
			"LIMIT · 1.1 seconds per airtime, then gravity takes over",
			"RELEASE · let go of sprint to leave the wall"][episode]
	var t := fmod(_demo_time, 4.5)
	var input := game.hero.input
	input.clear()
	if t > 0.5 and t < 2.4:
		input.move = Vector3(0.18, 0.0, -1.0).normalized()
		input.stick = Vector2(0.18, -1.0)
		input.sprint_held = episode != 2 or t < 1.15
		input.jump_held = t < 0.6 or (episode == 0 and t > 1.6 and t < 1.75)
	_report_state("episode %d t=%.2f" % [episode, t])


func _report_state(context: String) -> void:
	var state := "wall run" if game.hero.wall_running else ("ground" if game.hero.is_on_floor() else "air")
	if state != _last_state:
		_last_state = state
		print("[wall practice] %s %s velocity=%s" % [context, state, game.hero.velocity])
