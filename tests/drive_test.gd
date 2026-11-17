extends Node3D
## Synthetic road exercise: hijack a real traffic slot, drive, brake, shift and exit.
## Run: godot --headless --path . res://tests/drive_test.tscn

var _failures := 0
var _crimes: Array[StringName] = []


func _ready() -> void:
	Combat.crime.connect(func(kind: StringName, _at: Vector3, _severity: float) -> void: _crimes.append(kind))
	var ground := StaticBody3D.new()
	ground.add_to_group("floating")
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 1, 4000)
	collision.shape = box
	collision.position.y = -0.5
	ground.add_child(collision)
	add_child(ground)
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	hero.position = Vector3(2, 0.2, 0)
	var traffic := Traffic.new()
	traffic.max_cars = 4
	add_child(traffic)
	traffic.set_process(false)
	var lines: Array[PackedVector3Array] = [PackedVector3Array([Vector3(0, 0, -100), Vector3(0, 0, 100)])]
	traffic.set_tile_lanes(Vector2i.ZERO, lines, PackedFloat32Array([1, 2, 12, 0, 1, -1, 0]))
	# Build one slot through Traffic's real allocation/routing path.
	var lane: TrafficLanes.Lane = traffic.lanes.tiles[Vector2i.ZERO][0]
	traffic._add_car(lane, 102.35, 0, Vector3.ZERO, 0, 100, false)
	traffic._v[0] = 0.0
	await _ticks(3)
	hero.input.interact_pressed = true
	await _ticks(2)
	_check(hero.mode.name == &"Drive", "G enters nearby traffic car")
	_check(_crimes.count(&"carjack") == 1, "hijack emits one crime event")
	_check(traffic.car_count == 0 and lane.cars.is_empty(), "hijack releases traffic slot and lane")
	var drive := hero.get_mode(&"Drive") as DriveMode
	if drive.car == null:
		get_tree().quit(1)
		return
	var car := drive.car
	var start := car.global_position
	hero.input.stick = Vector2(0, -1)
	await _ticks(120)
	_check(car.velocity.length() > 12.0 and car.global_position.distance_to(start) > 10.0, "accelerates along the road")
	hero.input.jump_held = true
	await _ticks(60)
	_check(car.velocity.length() < 1.0, "handbrake wins over held throttle")
	hero.input.jump_held = false
	await _ticks(90)
	var heading := car.heading
	hero.input.stick = Vector2(0.8, -1)
	await _ticks(30)
	_check(absf(car.heading - heading) > 0.2, "steering changes heading")
	var world_before := WorldOrigin.to_world(car.global_position)
	var velocity_before := car.velocity
	WorldOrigin.shift(Vector3(1500, 0, -500))
	_check(WorldOrigin.to_world(car.global_position).distance_to(world_before) < 0.01, "origin shift preserves car world position")
	_check(car.velocity == velocity_before and hero.global_position.distance_to(car.global_position) < 0.01, "origin shift preserves velocity and driver seat")
	hero.wanted_stars = 3
	hero.wanted_searching = true
	var sync := PlayerSync.new()
	var state := sync._encode(hero)
	_check(state.size() == 22 and state[4] == 6 and state[15] == car.model and state[16] == car.paint, "snapshot carries driving model and paint")
	_check(state[13] == 3 and state[14] == true, "driving snapshot preserves wanted fields")
	var remote: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	remote.remote_id = 2
	add_child(remote)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(float(state[0]), state)
	sync._follow(remote, snapshots)
	var remote_drive := remote.get_mode(&"Drive") as DriveMode
	_check(remote.mode.name == &"Drive" and is_instance_valid(remote_drive.car) and remote_drive.car.model == car.model, "remote snapshot displays matching car")
	_check(remote.wanted_stars == 3 and remote.wanted_searching, "remote car retains wanted state")
	var copy := remote_drive.car
	remote_drive.show_remote(car.model, PoliceLivery.PAINT, 0.5)
	_check(remote_drive.car == copy and is_instance_valid(copy._livery), "same-model remote paint change adds police markings")
	remote_drive.show_remote(car.model, 1.0, 0.5)
	_check(remote_drive.car == copy and copy._livery == null, "remote respray removes police markings without replacing its car")
	remote.queue_free()
	sync.free()
	hero.input.stick = Vector2.ZERO
	hero.input.jump_held = true
	await _ticks(90)
	_check(car.velocity.length() < 1.0, "handbrake stops the car")
	hero.input.jump_held = false
	hero.input.stick = Vector2(0, 1)
	await _ticks(40)
	_check(car.velocity.dot(Vector3(sin(car.heading), 0, cos(car.heading))) < -2.0, "S reverses after stopping")
	hero.input.stick = Vector2.ZERO
	hero.input.interact_pressed = true
	await _ticks(2)
	_check(hero.mode.name == &"OnFoot" and car.driver == null and hero.collision_mask == 97, "exit restores hero and leaves physical parked car")
	_check(hero.global_position.distance_to(car.global_position) > 1.0, "exit places hero outside body")
	hero.input.interact_pressed = true
	await _ticks(2)
	_check(hero.mode.name == &"Drive" and drive.car == car, "parked car can be entered again")
	# A parked physical footprint must stop the ordinary lane simulation.
	hero.frozen = true
	car.global_position = WorldOrigin.to_local(Vector3(0, 0.1, -40))
	car.heading = 0.0
	car.velocity = Vector3.ZERO
	traffic._add_car(lane, 20.0, 0, Vector3(0, 0, -82.35), 0, 100, false)
	traffic._focus = Vector3.ZERO
	traffic._find_people()
	for i in 240:
		traffic._clock += 1.0 / 30.0
		traffic._drive(1.0 / 30.0)
		traffic._draw()
	_check(traffic._v[0] < 0.5 and traffic._at[0].z < -44.0, "traffic stops before physical car footprint")
	traffic._despawn(0)
	hero.frozen = false
	car.global_position = WorldOrigin.to_local(Vector3.ZERO)
	car.heading = 0.0
	car.velocity = Vector3.ZERO
	var pedestrian: Pedestrian = load("res://scenes/npc/pedestrian.tscn").instantiate()
	pedestrian.hero = hero
	add_child(pedestrian)
	pedestrian.set_process(false)
	pedestrian.world_position = Vector3(0, 0, 6)
	pedestrian.global_position = WorldOrigin.to_local(pedestrian.world_position)
	hero.input.stick = Vector2(0, -1)
	await _ticks(90)
	_check(pedestrian.is_knocked_down(), "moving car knocks down a pedestrian")
	_check(_crimes.count(&"vehicular_assault") == 1, "pedestrian impact emits one crime event")
	pedestrian.queue_free()
	car.global_position = WorldOrigin.to_local(Vector3.ZERO)
	car.heading = 0.0
	car.velocity = Vector3.ZERO
	var officer: PoliceOfficer = load("res://scenes/npc/police_officer.tscn").instantiate()
	add_child(officer)
	officer.setup(hero, 100, 0)
	officer.suspect_id = Net.local_id()
	officer.set_physics_process(false)
	officer.global_position = WorldOrigin.to_local(Vector3(0, 0, 6))
	_check(officer._nearest_hero() == hero, "police keep tracking a suspect who enters a car")
	await _ticks(90)
	_check(officer.is_down() and _crimes.count(&"assault_police") == 1, "car knocks down police through existing crime path")
	officer.queue_free()
	car.global_position = WorldOrigin.to_local(Vector3.ZERO)
	car.heading = PI / 4.0
	car.velocity = Vector3.ZERO
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1, 8, 200)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.global_position = WorldOrigin.to_local(Vector3(5, 4, 0))
	await _ticks(120)
	var wall_at := WorldOrigin.to_world(car.global_position)
	print("wall slide position: ", wall_at, " velocity: ", car.velocity)
	_check(wall_at.x < 4.5 and wall_at.z > 5.0, "car hits wall and slides along it")
	await _car_feel(hero, traffic, lane)
	await _wreck_sync(hero)
	print("DRIVE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _car_feel(hero: Hero, traffic: Traffic, lane: TrafficLanes.Lane) -> void:
	hero.set_mode(&"OnFoot")
	hero.input.stick = Vector2.ZERO
	for old: DriveVehicle in get_tree().get_nodes_in_group("drive_cars"):
		old.queue_free()
	await _ticks(2)
	hero.global_position = WorldOrigin.to_local(Vector3(30, 0.1, 0))
	var drive := hero.get_mode(&"Drive") as DriveMode
	_check(not drive.can_take_car(), "no take-car hint without a reachable car")
	traffic._add_car(lane, 112.35, 0, Vector3(0, 0, 10), 0, 100, false)
	traffic._v[0] = 0.0
	hero.global_position = WorldOrigin.to_local(Vector3(2, 0.1, 10))
	_check(drive.can_take_car(), "nearby traffic enables take-car hint")
	var car := DriveVehicle.new()
	car.traffic = traffic
	add_child(car)
	car.global_position = WorldOrigin.to_local(Vector3(0, 0.1, 0))
	drive.car = car
	hero.set_mode(&"Drive")
	car.velocity = Vector3(0, 0, 25)
	hero.input.stick = Vector2(0, -1)
	await _ticks(30)
	_check(traffic.car_count == 0 and lane.cars.is_empty(), "crash promotes traffic and frees lane reservations")
	_check(car.health < 100.0 and car.velocity.length() < 22.0, "solid traffic impact damages and slows player car")
	var pushed: DriveVehicle
	for other: DriveVehicle in get_tree().get_nodes_in_group("drive_cars"):
		if other != car:
			pushed = other
	_check(pushed != null and pushed.global_position.z > WorldOrigin.to_local(Vector3(0, 0, 10)).z, "traffic wreck is pushed forward")
	# Punch a fresh row and slam the resulting body through the real Combat API.
	traffic._add_car(lane, 162.35, 0, Vector3(0, 0, 60), 0, 100, false)
	Combat.strike(WorldOrigin.to_local(Vector3(0, 1, 60)), 2.0, 20.0, Vector3(12, 2, 0), true)
	_check(traffic.car_count == 0, "super punch promotes a traffic row")
	Combat.shockwave(WorldOrigin.to_local(Vector3(0, 0, 60)), 6.0, 20.0, 14.0)
	# A witness outside blast range still makes an exploding car a crime.
	var witness: Pedestrian = load("res://scenes/npc/pedestrian.tscn").instantiate()
	witness.hero = hero
	add_child(witness)
	witness.set_process(false)
	witness.global_position = car.global_position + Vector3(15, 0, 0)
	witness.world_position = WorldOrigin.to_world(witness.global_position)
	hero.input.stick = Vector2.ZERO
	hero.input.jump_held = true
	var before_health := hero.health
	car.take_hit(200.0, Vector3.ZERO)
	_check(car.burn_time > 0.0 and not car.exploded, "zero health starts escape countdown")
	await get_tree().create_timer(3.3).timeout
	_check(car.exploded and car.health == 0.0 and car.collision_layer == DriveVehicle.LAYER, "fire leaves a solid burned wreck")
	_check(hero.health < before_health and hero.mode.name != &"Drive", "explosion hurts and ejects seated driver")
	_check(_crimes.has(&"car_explosion"), "explosion near pedestrian reports crime")
	hero.global_position = car.global_position + Vector3(2, 0, 0)
	if pushed:
		pushed.queue_free()
	await _ticks(2)
	_check(not drive.can_take_car(), "burned wreck cannot be taken")
	witness.queue_free()
	# Queries stay local and exclude a car on the bridge above the sweep.
	_check(not DriveVehicle.swept_overlap(Vector3.ZERO, Vector3(0, 0, 100), Vector3(4.7, 1.8, 1.5), 0, Vector3(0, 10, 50), Vector3(4.7, 1.8, 1.5), 0), "sweep ignores traffic on another elevation")
	_check(DriveVehicle.swept_overlap(Vector3.ZERO, Vector3(0, 0, 100), Vector3(0.7, 0.7, 1.8), 0, Vector3(0, 0, 50), Vector3(4.7, 1.8, 1.5), PI / 4), "fast hero sweep catches angled traffic between ticks")
	# Exercise the hero's actual move_and_slide path, beyond the pure sweep test.
	for old: DriveVehicle in get_tree().get_nodes_in_group("drive_cars"):
		old.queue_free()
	await _ticks(2)
	hero.input.clear()
	hero.hurt_time = 0.0
	hero.global_position = WorldOrigin.to_local(Vector3(0, 0.1, 72))
	hero.velocity = Vector3(0, 0, 40)
	hero.input.move = Vector3(0, 0, 1)
	hero.input.sprint_held = true
	traffic._add_car(lane, 182.35, 0, Vector3(0, 0, 80), 0, 100, false)
	traffic._v[0] = 0.0
	await _ticks(20)
	_check(traffic.car_count == 0, "sprinting hero makes traffic solid before contact")
	var rammed := get_tree().get_first_node_in_group("drive_cars") as DriveVehicle
	_check(rammed != null and rammed.health < 100.0, "hero body impact shoves and damages the car")
	hero.input.clear()
	hero.frozen = true
	await _ramp_check(hero)
	traffic._setup_slots(180)
	for i in 180:
		traffic._add_car(lane, 90.0, 0, Vector3(6 + (i % 10) * 20, 0, 6 + (i / 10) * 20), 0, 100, false)
	var started := Time.get_ticks_usec()
	for i in 1000:
		traffic.solidify_sweep(WorldOrigin.to_local(Vector3.ZERO), Vector3(0, 0, 0.5), Vector3(4.7, 1.8, 1.5), 0.0)
	var query_ms := (Time.get_ticks_usec() - started) / 1000000.0
	print("Traffic query average ms: ", query_ms)
	_check(query_ms < 0.2, "nearby traffic query stays below 0.2 ms")


func _ramp_check(hero: Hero) -> void:
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.4, 20)
	shape.shape = box
	ramp.add_child(shape)
	add_child(ramp)
	ramp.global_position = WorldOrigin.to_local(Vector3(-50, 1.5, 10))
	ramp.rotation.x = -0.18
	var car := DriveVehicle.new()
	add_child(car)
	car.global_position = WorldOrigin.to_local(Vector3(-50, 0.1, -6))
	car.driver = hero
	car.velocity = Vector3(0, 0, 22)
	var controls := HeroInput.new()
	controls.stick = Vector2(0, -1)
	var launched := false
	var landed := false
	for i in 160:
		await get_tree().physics_frame
		car.drive(controls, 1.0 / 60.0)
		if WorldOrigin.to_world(car.global_position).z > 17.0 and not car.is_on_floor() and car.velocity.y > 0.1:
			launched = true
		if launched and car.is_on_floor():
			landed = true
	_check(launched and landed, "car leaves a ramp crest and lands without sticking")
	car.driver = null
	car.queue_free()
	ramp.queue_free()


