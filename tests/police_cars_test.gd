extends Node3D
## Synthetic street: caps, AI pursuit/deployment, roadblocks, sight/search,
## stolen livery/crime, origin shifts and loss-tolerant plain fleet snapshots.
## Run: godot --headless --path . res://tests/police_cars_test.tscn

class Street extends CityStreamer:
	func _ready() -> void:
		set_process(false)
	func has_collision_at(_at: Vector3) -> bool:
		return true
	func ground_height_at(_at: Vector3, _search_from := INF) -> float:
		return 0.0

var _failures := 0
var _crime_severity := 0.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 1, 2000)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.position.y = -0.5
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	var city := Street.new()
	add_child(city)
	var director := EncounterDirector.new()
	director.hero = hero
	director.city = city
	add_child(director)
	director.set_process(false)
	var wanted := Wanted.new()
	wanted.hero = hero
	wanted.city = city
	wanted.encounters = director
	add_child(wanted)
	wanted.set_physics_process(false)
	var pursuit := wanted.pursuit
	pursuit.set_physics_process(false)
	var lanes: Array[PackedVector3Array] = [PackedVector3Array([Vector3(0, 0, -150), Vector3(0, 0, -40)])]
	var info := PackedFloat32Array([1, 2, 11.2, 0, 1, -1, 0])
	pursuit._lanes_changed(Vector2i.ZERO, lanes, info)
	await _ticks(2)
	for stars in range(1, 6):
		wanted.set_stars(stars)
		for i in 10:
			pursuit.advance(3.0)
		_check(pursuit.cars.size() == PolicePursuit.cap(stars), "%d stars cap at %d patrol cars" % [stars, PolicePursuit.cap(stars)])
		if stars == 5:
			wanted.set_stars(2)
			pursuit.advance(0.2)
			_check(pursuit.cars.size() == 1, "falling wanted level lowers existing fleet cap")
		for car in pursuit.cars:
			car.queue_free()
		pursuit.cars.clear()
		await _ticks(2)
	wanted.set_stars(3)
	var car := pursuit.spawn(Vector3(0, 0.1, -65), 0.0)
	var starting := car.global_position.distance_to(hero.global_position)
	for i in 120:
		pursuit.think(car, 1.0 / 60.0)
		await get_tree().physics_frame
	_check(car.global_position.distance_to(hero.global_position) < starting - 8.0, "shared car physics chases toward suspect")
	_check(wanted.police_see_hero(), "patrol sight resets wanted escape clock")
	var world_before := WorldOrigin.to_world(car.global_position)
	var velocity_before := car.velocity
	WorldOrigin.shift(Vector3(500, 0, 0))
	_check(WorldOrigin.to_world(car.global_position).distance_to(world_before) < 0.01 and car.velocity == velocity_before, "moving patrol survives floating origin shift")
	WorldOrigin.shift(Vector3(-500, 0, 0))
	wanted.searching = true
	car.last_known = Vector3(0, 0, 30)
	hero.global_position = Vector3(200, 0, 0)
	pursuit.think(car, 0.2)
	_check(car.last_known == Vector3(0, 0, 30), "search keeps last known position while hero escapes")
	wanted.searching = false
	hero.global_position = Vector3.ZERO
	car.global_position = Vector3(0, 0.1, -12)
	car.velocity = Vector3.ZERO
	pursuit.think(car, 0.2)
	var officers := Combat.thugs.filter(func(t: Thug) -> bool: return t is PoliceOfficer)
	_check(car.deployed and not car.ai_controlled and officers.size() == 2, "stopped patrol deploys two existing officers near foot suspect")
	for officer: Thug in officers:
		officer.set_physics_process(false)
		Combat.unregister(officer)
		officer.queue_free()
	Combat.crime.connect(func(_kind: StringName, _at: Vector3, severity: float) -> void: _crime_severity = severity)
	hero.global_position = car.global_position + Vector3.RIGHT * 2.0
	var mode := hero.get_mode(&"Drive") as DriveMode
	mode.interact()
	_check(hero.mode == mode and mode.car == car and _crime_severity == 2.0, "G steals deployed patrol and reports severity two")
	var sync := PlayerSync.new()
	var state := sync._encode(hero)
	sync.free()
	_check(float(state[16]) == PoliceLivery.PAINT, "stolen patrol livery uses ordinary driver snapshot")
	mode.interact()
	await _ticks(2)
	var desc := car.description()
	desc[0] = int(desc[0]) + 100000
	director.receive_police_cars([desc], 99)
	await _ticks(2)
	var copy: PoliceCar
	for candidate: PoliceCar in get_tree().get_nodes_in_group("police_cars"):
		if candidate.puppet:
			copy = candidate
	_check(copy != null and copy.run_by == 99 and copy.suspect_id == Net.local_id() and copy.deployed, "fleet description preserves owner, suspect and parked state")
	desc[1] = Vector3(20, 0, 0)
	director.receive_police_cars([desc], 99)
	await _ticks(30)
	_check(copy.global_position.distance_to(Vector3(20, 0, 0)) < 0.1 and copy.collision_layer == 0, "remote patrol follows snapshots without local physics")
	director.receive_police_cars([], 99)
	await _ticks(2)
	_check(not is_instance_valid(copy), "empty fleet removes remote cars")
	car.queue_free()
	pursuit.cars.clear()
	await _ticks(2)
	var player_car := DriveVehicle.new()
	add_child(player_car)
	mode.car = player_car
	hero.set_mode(&"Drive")
	wanted.set_stars(4)
	hero.velocity = Vector3(0, 0, -15)
	_check(pursuit._spawn_patrol(true), "four-star driving suspect gets roadblock ahead")
	_check(pursuit.cars.size() == 2 and pursuit.cars.all(func(c: PoliceCar) -> bool: return c.roadblock and not c.ai_controlled), "roadblock has two parked cars across road")
	for block in pursuit.cars:
		_check(absf(cos(block.heading)) < 0.01, "roadblock faces across driving lane")
	var far := pursuit.spawn(Vector3(800, 0, 0), 0.0)
	pursuit.advance(0.2)
	await _ticks(2)
	_check(not is_instance_valid(far), "far unseen patrol despawns")
	wanted.set_stars(0)
	pursuit.advance(0.2)
	await _ticks(2)
	_check(pursuit.cars.is_empty(), "cleared wanted level removes police response")
	await _network_fleet(hero, city, desc)
	print("police_cars_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


## Exercise the actual EncounterDirector RPC over ENet, with separate scene
## multiplayer roots so no city downloads or signaling process are needed.
func _network_fleet(hero: Hero, city: CityStreamer, data: Array) -> void:
	var server_root := Node3D.new()
	var client_root := Node3D.new()
	add_child(server_root)
	add_child(client_root)
	var server_api := SceneMultiplayer.new()
	var client_api := SceneMultiplayer.new()
	get_tree().set_multiplayer(server_api, server_root.get_path())
	get_tree().set_multiplayer(client_api, client_root.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	var client_peer := ENetMultiplayerPeer.new()
	var port := 19000 + OS.get_process_id() % 10000
	_check(server_peer.create_server(port) == OK, "fleet transport opens ENet server")
	server_api.multiplayer_peer = server_peer
	client_peer.create_client("127.0.0.1", port)
	client_api.multiplayer_peer = client_peer
	var send := EncounterDirector.new()
	var receive := EncounterDirector.new()
	for director: EncounterDirector in [send, receive]:
		director.name = "Encounters"
		director.hero = hero
		director.city = city
	server_root.add_child(send)
	client_root.add_child(receive)
	send.set_process(false)
	receive.set_process(false)
	for i in 120:
		if not server_api.get_peers().is_empty():
			break
		await get_tree().process_frame
	if server_api.get_peers().is_empty():
		_check(false, "fleet client connects")
		return
	var peer := server_api.get_peers()[0]
	send._police_car_states.rpc_id(peer, [data])
	await get_tree().create_timer(0.2).timeout
	var copies := receive.get_children().filter(func(node: Node) -> bool: return node is PoliceCar)
	_check(copies.size() == 1 and copies[0].puppet and copies[0].suspect_id == int(data[4]), "real ENet RPC creates suspect-owned patrol copy")
	data[1] = Vector3(36, 0, 0)
	send._police_car_states.rpc_id(peer, [data])
	await get_tree().create_timer(0.5).timeout
	_check(copies.size() == 1 and copies[0].global_position.distance_to(Vector3(36, 0, 0)) < 0.1, "real ENet patrol snapshots move remote car")
	send._police_car_states.rpc_id(peer, [])
	await get_tree().create_timer(0.2).timeout
	_check(receive.get_child_count() == 0, "real ENet empty fleet removes remote car")
	server_peer.close()
	client_peer.close()
	server_root.queue_free()
	client_root.queue_free()
