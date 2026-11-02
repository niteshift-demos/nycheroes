extends Node
## Two processes: PlayerSync displays dodges and the defending owner resolves
## Combat's real reliable punch RPC. No tiles or public server required.
## godot --headless --path . res://tests/dodge_coop_test.tscn

var _client := false
var _client_pid := 0
var _peer: ENetMultiplayerPeer
var _players: PlayerSync
var _hero: Hero
var _reports := {}
var _port := 18764


func _ready() -> void:
	_client = LaunchOptions.get_string("role") == "client"
	_port = LaunchOptions.get_string("port", str(_port)).to_int()
	_run()


func _run() -> void:
	Net.set_process(false)
	Net.state = Net.State.JOINED if _client else Net.State.HOSTING
	Net.host_id = 1
	_hero = preload("res://scenes/hero/hero.tscn").instantiate()
	add_child(_hero)
	_hero.frozen = false
	_hero.set_physics_process(false)  # hold the seeded timing at the RPC boundary
	if _client:
		_hero.dodge_time = Hero.DODGE_DURATION - 0.05
		_hero.dodge_direction = Vector3.BACK
		_hero._dodge_start = Vector3.ZERO
	_players = PlayerSync.new()
	_players.name = "Players"
	_players.hero = _hero
	add_child(_players)
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client("127.0.0.1", _port) if _client else _peer.create_server(_port, 1)
	if error != OK:
		_fail("could not open peer: %d" % error)
		return
	multiplayer.multiplayer_peer = _peer
	if not _client:
		_client_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/dodge_coop_test.tscn", "--", "--role=client", "--port=" + str(_port)])
	if not await _until(func() -> bool: return _players.remote_heroes.size() == 1, "peer hero created"):
		return
	if _client:
		if not await _until(func() -> bool: return _hero.counter_time > 0.0 and _hero.health == Hero.MAX_HEALTH,
				"defending owner evades remote thug and earns counter"):
			return
		_report.rpc_id(1, "evaded")
		_hero.dodge_time = 0.0
		_hero.counter_time = 0.0
		if not await _until(func() -> bool: return _hero.health == Hero.MAX_HEALTH - Thug.PUNCH_DAMAGE,
				"remote punch damages owner outside dodge"):
			return
		_report.rpc_id(1, "damaged")
		await get_tree().create_timer(0.3).timeout
	else:
		var other_id: int = _players.remote_heroes.keys()[0]
		var remote: Hero = _players.remote_heroes[other_id]
		if not await _until(func() -> bool: return remote.dodge_time > 0.0 and remote.dodge_direction == Vector3.BACK,
				"dodge state crosses PlayerSync"):
			return
		Combat.resolve_punch(remote, Vector3(0.0, 0.0, -1.7), Vector3.BACK)
		if not await _until(func() -> bool: return _reports.has("evaded"), "client confirms perfect evasion"):
			return
		Combat.resolve_punch(remote, Vector3(0.0, 0.0, -1.7), Vector3.BACK)
		if not await _until(func() -> bool: return _reports.has("damaged"), "client confirms ordinary damage"):
			return
	print("DODGE_COOP %s passed" % ("client" if _client else "host"))
	_peer.close()
	get_tree().quit()


func _until(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while not predicate.call():
		if Time.get_ticks_msec() > deadline:
			_fail(label)
			return false
		await get_tree().create_timer(0.02).timeout
	print("PASS %s %s" % ["client" if _client else "host", label])
	return true


func _fail(label: String) -> void:
	push_error(label)
	if _client_pid > 0:
		OS.kill(_client_pid)
	get_tree().quit(1)


@rpc("any_peer", "call_remote", "reliable")
func _report(label: String) -> void:
	_reports[label] = true
