class_name RooftopTrial
extends Node3D
## A small optional rooftop circuit on an existing Times Square roof. The
## course is local to this player; it changes no hero or network movement state.

const BEST_KEY := "rooftop_trial_v1_best"
var game: Game
var state := RooftopTrialState.new()
var _label: Label
var _gates: Array[MeshInstance3D] = []
var _ready_course := false
var _best := 0.0
var _display_gate := -1


func _ready() -> void:
	add_to_group("floating")
	position = -WorldOrigin.offset
	_best = float(Settings.get_value(BEST_KEY, 0.0))
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 100)
	panel.size.x = minf(540.0, get_viewport().get_visible_rect().size.x - 40.0)
	get_viewport().size_changed.connect(func() -> void:
		panel.size.x = minf(540.0, get_viewport().get_visible_rect().size.x - 40.0))
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_label)
	var restart := Button.new()
	restart.text = "Restart rooftop trial [R]"
	restart.pressed.connect(restart_run)
	column.add_child(restart)
	for i in RooftopTrialState.GATES.size() - 1:
		var marker := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 1.5
		mesh.outer_radius = 1.8
		marker.mesh = mesh
		marker.position = RooftopTrialState.GATES[i] + Vector3.UP * 0.12
		add_child(marker)
		_gates.append(marker)
		var number := Label3D.new()
		number.text = "START / FINISH" if i == 0 else str(i)
		number.position = marker.position + Vector3.UP * 2.5
		number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		number.font_size = 80
		number.pixel_size = 0.008
		add_child(number)
	game.city.initial_load_finished.connect(_validate_roof, CONNECT_ONE_SHOT)
	_update_display()


func _validate_roof(_seconds: float) -> void:
	# Refuse the course if a later city rebuild changes this roof. Sample the
	# entire running rectangle, not just its checkpoint centers.
	await get_tree().physics_frame
	_ready_course = true
	for x in range(10, 31, 2):
		for z in range(50, 79, 2):
			var height := game.city.ground_height_at(Vector3(x, 0, z))
			if is_nan(height) or absf(height - 32.724) > 0.25:
				_ready_course = false
	if not _ready_course:
		state.message = "Course unavailable: roof data changed or has not loaded"
	print("[rooftop] roof validated: ", _ready_course)
	_update_display()


func restart_run() -> void:
	if not _ready_course:
		return
	state.reset()
	game.place_hero(RooftopTrialState.GATES[0] + Vector3(0, 0.05, 3), 0.0)
	_update_display()
	print("[rooftop] restart")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		if game.player_input.enabled:
			restart_run()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not _ready_course or game.hero.frozen:
		return
	var previous := state.next_gate
	var was_finished := state.finished
	state.step(delta, game.hero.world_position(), game.hero.mode.name)
	if previous != state.next_gate:
		print("[rooftop] gate ", state.next_gate, " time ", state.elapsed)
	if state.finished and not was_finished:
		print("[rooftop] ", state.message, " time ", state.elapsed)
		if state.next_gate == RooftopTrialState.GATES.size() and (_best <= 0.0 or state.elapsed < _best):
			_best = state.elapsed
			Settings.set_value(BEST_KEY, _best)
	_update_display()


func _update_display() -> void:
	_label.text = "  ROOFTOP CIRCUIT · Times Square  \n  %05.2f s    Best: %s  \n  %s  \n  WASD / stick · Jump · R restart  \n  Ordered gates · No flight or webs  " % [state.elapsed, "—" if _best <= 0.0 else "%.2f s" % _best, state.message]
	if _display_gate == state.next_gate:
		return
	_display_gate = state.next_gate
	for i in _gates.size():
		var material := StandardMaterial3D.new()
		var target := state.next_gate % _gates.size()
		material.albedo_color = Color(0.2, 1, 0.45) if i == 0 else Color(1, 0.7, 0.08)
		if i != target:
			material.albedo_color = Color(0.3, 0.4, 0.5)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_gates[i].material_override = material
