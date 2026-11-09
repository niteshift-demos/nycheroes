class_name PatrolHud
extends Control
## A small, input-accessible personal patrol card, independent of combat HUD.

signal notice(text: String)

var hero: Hero
var encounters: EncounterDirector
var patrol := NeighborhoodPatrol.new()
var _patrol_button: Button
var _patrol_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_patrol()


func _process(_delta: float) -> void:
	_update_patrol()


func _add_patrol() -> void:
	var panel := PanelContainer.new()
	panel.name = "NeighborhoodPatrol"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -160.0
	panel.offset_right = 160.0
	panel.offset_top = -184.0
	panel.offset_bottom = -64.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.045, 0.08, 0.88)
	box.set_corner_radius_all(8)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_patrol_label = Label.new()
	_patrol_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_patrol_label)
	_patrol_button = Button.new()
	_patrol_button.focus_mode = Control.FOCUS_NONE
	_patrol_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_patrol_button.pressed.connect(_start_patrol)
	column.add_child(_patrol_button)
	encounters.encounter_started.connect(patrol.encounter_started)
	encounters.encounter_removed.connect(patrol.encounter_removed)
	encounters.encounter_cleared.connect(func(id: int) -> void:
		var before := patrol.cleared
		patrol.encounter_cleared(id, hero.world_position())
		if patrol.cleared > before:
			notice.emit("Patrol complete! Replay when ready." if patrol.completed else "Patrol: gang cleared — %d / %d" % [patrol.cleared, NeighborhoodPatrol.TARGET]))
	_update_patrol()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		_start_patrol()
		get_viewport().set_input_as_handled()


func _start_patrol() -> void:
	if hero.frozen or patrol.active:
		return
	patrol.start(hero.world_position())
	var candidates := encounters.patrol_candidates()
	for id: int in candidates:
		patrol.encounter_started(id, candidates[id])
	notice.emit("Patrol started: clear 2 full gangs within 300 m")


func _update_patrol() -> void:
	if not _patrol_label:
		return
	var status := "NEIGHBORHOOD PATROL"
	if patrol.active:
		var distance := patrol.distance_from(hero.world_position())
		status += "  %d / %d\n%s · %d m from start" % [patrol.cleared, NeighborhoodPatrol.TARGET,
			"Return within 300 m" if distance > NeighborhoodPatrol.RADIUS else "Inside 300 m area", int(distance)]
	elif patrol.completed:
		status += "  2 / 2 · COMPLETE!\nReplay starts a fresh area here."
	else:
		status += "\nClear 2 full gangs within 300 m of start."
	_patrol_label.text = status + "\nLocal gangs only · full clears · no timer"
	_patrol_button.text = "Patrolling — follow THUGS markers" if patrol.active else ("Replay patrol · P" if patrol.completed else "Start patrol · P")
	_patrol_button.disabled = patrol.active or hero.frozen
