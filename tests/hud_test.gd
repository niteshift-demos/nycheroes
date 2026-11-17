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
	_check(pause._content.find_children("*", "Button", false, false).size() >= director.catalog.size() + 2, "all contracts have waypoint actions and side job is in menu")
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
