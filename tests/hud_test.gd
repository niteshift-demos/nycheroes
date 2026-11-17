extends Node
## Pause navigation, single-player/co-op pause ownership, lifetime totals,
## tutorial persistence and dedicated menu bindings without downloading city data.
## Run: godot --headless --path . res://tests/hud_test.tscn

var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1


func _run() -> void:
	var path := "user://hud_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_file(path)
	var stats := PlayerStats.new()
	add_child(stats)
	stats.record_mission("bridge_run", true)
	stats.record_mission("bridge_run", false)
	stats.increment("cars_stolen")
	stats.totals.flown_m = 1250.0
	stats.totals.driven_m = 2300.0
	stats.totals.max_wanted = 4
	stats.save()
	Settings.use_file(path)
	var reloaded := PlayerStats.new()
	add_child(reloaded)
	_check(reloaded.totals.missions_passed == 1 and reloaded.totals.cars_stolen == 1 \
		and reloaded.totals.completed.bridge_run == 1 and reloaded.totals.flown_m == 1250.0 \
		and reloaded.totals.driven_m == 2300.0 and reloaded.totals.max_wanted == 4, "stats reload and failed missions grant no completion")
	var director := MissionDirector.new()
	director.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(director)
	var wallet := Wallet.new()
	add_child(wallet)
	var radar := Radar.new()
	radar.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(radar)
	var pause := PauseMenu.new()
	pause.missions = director
	pause.wallet = wallet
	pause.stats = stats
	pause.radar = radar
	add_child(pause)
	PauseMenu.add_action()
	OptionsPanel.add_action()
	pause.open()
	_check(pause.visible and get_tree().paused and get_viewport().gui_get_focus_owner() is Button, "pause freezes solo play and focuses Resume")
	(pause._content.get_child(3) as Button).pressed.emit()
	await get_tree().process_frame
	_check(pause._page == "missions", "mission button safely replaces its own page while emitting")
	_check(pause._content.find_children("*", "Button", false, false).size() >= director.available_missions().size() + 2, "available missions have waypoint actions and locked chapters stay compact")
	Settings.set_value("upgrade_health", 2)
	pause.show_page("stats")
	_check(pause._content.get_child(0).text.begins_with("Cash"), "stats includes current wallet")
	pause.show_page("upgrades")
	_check((pause._content.get_child(1) as Label).text.ends_with("2 / 3") and HeroUpgrades.tier("health") == 2, "Stats lists owned upgrade tiers without changing them")
	pause.close(false)
	_check(not get_tree().paused, "Resume releases owned pause")
	Net.state = Net.State.HOSTING
	pause.open()
	_check(not get_tree().paused, "co-op pause leaves the shared world running")
	pause.close(false)
	Net.state = Net.State.OFFLINE
	var map := WorldMap.new()
	map.radar = radar
	add_child(map)
	map.size = Vector2(844, 390)
	map.open()
	_check(map.visible and get_tree().paused, "map preserves a solo pause while planning a route")
	map.close()
	_check(not get_tree().paused, "closing the map releases its owned pause")
	Net.state = Net.State.HOSTING
	map.open()
	_check(not get_tree().paused, "co-op map leaves shared simulation running")
	map.close()
	Net.state = Net.State.OFFLINE
	map.open()
	map.free()
	_check(not get_tree().paused, "removing an open map cannot strand a paused tree")
	var tutorial := Onboarding.new()
	add_child(tutorial)
	_check(tutorial.title_pending, "new save has title card pending")
	tutorial.dismiss_title()
	tutorial.teach("move", "Move")
	tutorial.teach("move", "Move again")
	Settings.use_file(path)
	var returning := Onboarding.new()
	add_child(returning)
	_check(not returning.title_pending and returning.seen == ["move"], "title and once-only lesson survive reload")
	returning.skip()
	_check((Settings.get_value("tutorial_seen", []) as Array).size() == Onboarding.LESSONS.size(), "skip persists every lesson without touching cash or stats")
	LaunchOptions._options["tutorial"] = "reset"
	var reset := Onboarding.new()
	add_child(reset)
	_check(reset.title_pending and reset.seen.is_empty() and Settings.get_value("player_stats", {}).missions_passed == 1, "tutorial reset preserves lifetime stats")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	var options := InputEventKey.new()
	options.physical_keycode = KEY_O
	_check(InputMap.event_is_action(escape, "pause_menu") and not InputMap.event_is_action(escape, "options_menu") \
		and InputMap.event_is_action(options, "options_menu"), "Esc pauses and O opens options without conflicting")
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(hero)
	await _check_touch(hero)
	var services := CityShops.new()
	services.hero = hero
	var here := hero.world_position()
	services.locations = [{"position": here + Vector3.RIGHT * 25.0}, {"position": here + Vector3.RIGHT * 150.0}, {"position": here + Vector3.RIGHT * 150.1}]
	_check(services.markers().size() == 2, "service labels include 150 metres and exclude farther doors")
	services.free()
	var display := GameHud.new()
	display.hero = hero
	display.missions = director
	add_child(display)
	display.show_banner("BUSTED", "Arrest")
	hero.set_mode(&"KnockedOut")
	display._process(0.1)
	_check(display.banner_title == "BUSTED", "arrest wins over simultaneous knockout")
	hero.set_mode(&"OnFoot")
	display._process(0.1)
	display.banner_remaining = 0.0
	hero.set_mode(&"KnockedOut")
	display._process(0.1)
	_check(display.banner_title == "KNOCKED OUT", "later knockouts still show after an expired arrest")
	WorldMap.add_action()
	var bindings := {KEY_G: "interact", KEY_COMMA: "world_map", KEY_M: "coop_menu", KEY_O: "options_menu", KEY_P: "pause_menu", KEY_T: "time_of_day", KEY_N: "mute", KEY_F: "fly_toggle", KEY_E: "web", KEY_C: "descend"}
	for code: Key in bindings:
		var key := InputEventKey.new()
		key.physical_keycode = code
		var matched: Array[String] = []
		for action: StringName in InputMap.get_actions():
			if not action.begins_with("ui_") and InputMap.event_is_action(key, action):
				matched.append(action)
		# GameAudio registers its action at runtime; the world test covers it.
		if code == KEY_N and not InputMap.has_action("mute"):
			continue
		_check(matched == [bindings[code]], "%s maps only to %s" % [OS.get_keycode_string(code), bindings[code]])
	get_tree().quit(1 if _failed else 0)


