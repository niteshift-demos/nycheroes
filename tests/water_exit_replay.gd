extends Node
## Reproducible native Movie Maker gameplay capture. Drives ONLY HeroInput;
## world and hero state are never moved or overridden after ordinary spawn.
## Run with --solo=1 --quality=low --spawn=1614,38,-3100,90
## and --tiles_url=http://localhost:8060/tiles. Physics remains at 60 Hz.

var _world: Game
var _hero: Hero
var _city: CityStreamer
var _time := -1.0
var _settle := 0.0
var _last_second := -1


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	_hero.input.clear()
	if _time < 0.0:
		if _hero.frozen or _city.pending_count() > 0:
			return
		_settle += delta
		if _settle < 3.0:
			return
		_time = 0.0
		print("REPLAY_START frame=%d physics=%d" % [Engine.get_process_frames(), Engine.physics_ticks_per_second])
	_time += delta
	if _time >= 3.0 and _time < 10.0:
		_move(Vector3.LEFT)
		_hero.input.jump_held = _time >= 8.0 and _time < 10.0
	elif _time >= 14.0 and _time < 18.0:
		_move(Vector3.RIGHT)
	elif _time >= 21.0 and _time < 21.15:
		_hero.input.jump_held = true
	elif _time >= 25.0:
		_move(Vector3.LEFT)
		_hero.input.jump_held = true
	var second := int(_time)
	if second != _last_second:
		_last_second = second
		print("REPLAY %02d pos=%s water=%.3f swimming=%s floor=%s wall=%s mode=%s" % [second,
			_hero.world_position(), _hero.water_level, _hero.is_in_water(), _hero.is_on_floor(), _hero.is_on_wall(), _hero.mode.name])
	if _time >= 30.0:
		get_tree().quit()


func _move(direction: Vector3) -> void:
	_hero.input.move = direction
	_hero.input.stick = Vector2(0.0, -1.0)
	_hero.input.aim = direction
