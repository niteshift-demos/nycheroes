class_name FlightCourse
extends Node3D
## A personal time trial over the Hudson. Only the local hero can score;
## its movement remains ordinary Hero state, already replicated by PlayerSync.
## Ring checks use swept world positions so boost and origin shifts cannot skip gates.

const START := Vector3(-2050.0, 110.0, 100.0)
const RADIUS := 22.0
const GOLD := 4.5
const SILVER := 8.0
const BRONZE := 17.0
const LIMIT := 60.0
const OFFSETS := [0.0, 0.0, 12.0, 26.0, 12.0, 0.0]
const CYAN := Color(0.15, 0.9, 1.0)
const AMBER := Color(1.0, 0.72, 0.15)

enum State { IDLE, ARMED, RUNNING, FINISHED }
var game: Game
var state := State.IDLE
var next_ring := 0
var elapsed := 0.0
var best := 0.0
var _previous := Vector3.ZERO
var _rings: Array[MeshInstance3D] = []
var _panel: PanelContainer
var _title: Label
var _detail: Label
var _button: Button
var _leave: Button
var _marker: Label
var _result := ""


func _ready() -> void:
	best = float(Settings.get_value("hudson_sprint_best", 0.0))
	add_to_group("floating")
	position = -WorldOrigin.offset
	var mesh := TorusMesh.new()
	mesh.inner_radius = RADIUS
	mesh.outer_radius = RADIUS + 0.8
	mesh.rings = 32
	mesh.ring_segments = 8
	for i in OFFSETS.size():
		var ring := MeshInstance3D.new()
		ring.mesh = mesh
		ring.position = ring_position(i)
		ring.rotation.x = PI * 0.5
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		add_child(ring)
		_rings.append(ring)
	_build_hud()
	_recolor()


static func ring_position(index: int) -> Vector3:
	return START + Vector3(OFFSETS[index], 0.0, -100.0 * index)


## Forward crossing of the opening, including a whole gate crossed in one tick.
static func crosses_gate(from: Vector3, to: Vector3, center: Vector3) -> bool:
	if from.z <= center.z or to.z > center.z:
		return false
	var along := (from.z - center.z) / (from.z - to.z)
	var at := from.lerp(to, along) - center
	return Vector2(at.x, at.y).length() <= RADIUS


static func medal(seconds: float) -> String:
	if seconds <= GOLD:
		return "GOLD"
	if seconds <= SILVER:
		return "SILVER"
	if seconds <= BRONZE:
		return "BRONZE"
	return "FINISHER"


## Start in a hover, facing the first ring. The clock starts at its plane.
func start() -> void:
	state = State.ARMED
	next_ring = 0
	elapsed = 0.0
	_result = ""
	game.place_hero(START + Vector3(0.0, 0.0, 45.0), 0.0)
	game.hero.frozen = false  # No terrain is needed for a course over open water.
	game.hero.set_mode(&"Flight")
	game.hero.input.clear()
	game.hero_camera.pitch = 0.0
	_previous = game.hero.world_position()
	_recolor()


func leave() -> void:
	state = State.IDLE
	_result = ""
	_recolor()


func _physics_process(delta: float) -> void:
	if state != State.ARMED and state != State.RUNNING:
		return
	var current := game.hero.world_position()
	if game.hero.frozen or current.distance_to(_previous) > 250.0 or game.hero.mode.name == &"KnockedOut":
		_finish("Run interrupted · retry when ready")
		return
	if state == State.RUNNING:
		elapsed += delta
	if game.hero.mode.name == &"Flight" and crosses_gate(_previous, current, ring_position(next_ring)):
		if state == State.ARMED:
			state = State.RUNNING
			elapsed = 0.0
		next_ring += 1
		if next_ring == OFFSETS.size():
			if best <= 0.0 or elapsed < best:
				best = elapsed
				Settings.set_value("hudson_sprint_best", best)
			_finish("%s  ·  %.2f s" % [medal(elapsed), elapsed])
		_recolor()
	elif elapsed >= LIMIT:
		_finish("Time limit · try again")
	_previous = current


func _finish(message: String) -> void:
	state = State.FINISHED
	_result = message
	_recolor()


