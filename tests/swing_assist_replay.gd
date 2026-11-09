extends Node
## Optional evidence replay in the real city. Only writes normal HeroInput;
## never moves a hero, changes world state, physics ticks, or game time.
## Launch with --solo=1 --spawn=420,30,-220,-29 --quality=low --name=SwingTester
## and --tiles_url=http://localhost:8060/tiles/ for existing streamed tiles.

var _game: Game
var _elapsed := -1.0
var _settle := 0.0
var _last_second := -1


func _ready() -> void:
	_game = load("res://scenes/world.tscn").instantiate()
	add_child(_game)
	_game.player_input.process_mode = Node.PROCESS_MODE_DISABLED
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	var hero := _game.hero
	hero.input.clear()
	hero.input.aim = _game.hero_camera.aim_direction()
	if _elapsed < 0.0:
		if hero.frozen or _game.city.pending_count() > 0:
			return
		_settle += delta
		if _settle < 3.0:
			return
		_elapsed = 0.0
		print("[swing replay] begin movie_frame=%d" % Engine.get_process_frames())
	var before := _elapsed
	_elapsed += delta
	# Three natural pendulum attachments and releases, then a normal flight
	# above nearby roofs to show the honest empty-air range limitation.
	if _elapsed >= 3.0 and _elapsed < 12.0:
		hero.input.move = Vector3(0.485, 0, -0.875)
		hero.input.stick = Vector2(0, -1)
		hero.input.web_held = fmod(_elapsed - 3.0, 3.0) < 2.1
	if before < 13.0 and _elapsed >= 13.0:
		hero.input.fly_toggle_pressed = true
	if _elapsed >= 13.0 and _elapsed < 24.0:
		hero.input.vertical = 1.0
	if before < 24.0 and _elapsed >= 24.0:
		hero.input.fly_toggle_pressed = true
	if _elapsed >= 24.0:
		hero.input.web_held = true
	var second := int(_elapsed)
	if second != _last_second:
		_last_second = second
		var swing := hero.get_mode(&"Swing") as SwingMode
		print("[swing replay] t=%d mode=%s y=%.1f speed=%.1f ready=%s" % [second, hero.mode.name, hero.world_position().y, hero.velocity.length(), not swing.preview.is_empty()])
	if _elapsed >= 30.0:
		print("[swing replay] end movie_frame=%d" % Engine.get_process_frames())
		get_tree().quit()
