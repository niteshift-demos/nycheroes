extends Node
## Optional solo verification input replay. Drives ordinary HeroInput only;
## never places actors, changes combat balance, or changes the simulation clock.
var _game: Node3D
var _time := 0.0
var _started := false
var _last_count := -1
var _label: Label


func _ready() -> void:
	_game = get_parent()
	process_physics_priority = -20
	_game.player_input.set_physics_process(false)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_label.position = Vector2(24.0, get_viewport().get_visible_rect().size.y - 92.0)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_outline_size", 6)
	_label.add_theme_font_size_override("font_size", 18)
	_game.hud.add_child(_label)
	_label.text = "SOLO INPUT REPLAY · Waiting for city streets"


func _physics_process(delta: float) -> void:
	var hero: Hero = _game.hero
	if hero.frozen or _game.city.pending_count() > 0 and not _started:
		return
	if not _started:
		_started = true
		print("[combo replay] ready")
	_time += delta
	var input := hero.input
	input.clear()
	var thug: Thug = _game.encounters.nearest_thug(hero.world_position())
	var phase := fmod(_time, 32.0)
	if phase < 23.0 and thug:
		var offset := thug.global_position - hero.global_position
		offset.y = 0.0
		input.aim = offset.normalized()
		if offset.length() > 5.0:
			input.move = input.aim
			input.stick = Vector2(0.0, -1.0)
		input.attack_held = offset.length() < 8.5 and fmod(_time, 0.28) < 0.12
		_game.hero_camera.yaw = lerp_angle(_game.hero_camera.yaw, atan2(-offset.x, -offset.z), delta * 2.0)
		_label.text = "SOLO INPUT REPLAY · Normal punches · Confirmed hits only"
	else:
		# Sprint away using the same movement input as a player; show the limit.
		input.move = hero.forward() * -1.0
		input.stick = Vector2(0.0, 1.0)
		input.sprint_held = true
		_label.text = "SOLO INPUT REPLAY · Leaving combat · Streak expires after 4s"
	if Combat.combo.count != _last_count:
		_last_count = Combat.combo.count
		print("[combo replay] t=%.2f hits=%d best=%d health=%.1f notice=%s" % [_time, _last_count, Combat.combo.best, hero.health, Combat.combo.notice])
	if _time > 32.0 and LaunchOptions.has("replay_quit") and not Device.is_web():
		get_tree().quit()