## Screen events reach the same analog actions that PlayerInput reads on foot
## and in a car. Keep distinct finger IDs so another finger cannot release it.
func _check_touch(hero: Hero) -> void:
	LaunchOptions._options.erase("touch")
	Device.set_page_touch_mode(true)
	_check(Device.wants_touch_controls(), "first touch keeps all later prompts in touch mode even with a fine pointer")
	LaunchOptions._options["touch"] = "0"
	_check(not Device.wants_touch_controls(), "explicit touch=0 still wins over a previous touch")
	LaunchOptions._options["touch"] = "1"
	var coop := CoopPanel.new()
	add_child(coop)
	var touch := TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_DISABLED
	touch.hero = hero
	touch.camera_rig = ThirdPersonCamera.new()
	touch.coop_panel = coop
	add_child(touch)
	touch.set_anchors_preset(Control.PRESET_TOP_LEFT)
	touch.size = Vector2(844, 390)
	var reader := PlayerInput.new()
	reader.hero = hero
	reader.camera_rig = touch.camera_rig
	_touch_event(touch, 7, Vector2(100, 290), true)
	_touch_drag(touch, 7, Vector2(100, 260))
	reader._physics_process(0.016)
	_check(hero.input.stick.y < -0.01 and hero.input.stick.y > -1.0, "stick drag produces analog forward movement")
	_touch_drag(touch, 7, Vector2(100, 200))
	_touch_event(touch, 2, touch._by_id[&"jump"].center, true)
	_touch_event(touch, 11, Vector2(430, 240), true)
	_touch_drag(touch, 11, Vector2(450, 240))
	reader._physics_process(0.016)
	_check(is_equal_approx(hero.input.stick.y, -1.0) and hero.input.jump_held and touch.camera_rig.yaw != 0.0,
		"held stick survives simultaneous jump and camera fingers")
	_touch_event(touch, 11, Vector2(450, 240), false)
	_touch_event(touch, 2, touch._by_id[&"jump"].center, false)
	touch._physics_process(0.016)
	reader._physics_process(0.016)
	_check(hero.input.stick.length() > 0.9 and not hero.input.jump_held, "releasing other fingers leaves the stick held")
	_touch_event(touch, 7, Vector2(100, 200), false)
	reader._physics_process(0.016)
	_check(hero.input.stick == Vector2.ZERO, "lifting the stick finger clears both movement axes")
	_touch_event(touch, 5, Vector2(100, 290), true)
	_touch_drag(touch, 5, Vector2(158, 290))
	touch._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	reader._physics_process(0.016)
	_check(hero.input.stick == Vector2.ZERO and touch._stick_touch == -1, "focus loss releases a held stick")
	var display := GameHud.new()
	display.process_mode = Node.PROCESS_MODE_DISABLED
	display.touch_controls = touch
	add_child(display)
	display.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var message := "Tap the radar for the map. Tap the map to set a waypoint."
	for viewport: Vector2 in [Vector2(844, 390), Vector2(915, 412), Vector2(1616, 720), Vector2(390, 844), Vector2(844, 340), Vector2(844, 320), Vector2(874, 344), Vector2(874, 292)]:
		for insets: Vector4 in [Vector4.ZERO, Vector4(54, 0, 0, 0), Vector4(59, 0, 59, 21), Vector4(0, 0, 59, 21)]:
			touch.size = viewport
			touch.safe_insets = insets
			touch._can_fullscreen = true
			touch._layout()
			display.size = viewport
			var notice := display.notice_rect(message)
			var cash := Rect2(display.wanted_anchor() + Vector2(-210, 32), Vector2(224, 40))
			var radar := touch.radar_rect()
			var health := Rect2(radar.position - Vector2(0, 28), Vector2(radar.size.x, 28))
			var clear := not notice.intersects(radar) and not notice.intersects(cash) and notice.end.x <= viewport.x and notice.end.y <= viewport.y
			for id: StringName in [&"options", &"coop", &"sound", &"fullscreen"]:
				clear = clear and not notice.intersects(touch._by_id[id].rect)
			_check(clear, "touch toast clears radar, health, cash and toolbar at %s / inset %d" % [viewport, insets.x])
			if viewport.x > viewport.y:
				var stick := Rect2(touch._stick_home - Vector2.ONE * TouchControls.STICK_RADIUS, Vector2.ONE * TouchControls.STICK_RADIUS * 2)
				_check(not radar.intersects(stick) and not health.intersects(stick), "radar and health clear the stick at %s / %s" % [viewport, insets])
				var wanted := Rect2(display.wanted_anchor() + Vector2(-128, -12), Vector2(140, 42))
				var areas: Array[Rect2] = [radar, health, notice, cash, stick, wanted]
				for button: TouchControls.TouchButton in touch._buttons:
					if not button.shown:
						continue
					var area := Rect2(button.center - Vector2.ONE * button.radius, Vector2.ONE * button.radius * 2) if button.is_round() else button.rect
					var inside := area.position.x >= insets.x and area.position.y >= insets.y and area.end.x <= viewport.x - insets.z and area.end.y <= viewport.y - insets.w
					for reserved: Rect2 in areas:
						inside = inside and not area.intersects(reserved)
					_check(inside, "%s clears HUD and safe edges at %s / %s" % [button.id, viewport, insets])
					areas.append(area)
	_check(MissionCatalog.all().back().intro.contains("SPEED"), "mission introduction names SPEED on touch")
	display.free()
	touch.camera_rig.free()
	touch.free()
	coop.free()
	reader.free()
	Device.set_page_touch_mode(false)
	LaunchOptions._options.erase("touch")
	await get_tree().process_frame


func _touch_event(touch: TouchControls, index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	touch._input(event)


func _touch_drag(touch: TouchControls, index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	event.relative = Vector2(20, -30)
	touch._input(event)
