extends Node
## Recording harness: only replays ordinary HeroInput after the real city loads.
## It never places the hero, changes its state, camera, game time, or physics.

var _world: Game
var _time := -1.0
var _started := false
var _tick := 0
var _last_message := ""


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.player_input.set_physics_process(false)
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	if not _started and (_world.hero.frozen or _world.city.pending_count() > 0):
		return
	if not _started:
		_started = true
		_time = 0.0
		print("REPLAY START frame=", Engine.get_process_frames())
	_time += delta
	_tick += 1
	var input := _world.hero.input
	input.clear()
	# 3 seconds to settle, save, run away, try saving mid-jump, recover, then
	# show the cooldown refusal before taking another short run and retrying.
	if _tick == 180:
		input.checkpoint_pressed = true
	if _time >= 5.0 and _time < 9.0:
		input.move = Vector3(0.485, 0, -0.875)
		input.stick = Vector2(0, -1)
	if _time >= 9.0 and _time < 9.15:
		input.jump_held = true
	if _tick == 570:
		input.checkpoint_pressed = true
	if _tick == 720 or _tick == 840 or _tick == 1680:
		input.return_pressed = true
	if _time >= 18.0 and _time < 21.0:
		input.move = Vector3(0.485, 0, -0.875)
		input.stick = Vector2(0, -1)
	var message := _world.hero.safe_return.message
	if message != _last_message:
		print("REPLAY t=%.2f position=%s message=%s" % [_time, _world.hero.world_position(), message])
		_last_message = message
	if _time >= 32.0:
		print("REPLAY END frame=", Engine.get_process_frames())
		get_tree().quit()