## Real hero RPC: a lost blast packet is recovered by the following full state.
func _wreck_sync(hero: Hero) -> void:
	hero.set_mode(&"OnFoot")
	hero.frozen = true
	hero.global_position = WorldOrigin.to_local(Vector3(900, 0, 900))
	var owner := Node3D.new()
	var guest := Node3D.new()
	add_child(owner)
	add_child(guest)
	var server := SceneMultiplayer.new()
	var client := SceneMultiplayer.new()
	get_tree().set_multiplayer(server, owner.get_path())
	get_tree().set_multiplayer(client, guest.get_path())
	var host_peer := ENetMultiplayerPeer.new()
	var guest_peer := ENetMultiplayerPeer.new()
	var port := 29000 + OS.get_process_id() % 10000
	_check(host_peer.create_server(port) == OK, "wreck transport opens ENet server")
	server.multiplayer_peer = host_peer
	guest_peer.create_client("127.0.0.1", port)
	client.multiplayer_peer = guest_peer
	var send := PlayerSync.new()
	var receive := PlayerSync.new()
	for sync: PlayerSync in [send, receive]:
		sync.name = "Players"
		sync.hero = hero
	owner.add_child(send)
	guest.add_child(receive)
	var remote: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	remote.remote_id = 1
	guest.add_child(remote)
	var buffer := SnapshotBuffer.new()
	receive._snapshots[1] = buffer
	for i in 120:
		if not server.get_peers().is_empty():
			break
		await get_tree().process_frame
	if server.get_peers().is_empty():
		_check(false, "wreck client connects")
		return
	var drive := hero.get_mode(&"Drive") as DriveMode
	var car := DriveVehicle.new()
	add_child(car)
	car.global_position = hero.global_position + Vector3(20, 0, 0)
	drive.car = car
	hero.set_mode(&"Drive")
	car.explode()
	_check(hero.mode.name != &"Drive" and car.is_in_group("shared_wrecks"), "occupied explosion survives driver exit in shared state")
	var state := send._encode(hero)
	var event: Array = (state[21] as Array).back()
	state[21] = [event]
	var explosions: Array[int] = [0]
	var count_blast := func(_at: Vector3, _strength: float) -> void: explosions[0] += 1
	Combat.impact.connect(count_blast)
	var health := hero.health
	var crimes := _crimes.size()
	# No explosion-frame packet: the next ordinary state must be enough.
	send._hero_state.rpc_id(server.get_peers()[0], state)
	await get_tree().create_timer(0.2).timeout
	explosions[0] = 0  # Ignore unrelated physical crashes while the RPC was in flight.
	receive._follow(remote, buffer)
	var copies: Dictionary = receive._wreck_copies.get(1, {})
	_check(copies.has(car.wreck_id), "real ENet hero snapshot creates wreck after driver exits")
	if copies.has(car.wreck_id):
		var wreck: DriveVehicle = copies[car.wreck_id]
		_check(wreck.exploded and wreck.collision_layer == 0 and wreck.driver == null, "remote wreck is charred and visual-only")
		_check(WorldOrigin.to_world(wreck.global_position).distance_to(event[1]) < 0.01, "remote wreck uses blast location, not ejected hero")
		var at := WorldOrigin.to_world(wreck.global_position)
		WorldOrigin.shift(Vector3(500, 0, 500))
		_check(WorldOrigin.to_world(wreck.global_position).distance_to(at) < 0.01, "remote wreck survives floating-origin shift")
		receive._follow(remote, buffer)
		_check(explosions[0] == 1 and receive._wreck_copies[1][car.wreck_id] == wreck, "repeated snapshot does not replay blast or duplicate wreck")
	_check(hero.health == health and _crimes.size() == crimes, "remote explosion causes no duplicate damage or crime")
	car.wreck_age = PlayerSync.WRECK_SECONDS + 1.0
	receive._follow_wrecks(remote, send._encode_wrecks(hero))
	_check(not receive._wreck_copies[1].has(car.wreck_id), "expired wreck disappears from shared state and receiver")
	# Re-entering range or joining after the blast shows a wreck without old fire.
	event[6] = 5.0
	receive._last_wreck.clear()
	receive._follow_wrecks(remote, [event])
	_check(explosions[0] == 1, "late snapshot does not replay an old explosion")
	receive._remove_player(1)
	_check(not receive._wreck_copies.has(1), "disconnect removes peer wreck copies")
	var burst: Array[DriveVehicle] = []
	for i in 4:
		var body := DriveVehicle.new()
		body.wreck_id = car.wreck_id + 10 - i  # Tree order differs from blast order.
		body.exploded = true
		body.puppet = true
		add_child(body)
		body.add_to_group("shared_wrecks")
		burst.append(body)
	var bounded := send._encode_wrecks(hero)
	_check(bounded.size() == 3 and bounded[0][0] == car.wreck_id + 8 and bounded[2][0] == car.wreck_id + 10,
		"snapshot retains only the three newest wrecks regardless of tree order")
	for body in burst:
		body.queue_free()
	Combat.impact.disconnect(count_blast)
	car.queue_free()
	host_peer.close()
	guest_peer.close()
	owner.queue_free()
	guest.queue_free()
