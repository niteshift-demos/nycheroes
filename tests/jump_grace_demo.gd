extends Node
## Reproducible gameplay capture: drives only normal HeroInput after ordinary spawn.
## No teleports, velocity edits, physics changes, or changes to the city.
## Run with --spawn=30,33.3,-10,90 --solo=1 --tiles_url=https://nycheroes.party/tiles.

var _game: Game
var _hero: Hero
var _caption: Label
var _phase := -1
var _time := 0.0
var _air_ticks := 0
var _pressed := false
var _previous_floor := false
var _elapsed := 0.0


func _ready() -> void:
	process_physics_priority = -20
	_game = load("res://scenes/world.tscn").instantiate()
	add_child(_game)
	_hero = _game.hero
	_game.player_input.process_mode = Node.PROCESS_MODE_DISABLED
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(36, 586)
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption)


func _physics_process(delta: float) -> void:
	_hero.input.clear()
	if _phase < 0:
		if _hero.frozen or _game.city.pending_count() > 0 or not _hero.is_on_floor():
			return
		_time += delta
		if _time >= 1.0:
			print("[jump demo] useful footage begins; movie frame %d" % Engine.get_frames_drawn())
			_next(0, "Forgiving jumps • 120 ms of grace\nNormal HeroInput replay • solo • medium quality")
		return
	_time += delta
	_elapsed += delta
	if _hero.is_on_floor() and not _previous_floor:
		print("[jump demo] landed t=%.3f at %s" % [_elapsed, _hero.world_position()])
	_previous_floor = _hero.is_on_floor()
	if int(_elapsed * 60) % 30 == 0:
		print("[jump demo] t=%.2f phase=%d y=%.3f vy=%.3f grounded=%s" % [
			_elapsed, _phase, _hero.world_position().y, _hero.velocity.y, _hero.is_on_floor()])
	match _phase:
		0:
			if _time > 2.0:
				_next(1, "Walk off the roof, then press jump\nThe press comes 50 ms after leaving the ledge")
		1:
			_hero.input.move = Vector3.LEFT
			if not _hero.is_on_floor():
				_air_ticks += 1
				if _air_ticks == 3:
					_hero.input.jump_held = true
					print("[jump demo] ledge press after 3 airborne ticks vy=%.3f" % _hero.velocity.y)
					_next(2, "Late ledge press accepted\nNext: tap jump just before touching down")
		2:
			# Counter-steer through input, so the hero lands in the plaza.
			if _hero.velocity.x < -0.5:
				_hero.input.move = Vector3.RIGHT
			if not _pressed and _hero.velocity.y < -1.0 and _landing_soon():
				_pressed = true
				_hero.input.jump_held = true
				print("[jump demo] buffered tap y=%.3f vy=%.3f" % [_hero.world_position().y, _hero.velocity.y])
			if _pressed and _hero.velocity.y > 1.0:
				_next(3, "A released tap before landing still jumps\nOne press produces one jump")
		3:
			if _time > 3.0 and _hero.is_on_floor():
				_next(4, "The limit: no double jump\nA press high in the air expires before landing")
		4:
			_hero.input.jump_held = _time < 0.1 or (_time > 0.4 and _time < 0.45)
			if _time > 3.5:
				_next(5, "Holding jump still charges a super jump\nAirborne time never adds charge")
		5:
			_hero.input.jump_held = _time < 1.3
			if _time > 7.5 and _hero.is_on_floor():
				_next(6, "120 ms after a ledge • 120 ms before landing\nOutside those windows, press again on the ground")
		6:
			if _time > 4.0:
				print("[jump demo] finished %.3f seconds of useful footage" % _elapsed)
				get_tree().quit()
	if _elapsed > 45.0:
		push_error("Jump demo did not finish its route")
		get_tree().quit(1)


func _landing_soon() -> bool:
	var from := _hero.global_position + Vector3.UP * 0.05
	var distance := -_hero.velocity.y * 0.075
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * distance, Hero.WORLD_LAYER)
	return not _hero.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _next(phase: int, text: String) -> void:
	_phase = phase
	_time = 0.0
	_caption.text = text
	print("[jump demo] phase %d: %s" % [phase, text.replace("\n", " / ")])
