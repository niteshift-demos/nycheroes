extends Node
## Reproducible QA input driver for the ordinary game. Does not spawn enemies,
## teleport, change health, tune physics, or alter the world. Drives HeroInput
## and rotates the viewing camera to follow the selected real encounter.
## Run with --solo=1 --quality=low --name=Patrol --peds=0 --traffic=0.

var _game: Game
var _hud: PatrolHud
var _time := 0.0
var _started := false
var _last_progress := -1
var _last_report := -1
var _completed_at := -1.0
var _replayed := false
var _stuck := 0.0

func _ready() -> void:
	_game = load("res://scenes/world.tscn").instantiate() as Game
	add_child(_game)
	_game.player_input.set_physics_process(false)
	_hud = (_game.hud.get_node("GameHud") as GameHud).patrol_hud
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	if _game.hero.frozen:
		return
	if not _started:
		# Wait for useful footage after the city has loaded, without compression.
		if _game.city.pending_count() > 0 or is_instance_valid(_game._loading):
			return
		_started = true
		_hud._start_patrol()
		print("PATROL FOOTAGE START frame=", Engine.get_frames_drawn())
	_time += delta
	var input := _game.hero.input
	input.clear()
	var thug := _game.encounters.nearest_thug(_game.hero.world_position())
	if thug and _time < 32.0 and _completed_at < 0.0:
		var offset := thug.global_position - _game.hero.global_position
		offset.y = 0.0
		var direction := offset.normalized()
		input.aim = direction
		if offset.length() > 1.9:
			input.move = direction
			input.stick = Vector2(0, -1)
			input.sprint_held = offset.length() > 12.0
		input.attack_held = offset.length() < 7.0 and fmod(_time, 0.3) < 0.12
		# Use the ordinary flight control to get around a blocked sidewalk.
		if offset.length() > 7.0 and _game.hero.velocity.length() < 1.0:
			_stuck += delta
		else:
			_stuck = 0.0
		if _stuck > 1.0 and _game.hero.mode.name != &"Flight":
			input.fly_toggle_pressed = true
			_stuck = 0.0
		if _game.hero.mode.name == &"Flight":
			input.sprint_held = false
			var height := _game.hero.global_position.y - thug.global_position.y
			input.vertical = 1.0 if height < 80.0 else 0.0
			if height < 70.0:
				input.stick = Vector2.ZERO
			if offset.length() < 5.0 and height > 70.0:
				input.aim = (direction * 0.2 + Vector3.DOWN).normalized()
				input.attack_held = fmod(_time, 0.3) < 0.12
		if _game.hero.mode.name == &"Dive":
			input.clear()
		_game.hero_camera.yaw = lerp_angle(_game.hero_camera.yaw, atan2(-direction.x, -direction.z), delta * 3.0)
	if _hud.patrol.completed and _completed_at < 0.0:
		_completed_at = _time
		print("PATROL completed at ", _time)
	if _completed_at >= 0.0 and _time - _completed_at > 3.0:
		if not _replayed:
			_hud._start_patrol()
			_replayed = true
			print("PATROL replay at ", _time)
		# Ordinary super-speed input leaves the fresh area to expose its limit.
		input.move = Vector3(0.485, 0.0, -0.875)
		input.stick = Vector2(0, -1)
		input.sprint_held = true
	var second := int(_time)
	if second % 5 == 0 and second != _last_report:
		_last_report = second
		print("PATROL status t=", second, " position=", _game.hero.world_position(), " mode=", _game.hero.mode.name,
			" standing=", Combat.thugs.filter(func(t: Thug) -> bool: return not t.is_down()).size(), " down=", Combat.defeated_count)
		if not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
			_capture.call_deferred(second)
	if _last_progress != _hud.patrol.cleared:
		_last_progress = _hud.patrol.cleared
		print("PATROL progress=", _last_progress, " time=", _time, " health=", _game.hero.health)
	if _time > 35.0:
		print("PATROL END completed=", _hud.patrol.completed, " progress=", _hud.patrol.cleared)
		get_tree().quit()


func _capture(second: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/data/patrol/native-%02d.png" % second)
