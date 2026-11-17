class_name PauseMenu
extends Control
## Single-player pauses; co-op only releases local controls. All actions are
## focusable and the scrolling content fits landscape phones as well as desktop.

signal toggled(open: bool)
signal map_requested
signal options_requested
signal coop_requested
signal skip_tutorial_requested

var missions: MissionDirector
var wallet: Wallet
var stats: PlayerStats
var radar: Radar
var _content: VBoxContainer
var _heading: Label
var _margin: MarginContainer
var _scroll: ScrollContainer
var _paused_game := false
var _recapture := false
var _page := ""


static func add_action() -> void:
	if InputMap.has_action(&"pause_menu"):
		return
	InputMap.add_action(&"pause_menu")
	for code: Key in [KEY_ESCAPE, KEY_P]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(&"pause_menu", key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_START
	InputMap.action_add_event(&"pause_menu", pad)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = HudStyle.theme()
	var shade := ColorRect.new()
	shade.color = HudStyle.INK
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_heading = HudStyle.label("", 28, HudStyle.GOLD)
	column.add_child(_heading)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	visible = false
	resized.connect(_layout)
	_layout()
	Net.state_changed.connect(func() -> void:
		if _paused_game and Net.state != Net.State.OFFLINE:
			get_tree().paused = false
			_paused_game = false)


func open() -> void:
	if visible:
		return
	_recapture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_paused_game = Net.state == Net.State.OFFLINE and not get_tree().paused
	if _paused_game:
		get_tree().paused = true
	stats.save()
	show_page("home")
	toggled.emit(true)


func close(recapture := true) -> void:
	if not visible:
		return
	visible = false
	get_viewport().gui_release_focus()
	if _paused_game:
		get_tree().paused = false
		_paused_game = false
	if recapture and _recapture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(false)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"coop_menu"):
		_leave(coop_requested)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"options_menu"):
		_leave(options_requested)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"world_map"):
		_leave(map_requested)
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed(&"pause_menu") or event.is_action_pressed(&"ui_cancel")):
		if _page == "home":
			close()
		else:
			show_page("home")
		get_viewport().set_input_as_handled()


## Exposed for integration checks and future phone-menu entry points.
func show_page(page: String) -> void:
	_page = page
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()  # A pressed button may be the signal sender.
	_scroll.scroll_vertical = 0
	_heading.text = "NYC HEROES  /  " + ("PAUSED" if page == "home" and _paused_game else page.to_upper())
	match page:
		"home":
			_content.add_child(HudStyle.label("THE CITY IS YOURS", 14, HudStyle.MUTED))
			_button("Resume", close)
			_button("Map", func() -> void: _leave(map_requested))
			_button("Missions", func() -> void: show_page("missions"))
			_button("Stats", func() -> void: show_page("stats"))
			_button("Hero / Options", func() -> void: _leave(options_requested))
			_button("Co-op", func() -> void: _leave(coop_requested))
			_button("Skip tutorial", func() -> void:
				skip_tutorial_requested.emit()
				close())
		"missions":
			for mission in missions.catalog:
				var running := missions.active == mission
				var completed: Dictionary = stats.totals.get("completed", {})
				var status := "ACTIVE" if running else ("PASSED" if completed.has(mission.id) else "AVAILABLE")
				var label := HudStyle.label("%s  ·  %s  ·  %s" % [mission.title, Wallet.format_cash(mission.reward), status])
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_content.add_child(label)
				_button("Set waypoint", func() -> void:
					radar.set_waypoint(missions.current_target() if running else mission.giver)
					_leave(map_requested))
			if missions.active:
				_button("Abandon current mission", func() -> void:
					missions.finish(false)
					close())
			else:
				_button("Side job  ·  $1,200", func() -> void:
					missions.side_job()
					close())
				if missions.last_mission:
					_button("Retry last mission", func() -> void:
						missions.retry()
						close())
			_button("Back", func() -> void: show_page("home"))
		"stats":
			var rows: Array[String] = ["Cash  " + Wallet.format_cash(wallet.balance),
				"Missions passed  %d" % int(stats.totals.get("missions_passed", 0)),
				"Cars stolen  %d" % int(stats.totals.get("cars_stolen", 0)),
				"Highest wanted level  %d / 5" % int(stats.totals.get("max_wanted", 0)),
				"Distance flown  %.2f km" % (float(stats.totals.get("flown_m", 0.0)) / 1000.0),
				"Distance driven  %.2f km" % (float(stats.totals.get("driven_m", 0.0)) / 1000.0)]
			for row in rows:
				_content.add_child(HudStyle.label(row, 20))
			_content.add_child(HudStyle.label("UPGRADES · OWNED TIERS", 14, HudStyle.GOLD))
			for id: String in HeroUpgrades.NAMES:
				_content.add_child(HudStyle.label("%s  ·  %d / 3" % [HeroUpgrades.NAMES[id], HeroUpgrades.tier(id)]))
			_button("Back", func() -> void: show_page("home"))
	var first := _content.find_children("*", "Button", false, false)
	if not first.is_empty():
		(first[0] as Button).grab_focus()


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 46.0
	button.pressed.connect(action)
	_content.add_child(button)


func _leave(action: Signal) -> void:
	close(false)
	action.emit()


func _layout() -> void:
	if not _margin:
		return
	var horizontal := maxi(24, int((size.x - 720.0) * 0.5))
	var vertical := maxi(20, int((size.y - 650.0) * 0.5))
	_margin.add_theme_constant_override("margin_left", horizontal)
	_margin.add_theme_constant_override("margin_right", horizontal)
	_margin.add_theme_constant_override("margin_top", vertical)
	_margin.add_theme_constant_override("margin_bottom", vertical)