func _recolor() -> void:
	for i in _rings.size():
		var material := _rings[i].material_override as StandardMaterial3D
		material.albedo_color = AMBER if i == next_ring else (Color(0.2, 0.65, 0.4) if i < next_ring else Color(0.22, 0.4, 0.52))
		_rings[i].visible = state == State.ARMED or state == State.RUNNING


func _process(_delta: float) -> void:
	var width := minf(420.0, get_viewport().get_visible_rect().size.x - 24.0)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	var controls := "Stick to fly / steer · SPEED boost · UP/DOWN height" if Device.wants_touch_controls() else "W fly · A/D steer · Shift boost · Space/C height"
	var active := state == State.ARMED or state == State.RUNNING
	# Menus and free camera retain exclusive keyboard and touch control.
	_panel.visible = game.player_input.enabled and not is_instance_valid(game._loading) and not LaunchOptions.has("demo")
	_marker.visible = _panel.visible and active
	_title.text = "HUDSON SPRINT  /  FLIGHT TRIAL"
	if state == State.IDLE:
		_detail.text = "6 rings over the river · beat your best\nGold ≤4.5s  /  Silver ≤8s  /  Bronze ≤17s"
	elif state == State.FINISHED:
		_title.text = _result
		_detail.text = "Best %.2fs · Gold ≤4.5s / Silver ≤8s / Bronze ≤17s" % best if best > 0.0 else "Gold ≤4.5s / Silver ≤8s / Bronze ≤17s"
	else:
		_title.text = "RING %d / 6   ·   %s" % [next_ring + 1, "READY" if state == State.ARMED else "%.2f s" % elapsed]
		var missed := game.hero.world_position().z < ring_position(next_ring).z
		_detail.text = "Missed ring! Turn back, or retry." if missed else (controls + "\nClock starts at ring 1 · Gold ≤4.5s / Silver ≤8s" if state == State.ARMED else controls)
	_button.text = "Start flight trial" if state == State.IDLE else "Retry"
	if not Device.wants_touch_controls():
		_button.text += " · R"
	_leave.visible = state != State.IDLE
	if active:
		var camera := get_viewport().get_camera_3d()
		var target := WorldOrigin.to_local(ring_position(next_ring))
		var point := camera.unproject_position(target)
		var screen := get_viewport().get_visible_rect().size
		if camera.is_position_behind(target):
			point = Vector2(screen.x * 0.5, 100.0)
		_marker.position = point.clamp(Vector2(80.0, 100.0), screen - Vector2(180.0, 220.0))
		_marker.text = "NEXT %d  ·  %dm" % [next_ring + 1, game.hero.global_position.distance_to(target)]


func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud.add_child(root)
	game.hud.move_child(root, 0)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -210.0
	_panel.offset_right = 210.0
	_panel.offset_top = -186.0
	_panel.offset_bottom = -66.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.055, 0.09, 0.94)
	box.border_color = CYAN.darkened(0.4)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", box)
	root.add_child(_panel)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	_title = Label.new()
	_title.add_theme_color_override("font_color", CYAN)
	_title.add_theme_font_size_override("font_size", 17)
	rows.add_child(_title)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 280.0
	_detail.add_theme_font_size_override("font_size", 13)
	rows.add_child(_detail)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(180.0, 44.0)
	_button.focus_mode = Control.FOCUS_NONE
	_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_button.pressed.connect(start)
	buttons.add_child(_button)
	_leave = Button.new()
	_leave.text = "Leave trial"
	_leave.custom_minimum_size.y = 44.0
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_leave.pressed.connect(leave)
	buttons.add_child(_leave)
	_marker = Label.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.add_theme_color_override("font_color", AMBER)
	_marker.add_theme_color_override("font_outline_color", Color.BLACK)
	_marker.add_theme_constant_override("outline_size", 6)
	_marker.add_theme_font_size_override("font_size", 20)
	root.add_child(_marker)
	game._options.toggled.connect(_menu_changed)
	game.coop_panel.toggled.connect(_menu_changed)
	game._name_prompt.toggled.connect(_menu_changed)


func _menu_changed(open: bool) -> void:
	if open:
		_panel.hide()
		_marker.hide()
