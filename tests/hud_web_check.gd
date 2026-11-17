extends Node
## Browser presentation fixture, excluded from normal exports. Runs the real
## world and real mission/arrest APIs; holds transient results for screenshots.
## F5: foot/resume; F6: wanted mission car; F7: passed; F8: busted; F9: knockout.
## ?hud_case=foot|car|passed|busted|knocked also selects the initial case.

var _game: Game
var _ready_for_checks := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	# Software-rendered QA needs no 3-D frames while tiles are being assembled.
	# Restore normal rendering before the title, any input, or capture.
	RenderingServer.set_render_loop_enabled(false)
	_game = load("res://scenes/world.tscn").instantiate()
	add_child(_game)
	while is_instance_valid(_game._loading) or _game.hero.frozen:
		await get_tree().process_frame
	RenderingServer.set_render_loop_enabled(true)
	while _game.onboarding and _game.onboarding.title_pending:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	_ready_for_checks = true
	_scenario(LaunchOptions.get_string("hud_case", "foot"))


func _input(event: InputEvent) -> void:
	if not _ready_for_checks or not event is InputEventKey or not event.pressed or event.echo:
		return
	var cases := {KEY_F5: "foot", KEY_F6: "car", KEY_F7: "passed", KEY_F8: "busted", KEY_F9: "knocked"}
	if cases.has(event.keycode):
		get_viewport().set_input_as_handled()
		_scenario(cases[event.keycode])


func _scenario(scenario: String) -> void:
	get_tree().paused = false
	var display := _game.hud.get_node("GameHud") as GameHud
	var wanted := _game.get_node("Wanted") as Wanted
	match scenario:
		"foot":
			display.banner_remaining = 0.0
			_game.missions.banner_remaining = 0.0
			_game.hero.health = Hero.MAX_HEALTH
			if _game.hero.mode.name == &"KnockedOut":
				_game.hero.set_mode(&"OnFoot")
		"car":
			_game.missions.start("rooftop_courier")
			(_game.hero.get_mode(&"Drive") as DriveMode).interact()
			wanted.set_stars(2)
			print("[hud-check] car mode=" + str(_game.hero.mode.name))
		"passed":
			_game.missions.start("rooftop_courier")
			_game.missions.finish(true)
			print("[hud-check] mission finished; cash=" + str(_game.wallet.balance))
		"busted":
			_game.hero.health = Hero.MAX_HEALTH
			wanted.set_stars(2)
			_game.hero.take_hit(1000.0, Vector3.ZERO)
			print("[hud-check] arrest event; stars=" + str(_game.hero.wanted_stars))
		"knocked":
			_game.hero.health = Hero.MAX_HEALTH
			wanted.set_stars(0)
			_game.hero.set_mode(&"OnFoot")
			_game.hero.take_hit(1000.0, Vector3.ZERO)
			print("[hud-check] knockout event")
	if scenario in ["passed", "busted", "knocked"]:
		await get_tree().process_frame
		await get_tree().process_frame
		print("[hud-check] banner=" + display.banner_title)
		get_tree().paused = true
	print("[hud-check] ready " + scenario)
