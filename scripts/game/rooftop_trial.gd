class_name RooftopTrial
extends Node3D
## A deterministic rooftop practice course. Only the local stopwatch is private;
## hero motion and teleporting use the ordinary state already sent by PlayerSync.
## World-space gates and one floating parent keep retries valid after origin shifts.

## Over the Hudson (the movement tests use x=-2200 as open water), clear
## of city buildings and streets. This is an optional practice course.
const START := Vector3(-2200.0, 80.0, 0.0)
const HEIGHTS := [0.0, 2.0, 0.0, 4.0, 2.0, 0.0]
const LIMIT := 90.0
const GOLD := 5.0
const SILVER := 12.0
const BRONZE := 25.0
const CYAN := Color(0.12, 0.95, 0.86)
const GOLD_COLOR := Color(1.0, 0.74, 0.24)
const BEST_KEY := "rooftop_trial_v1_best"

enum Phase { READY, COUNTDOWN, RUNNING, FINISHED, FAILED }
var game: Game
var phase := Phase.READY
var next_gate := 0
var elapsed := 0.0
var best := 0.0
var _started := 0
var _countdown := 0.0
var _previous := Vector3.ZERO
var _return_position := Vector3.ZERO
var _return_facing := 0.0
var _gates: Array[MeshInstance3D] = []
var _course: Node3D
var _panel: PanelContainer
var _stats: Control
var _title: Label
var _status: Label
var _detail: Label
var _start_button: Button
var _exit_button: Button
var _message := ""
var _auto_start := false
var _hud_touch := -1


func _ready() -> void:
	# Keep the HUD hidden when an options menu pauses the world.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("floating")
	add_to_group("touch_hud")
	global_position = WorldOrigin.to_local(START)
	best = float(Settings.get_value(BEST_KEY, 0.0))
	_build_hud()
	_stats = game.hud.get_node_or_null("DebugLabel") as Control
	var game_hud := game.hud.get_node_or_null("GameHud") as GameHud
	if game_hud:
		game_hud.draw.connect(func() -> void:
			if phase == Phase.RUNNING and game.player_input.enabled:
				game_hud._draw_marker(WorldOrigin.to_local(gate_world(next_gate)),
					"GATE %d / 6" % (next_gate + 1), CYAN, 0.0))
	_auto_start = LaunchOptions.has("trial")


static func gate_world(index: int) -> Vector3:
	return START + Vector3(0.0, float(HEIGHTS[index]) + 4.0, -30.0 * index)


## Segment testing prevents a fast flight tick from tunneling through a gate.
static func crosses_gate(from: Vector3, to: Vector3, index: int) -> bool:
	var box := AABB(gate_world(index) - Vector3(6.0, 4.0, 1.5), Vector3(12.0, 10.0, 3.0))
	return box.has_point(to) or box.intersects_segment(from, to) != null


static func medal(seconds: float) -> String:
	if seconds <= GOLD:
		return "GOLD"
	if seconds <= SILVER:
		return "SILVER"
	if seconds <= BRONZE:
		return "BRONZE"
	return "FINISHER"


func start() -> void:
	if not game.player_input.enabled:
		return
	if phase == Phase.READY:
		_return_position = game.hero.world_position()
		_return_facing = game.hero.facing
	if not is_instance_valid(_course):
		_build_course()
	game.place_hero(START + Vector3(0.0, 0.1, 8.0), 0.0)
	# Course collision is ours: it doesn't depend on streamed tiles.
	game.hero.frozen = true
	game.hero.input.clear()
	game.hero_camera.pitch = 0.0
	phase = Phase.COUNTDOWN
	_countdown = 3.0
	next_gate = 0
	elapsed = 0.0
	_message = ""
	_refresh_gates()


