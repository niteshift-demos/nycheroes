extends Node
## Browser-only presentation fixture: runs the real world and real mission /
## arrest events, then holds transient banners for screenshots. Excluded from
## normal exports. Launch this scene in a verification export with ?hud_case=.
## Cases: foot, car, passed, busted, knocked. Menus remain interactive on foot.

var _game: Game


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = load("res://scenes/world.tscn").instantiate()
	add_child(_game)
	while is_instance_valid(_game._loading) or _game.hero.frozen:
		await get_tree().process_frame
	while _game.onboarding and _game.onboarding.title_pending:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var scenario := LaunchOptions.get_string("hud_case", "foot")
	match scenario:
		"car":
			(_game.hero.get_mode(&"Drive") as DriveMode).interact()
			print("[hud-check] car mode=" + str(_game.hero.mode.name))
		"passed":
			_game.missions.start("rooftop_courier")
			_game.missions.finish(true)
			print("[hud-check] mission finished; cash=" + str(_game.wallet.balance))
		"busted":
			(_game.get_node("Wanted") as Wanted).set_stars(2)
			_game.hero.take_hit(1000.0, Vector3.ZERO)
			print("[hud-check] arrest event; stars=" + str(_game.hero.wanted_stars))
		"knocked":
			(_game.get_node("Wanted") as Wanted).set_stars(0)
			_game.hero.take_hit(1000.0, Vector3.ZERO)
			print("[hud-check] knockout event")
	if scenario in ["passed", "busted", "knocked"]:
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().paused = true
	print("[hud-check] ready " + scenario)
