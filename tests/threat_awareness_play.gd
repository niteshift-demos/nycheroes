extends Node
## Native Movie Maker reproduction: normal world, automatic gangs, HeroInput only.
## No hero/enemy/world transforms, health, physics or combat timing are changed.
## Launch with --solo=1 --spawn=420,30,-220,-29 --quality=medium --gangs=1.

var _world: Game
var _hero: Hero
var _city: CityStreamer
var _camera: ThirdPersonCamera
var _time := 0.0
var _contact := false
var _settle := 0.0
var _max_cues := 0
var _incoming_frames := 0
var _last_report := -1


func _ready() -> void:
	seed(20261109)
	_world = load("res://scenes/world.tscn").instantiate() as Game
	add_child(_world)
	_hero = _world.hero
	_city = _world.city
	_camera = _world.hero_camera
	_world.get_node("HUD/NamePrompt").close()
	_world.player_input.process_mode = Node.PROCESS_MODE_DISABLED
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	_hero.input.clear()
	if _hero.frozen:
		return
	_settle += delta
	if _settle < 2.0:
		return
	var thug := _world.encounters.nearest_thug(_hero.world_position())
	if thug == null:
		if _contact:
			_time += delta
		else:
			return
	else:
		var toward := thug.global_position - _hero.global_position
		toward.y = 0.0
		var direction := toward.normalized()
		if not _contact:
			_camera.yaw = lerp_angle(_camera.yaw, atan2(-direction.x, -direction.z), minf(1.0, delta * 2.0))
			if toward.length() > 9.0:
				_hero.input.move = direction
				_hero.input.stick = Vector2(0.0, -1.0)
			else:
				_contact = true
				print("[threat-film] start frame=", Engine.get_process_frames())
		else:
			_time += delta
			# Look away smoothly to expose edge cues, then turn back to see telegraphs.
			if _time < 5.0:
				_camera.yaw += delta * 0.5
			elif _time < 10.0:
				_camera.yaw -= delta * 0.5
			elif _time > 13.0 and _time < 16.0:
				_hero.input.attack_held = fmod(_time, 0.45) < 0.2
			elif _time > 19.0:
				_hero.input.move = -direction
				_hero.input.stick = Vector2(0.0, 1.0)
				_hero.input.sprint_held = true
			_hero.input.aim = _camera.aim_direction()
	var overlay := _world.get_node("HUD/GameHud/ThreatAwareness") as ThreatAwareness
	_max_cues = maxi(_max_cues, overlay.shown_count)
	if overlay.incoming_count > 0:
		_incoming_frames += 1
	var report := int(_time / 5.0)
	if _contact and report != _last_report:
		_last_report = report
		print("[threat-film] t=%.1f frame=%d cues=%d incoming=%d hero=%s" % [_time, Engine.get_process_frames(), overlay.shown_count, overlay.incoming_count, _hero.world_position()])
	if _time > 30.0:
		print("[threat-film] finished max_cues=%d incoming_ticks=%d final_cues=%d health=%.0f" % [_max_cues, _incoming_frames, overlay.shown_count, _hero.health])
		get_tree().quit()
