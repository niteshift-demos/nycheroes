class_name Onboarding
extends Control
## First-run title and once-only, contextual lessons. Settings mirrors saves
## into browser storage immediately; reset never erases cash or lifetime stats.

signal dismissed

const LESSONS: Array[String] = ["move", "jump", "fly", "web", "punch", "car", "map", "missions"]
var game: Game
var game_hud: GameHud
var title_pending := false
var seen: Array = []
var _wait := 3.0
var _title: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = HudStyle.theme()
	if LaunchOptions.get_string("tutorial") == "reset":
		Settings.set_value("tutorial_seen", [])
		Settings.set_value("title_seen", false)
	seen = (Settings.get_value("tutorial_seen", []) as Array).duplicate()
	title_pending = not bool(Settings.get_value("title_seen", false))
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.04, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_title = VBoxContainer.new()
	_title.add_theme_constant_override("separation", 16)
	center.add_child(_title)
	for item: Array in [["NYC HEROES", 64, Color.WHITE], ["ONE CITY. EVERY POSSIBILITY.", 17, HudStyle.GOLD], [("TAP TO PLAY" if Device.wants_touch_controls() else "PRESS ANY KEY  /  TAP TO PLAY"), 15, HudStyle.MUTED]]:
		var label := HudStyle.label(item[0], item[1], item[2])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.add_child(label)
	visible = false


func _process(delta: float) -> void:
	(_title.get_child(2) as Label).text = "TAP TO PLAY" if Device.wants_touch_controls() else "PRESS ANY KEY  /  TAP TO PLAY"
	(_title.get_child(0) as Label).add_theme_font_size_override("font_size", clampi(int(size.x / 9.0), 24, 64))
	if not game:
		return
	visible = title_pending and not is_instance_valid(game._loading)
	if title_pending:
		return
	if not game.player_input.enabled or game_hud.banner_remaining > 0.0 or game.hero.frozen or game._name_prompt.visible or game.pause_menu.visible or game._options.visible \
			or game.coop_panel.visible or game.world_map.visible or is_instance_valid(game._loading):
		return
	_wait -= delta
	if _wait > 0.0 or seen.size() >= LESSONS.size():
		return
	var mode := game.hero.mode.name
	var lesson := ""
	var text := ""
	var touch := Device.wants_touch_controls()
	if not seen.has("move"):
		lesson = "move"
		text = "Move with the left stick. Tap SPEED to sprint. Drag the view to look." if touch else "WASD / left stick to move. Mouse / right stick to look."
	elif not seen.has("jump") and mode == &"OnFoot":
		lesson = "jump"
		text = "Hold JUMP for a super jump." if touch else "Hold Space / A to charge a super jump."
	elif not seen.has("fly") and mode != &"Drive":
		lesson = "fly"
		text = "Tap FLY. UP rises; DOWN descends." if touch else "F / Y toggles flight. Space rises; C / B descends."
	elif not seen.has("web") and mode != &"Drive":
		lesson = "web"
		text = "Hold WEB near buildings to swing." if touch else "Hold E / right mouse / RT near buildings to web-swing."
	elif not seen.has("punch") and game.encounters.nearest_thug(game.hero.world_position()):
		lesson = "punch"
		text = "Tap PUNCH near a thug to fight." if touch else "Left mouse / X punches. Chain hits to build a combo."
	elif not seen.has("car") and mode == &"OnFoot" and _car_nearby():
		lesson = "car"
		text = "Tap CAR near traffic; EXIT leaves the car." if touch else "Near a car, G / R3 takes the wheel. G / R3 exits."
	elif not seen.has("map"):
		lesson = "map"
		text = "Tap the radar for the map. Tap the map to set a waypoint." if touch else "Comma opens the map. Click a street to set a waypoint."
	elif not seen.has("missions"):
		lesson = "missions"
		text = ("Tap the gear → Missions for contracts and rewards." if touch else "Pause → Missions lists contracts and rewards.") + " Visit a purple contract or gold S radar marker."
	if not lesson.is_empty():
		teach(lesson, text)
		_wait = 12.0


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		dismiss_title()
		get_viewport().set_input_as_handled()


func dismiss_title() -> void:
	title_pending = false
	visible = false
	Settings.set_value("title_seen", true)
	dismissed.emit()


func teach(id: String, text: String) -> void:
	if seen.has(id):
		return
	seen.append(id)
	Settings.set_value("tutorial_seen", seen.duplicate())
	if game_hud:
		game_hud.notify(text)


func skip() -> void:
	seen = LESSONS.duplicate()
	Settings.set_value("tutorial_seen", seen.duplicate())
	if title_pending:
		dismiss_title()


func _car_nearby() -> bool:
	for car: Node3D in get_tree().get_nodes_in_group("drive_cars"):
		if car.global_position.distance_to(game.hero.global_position) < 30.0:
			return true
	for traffic: Traffic in get_tree().get_nodes_in_group("traffic"):
		if traffic.car_count > 0:
			return true
	return false