func leave() -> void:
	game.place_hero(_return_position, _return_facing)
	phase = Phase.READY
	# Detach immediately: no render instances or physics bodies remain in
	# the world, including during the frame before queued deletion.
	if is_instance_valid(_course):
		remove_child(_course)
		_course.queue_free()
		_course = null
	_gates.clear()


## TouchControls calls this before assigning a finger to movement or look.
func handle_hud_touch(event: InputEvent) -> bool:
	if event is InputEventScreenDrag:
		return event.index == _hud_touch
	if not event is InputEventScreenTouch:
		return false
	if not event.pressed and event.index == _hud_touch:
		_hud_touch = -1
		return true
	if not event.pressed or _hud_touch != -1 or not _panel.visible or not game.player_input.enabled:
		return false
	for button: Button in [_start_button, _exit_button]:
		if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
			_hud_touch = event.index
			button.pressed.emit()
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not game.player_input.enabled or is_instance_valid(game._loading):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J:
			start()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if phase == Phase.COUNTDOWN:
		# Game's tile-ready logic may unfreeze the hero, so hold our own start.
		game.hero.frozen = true
		_countdown -= delta
		if _countdown <= 0.0:
			game.hero.frozen = false
			_previous = game.hero.world_position()
			_started = Time.get_ticks_msec()
			phase = Phase.RUNNING
	elif phase == Phase.RUNNING:
		elapsed = float(Time.get_ticks_msec() - _started) / 1000.0
		var current := game.hero.world_position()
		while next_gate < HEIGHTS.size() and crosses_gate(_previous, current, next_gate):
			next_gate += 1
			_refresh_gates()
		if next_gate == HEIGHTS.size():
			phase = Phase.FINISHED
			var old_best := best
			if best <= 0.0 or elapsed < best:
				best = elapsed
				Settings.set_value(BEST_KEY, best)
				_message = "FIRST FINISH!" if old_best <= 0.0 else "NEW BEST · %.2fs faster" % (old_best - best)
			else:
				_message = "%.2fs off your best" % (elapsed - best)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif elapsed >= LIMIT or current.y < START.y - 18.0 or current.distance_to(START) > 400.0 \
				or game.hero.mode.name == &"KnockedOut":
			phase = Phase.FAILED
			_message = "Time limit reached" if elapsed >= LIMIT else "Off the rooftops — try another line"
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_previous = current


func _process(_delta: float) -> void:
	# Menus stay above the trial and can't accidentally trigger its buttons.
	_panel.visible = game.player_input.enabled and not is_instance_valid(game._loading)
	if _auto_start and _panel.visible:
		_auto_start = false
		start()
	_panel.offset_top = 112.0 if _stats and _stats.visible else 62.0
	var width := minf(380.0, game.get_viewport().get_visible_rect().size.x - 24.0)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	var active := phase != Phase.READY
	_start_button.text = "RETRY  ·  J" if active else "ROOFTOP TRIAL  ·  J"
	_exit_button.visible = active
	_title.visible = active
	_status.visible = active
	_detail.visible = active
	if not active:
		return
	_title.text = "SKYLINE SPRINT  /  HUDSON PRACTICE"
	match phase:
		Phase.COUNTDOWN:
			_status.text = "READY IN %d" % maxi(1, ceili(_countdown))
			_detail.text = "Follow mint gates in order. All powers welcome.\n" + ("Move, jump, fly and boost with touch controls" if game._touch_controls else "WASD move · Space jump · F fly · Shift boost")
		Phase.RUNNING:
			_status.text = "%05.2f s   /   GATE %d OF 6" % [elapsed, next_gate + 1]
			var distance := game.hero.world_position().distance_to(gate_world(next_gate))
			_detail.text = "NEXT %d m · follow the mint arrow\nGold ≤5s · Silver ≤12s · Bronze ≤25s" % distance
		Phase.FINISHED:
			_status.text = "%s  /  %.2f s" % [medal(elapsed), elapsed]
			_detail.text = "%s\nBest %.2fs · Gold ≤5s · Silver ≤12s · Bronze ≤25s" % [_message, best]
		Phase.FAILED:
			_status.text = "RUN ENDED  /  %.2f s" % elapsed
			_detail.text = "%s\n%d / 6 gates · Retry for a fresh countdown" % [_message, next_gate]
	_status.modulate = GOLD_COLOR if phase == Phase.FINISHED else CYAN


