extends Node3D
## Two real Godot processes, signaling + ENet, synthetic world (no downloads).
## The joined hero frees an owner's civilian; both see the same completion.
## godot --headless --path . res://tests/coop_rescue_test.tscn

const Server := preload("res://tests/signaling_server.gd")
var _server := Server.new()
var _rescue: RescueDirector
var _hero: Hero
var _client_pid := 0
var _client := false
var _room := ""
var _deadline := 0
var _made := false
var _done := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--room="):
			_client = true
			_room = arg.trim_prefix("--room=")
	LaunchOptions.set_default("signal", "ws://127.0.0.1:8076")
	LaunchOptions.set_default("net", "enet")
	_hero = preload("res://scenes/hero/hero.tscn").instantiate()
	_hero.name = "Hero"
	add_child(_hero)
	_hero.set_physics_process(false)
	_hero.frozen = false
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100, 1, 100)
	collision.shape = floor_shape
	ground.add_child(collision)
	ground.position.y = -0.5
	add_child(ground)
	await get_tree().physics_frame
	_hero.velocity = Vector3.DOWN
	_hero.move_and_slide()
	_hero.velocity = Vector3.ZERO
	var players := PlayerSync.new()
	players.name = "Players"
	players.hero = _hero
	add_child(players)
	var input := PlayerInput.new()
	input.set_physics_process(false)
	_rescue = RescueDirector.new()
	_rescue.name = "Rescues"
	_rescue.hero = _hero
	_rescue.player_input = input
	_rescue.city = CityStreamer.new()
	add_child(_rescue)
	_deadline = Time.get_ticks_msec() + 25000
	if _client:
		Net.join(_room)
	else:
		var error := _server.start(8076)
		if not error.is_empty():
			finish(false, error)
			return
		await get_tree().create_timer(1.0).timeout
		Net.host()

func _process(_delta: float) -> void:
	if _done:
		return
	_rescue._wait = 1000.0  # Only the explicit call, no sidewalk data here.
	if Time.get_ticks_msec() > _deadline:
		finish(false, "timed out")
		return
	if not _client and Net.state == Net.State.HOSTING and _client_pid == 0:
		_client_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/coop_rescue_test.tscn", "--", "--room=" + Net.room_code])
	if not _client and Net.peers().size() == 1 and not _made:
		_rescue.calls[Net.local_id()] = [7, Vector3.ZERO, 1, 0.0, false]
		_made = true
	if _client and not _rescue.calls.is_empty():
		Input.action_press("rescue")
		for call: Array in _rescue.calls.values():
			if call[4]:
				print("[PASS] joined player sees lifted debris and completed rescue")
				_report.rpc_id(Net.host_id, _rescue.saved_count == 1)
				_done = true

@rpc("any_peer", "call_remote", "reliable")
func _report(scored_once: bool) -> void:
	var call: Array = _rescue.calls[Net.local_id()]
	finish(scored_once and call[4] and is_equal_approx(call[3], RescueDirector.LIFT_SECONDS) and _rescue.saved_count == 1,
		"joined player's hold frees the owner's civilian; both score once")

func finish(ok: bool, message: String) -> void:
	_done = true
	print("[%s] %s" % ["PASS" if ok else "FAIL", message])
	if _client_pid:
		OS.kill(_client_pid)
	_server.stop()
	_rescue.set_process(false)
	_rescue.city.free()
	_rescue.player_input.free()
	get_tree().quit(0 if ok else 1)
