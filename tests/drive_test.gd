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
	var sync := PlayerSync.new()
	var state := sync._encode(hero)
	_check(state.size() == 16 and state[4] == 6 and state[13] == car.model and state[14] == car.paint, "snapshot carries driving model and paint")
	var remote: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	remote.remote_id = 2
	add_child(remote)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(float(state[0]), state)
	sync._follow(remote, snapshots)
	var remote_drive := remote.get_mode(&"Drive") as DriveMode
	_check(remote.mode.name == &"Drive" and is_instance_valid(remote_drive.car) and remote_drive.car.model == car.model, "remote snapshot displays matching car")
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
	print("DRIVE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