func _build_hud() -> void:
	_panel = PanelContainer.new()
	_panel.name = "RooftopTrialPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -190.0
	_panel.offset_right = 190.0
	_panel.offset_top = 62.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.09, 0.94)
	style.border_color = CYAN
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	game.hud.add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_title = _label(column, 14)
	_status = _label(column, 25)
	_detail = _label(column, 13)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_start_button = _button(buttons, start)
	_exit_button = _button(buttons, leave)
	_exit_button.text = "LEAVE"


func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = 44.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(func() -> void:
		# GUI handling alone does not clear PlayerInput's raw LMB action.
		# Consume it for the entire held click, including after leaving.
		Input.action_release("attack")
		callback.call())
	parent.add_child(button)
	return button


func _material(color: Color, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _box(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


func _build_course() -> void:
	_course = Node3D.new()
	_course.name = "PracticeCourse"
	add_child(_course)
	var roof := _material(Color(0.12, 0.18, 0.24))
	var edge := _material(Color(0.32, 0.42, 0.5))
	var stripe := _material(CYAN, true)
	for i in HEIGHTS.size():
		var at := Vector3(0.0, float(HEIGHTS[i]), -30.0 * i)
		# Six slender towers give the route actual roofs, with 6m jump gaps.
		var tower_height := START.y + float(HEIGHTS[i])
		_box(_course, at - Vector3(0.0, (tower_height + 1.2) * 0.5, 0.0), Vector3(22.0, tower_height - 1.2, 24.0), roof)
		_box(_course, at - Vector3(0.0, 0.6, 0.0), Vector3(23.0, 1.2, 24.0), edge)
		var body := StaticBody3D.new()
		body.position = at - Vector3(0.0, tower_height * 0.5, 0.0)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(23.0, tower_height, 24.0)
		collision.shape = shape
		body.add_child(collision)
		_course.add_child(body)
		for side: float in [-1.0, 1.0]:
			_box(_course, at + Vector3(side * 11.0, 0.5, 0.0), Vector3(0.3, 1.0, 24.0), edge)
			_box(_course, at + Vector3(side * 9.0, 0.7, 5.0), Vector3(2.0, 1.4, 3.0), roof)
			for z: float in [7.0, 2.0, -3.0, -8.0]:
				var arrow := _box(_course, at + Vector3(side * 0.65, 0.03, z), Vector3(0.25, 0.04, 2.0), stripe)
				arrow.rotation.y = side * 0.65
		var gate := MeshInstance3D.new()
		gate.position = at
		_course.add_child(gate)
		_gates.append(gate)
		for side: float in [-1.0, 1.0]:
			_box(gate, Vector3(side * 6.0, 4.5, 0.0), Vector3(0.35, 9.0, 0.35), stripe)
		_box(gate, Vector3(0.0, 9.0, 0.0), Vector3(12.35, 0.35, 0.35), stripe)
		var sign := Label3D.new()
		sign.text = "%02d  /  %s" % [i + 1, "FINISH" if i == 5 else "SKYLINE"]
		sign.position = Vector3(0.0, 10.0, 0.0)
		sign.font_size = 64
		sign.pixel_size = 0.015
		gate.add_child(sign)
	_refresh_gates()


func _refresh_gates() -> void:
	for i in _gates.size():
		var color := CYAN if i == next_gate else Color(0.28, 0.4, 0.5)
		if i < next_gate:
			color = GOLD_COLOR
		var material := _material(color, true)
		for child in _gates[i].get_children():
			if child is MeshInstance3D:
				child.material_override = material
