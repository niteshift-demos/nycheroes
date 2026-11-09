extends Node
## Native Movie Maker reproduction using only normal HeroInput after loading.
## See docs/ROADMAP.md Flight air brake. No hero/world state is assigned here.

var _world: Game
var _hero: Hero
var _time := -1.0
var _last_beat := ""


func _ready() -> void:
	process_physics_priority = -20
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.hero
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	if _hero.frozen or _world.city.pending_count() > 0 and _time < 0.0:
		return
	if _time < 0.0:
		_time = 0.0
	_time += delta
	var input := _hero.input
	input.clear()
	input.aim = Vector3.FORWARD
	var beat := ""
	if _time < 2.0:
		beat = "Take off: normal flight"
		input.fly_toggle_pressed = _time < 0.02
		input.vertical = 1.0
	elif _time < 2.5:
		beat = "Boost: ordinary speed"
		input.stick.y = -1.0
		input.sprint_held = true
	elif _time < 5.5:
		beat = "Brake: stopping distance remains"
		input.brake_held = true
	elif _time < 8.5:
		beat = "Brake: slow approach"
		input.brake_held = true
		input.stick.y = 1.0
	elif _time < 27.0:
		beat = "Brake + descend: controlled landing"
		input.brake_held = true
		input.vertical = -1.0
	elif _time < 30.0:
		beat = "Release brake: back on foot"
	else:
		print("DEMO finished at ", _hero.world_position(), " mode=", _hero.mode.name)
		get_tree().quit()
	if beat != _last_beat:
		print("DEMO %.2f %s at %s speed %.2f mode=%s" % [_time, beat, _hero.world_position(), _hero.velocity.length(), _hero.mode.name])
		(_world.get_node("HUD/GameHud") as GameHud).notify(beat)
		_last_beat = beat
