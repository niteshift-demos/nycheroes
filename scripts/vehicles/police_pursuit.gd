class_name PolicePursuit
extends Node
## Bounded, suspect-owned patrol response. All path/search positions are world
## coordinates. Lane updates and 5 Hz decisions avoid per-frame graph searches.

const THINK_INTERVAL := 0.2
const DESPAWN_RANGE := 360.0
var wanted: Wanted
var graph := TrafficLanes.new()
var cars: Array[PoliceCar] = []
var _tick := 0.0
var _spawn_wait := 0.0
var _block_wait := 0.0
var _lane_keys: Array[Vector2i] = []
var _scan_key := 0
var _scan_lane := 0
## Includes decisions and spawn selection, excludes vehicle physics/rendering.
var decision_usec := 0
var decision_frames := 0


func _ready() -> void:
	if not wanted.city:
		return
	wanted.city.traffic_lanes_changed.connect(_lanes_changed)
	var initial := wanted.city.traffic_lanes()
	for key: Vector2i in initial:
		var data: Array = initial[key]
		_lanes_changed(key, data[0], data[1])


func _lanes_changed(key: Vector2i, lanes: Array[PackedVector3Array], info: PackedFloat32Array) -> void:
	graph.set_tile(key, lanes, info)
	_lane_keys.assign(graph.tiles.keys())


static func cap(stars: int) -> int:
	return clampi(stars - 1, 0, 4)


func _physics_process(delta: float) -> void:
	if wanted.hero.frozen or not wanted.enabled or (wanted.hud and wanted.hud.get_parent().has_node("LoadingScreen")):
		return
	decision_frames += 1
	_tick += delta
	if _tick < THINK_INTERVAL:
		return
	var start := Time.get_ticks_usec()
	var elapsed := _tick
	_tick = 0.0
	advance(elapsed)
	decision_usec += Time.get_ticks_usec() - start
	if decision_frames >= 300 and LaunchOptions.has("police_profile"):
		print("[police cars] decisions %.3f ms/frame, %d cars" % [decision_usec / 1000.0 / decision_frames, cars.size()])
		decision_frames = 0
		decision_usec = 0


## Public step supports deterministic synthetic streets without streamed tiles.
func advance(delta: float) -> void:
	_spawn_wait -= delta
	_block_wait -= delta
	var hero := wanted.hero
	var pursuing := 0
	var blocks := 0
	for car in cars.duplicate():
		if not is_instance_valid(car) or not car.is_in_group("police_cars"):
			cars.erase(car)
			continue
		var at := WorldOrigin.to_world(car.global_position)
		if car.driver:
			continue
		if wanted.stars == 0 or (not car.roadblock and pursuing >= cap(wanted.stars)) \
				or (car.roadblock and wanted.stars < 4) \
				or (at.distance_to(hero.world_position()) > DESPAWN_RANGE and hidden(at)):
			car.queue_free()
			cars.erase(car)
			continue
		if car.roadblock:
			blocks += 1
		else:
			pursuing += 1
		think(car, delta)
	if wanted.searching or not wanted.city or not wanted.encounters:
		return
	if pursuing < cap(wanted.stars) and _spawn_wait <= 0.0:
		_spawn_wait = 2.0
		_spawn_patrol(false)
	if wanted.stars >= 4 and hero.mode.name == &"Drive" and blocks == 0 and _block_wait <= 0.0:
		if _spawn_patrol(true):
			_block_wait = 25.0


## Camera frustum plus world occlusion prevents visible reinforcements popping in.
func hidden(at: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera == null or not camera.is_position_in_frustum(WorldOrigin.to_local(at) + Vector3.UP) \
		or not wanted._clear_sight(WorldOrigin.to_world(camera.global_position), at)


func _spawn_patrol(block: bool) -> bool:
	if _lane_keys.is_empty():
		return false
	var hero := wanted.hero
	# A rotating cursor bounds candidate work even in dense midtown tiles.
	for attempt in 24:
		_scan_key = posmod(_scan_key, _lane_keys.size())
		var lanes: Array = graph.tiles.get(_lane_keys[_scan_key], [])
		if _scan_lane >= lanes.size():
			_scan_key = (_scan_key + 1) % _lane_keys.size()
			_scan_lane = 0
			continue
		var lane: TrafficLanes.Lane = lanes[_scan_lane]
		_scan_lane += 1
		var d := lane.length * 0.5
		var at := lane.point_on(lane.segment_at(d, 0), d)
		var offset := at - hero.world_position()
		if offset.length() < 45.0 or offset.length() > 170.0 or not wanted.city.has_collision_at(at) or not hidden(at):
			continue
		if block and (hero.velocity.length() < 3.0 or hero.velocity.normalized().dot(offset.normalized()) < 0.65):
			continue
		var ground := wanted.city.ground_height_at(at, EncounterDirector.GROUND_SEARCH)
		if not is_finite(ground):
			continue
		at.y = ground + 0.12
		var yaw := lane.yaws[lane.segment_at(d, 0)]
		if block:
			var side := Vector3(cos(yaw), 0, -sin(yaw))
			if not _free_spot(at - side * 2.4, yaw + PI * 0.5) or not _free_spot(at + side * 2.4, yaw + PI * 0.5):
				continue
			spawn(at - side * 2.4, yaw + PI * 0.5, true)
			spawn(at + side * 2.4, yaw + PI * 0.5, true)
		else:
			if not _free_spot(at, yaw):
				continue
			var car := spawn(at, yaw, false)
			car.lane = lane
			car.lane_distance = d
		return true
	return false


func _free_spot(at: Vector3, yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.3, 4.4)
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), WorldOrigin.to_local(at) + Vector3.UP * 0.85)
	query.collision_mask = 1 | DriveVehicle.LAYER
	return wanted.hero.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func spawn(at: Vector3, yaw: float, block := false) -> PoliceCar:
	var car := wanted.encounters.spawn_police_car(at, yaw, wanted.hero, block)
	car.last_known = wanted.hero.world_position()
	cars.append(car)
	return car


func think(car: PoliceCar, delta: float) -> void:
	var hero := wanted.hero
	if car.driver or car.deployed or car.health <= 0.0:
		return
	var at := WorldOrigin.to_world(car.global_position)
	var distance := at.distance_to(hero.world_position())
	if not wanted.searching:
		car.last_known = hero.world_position()
	if car.roadblock:
		if distance < 25.0 and hero.mode.name != &"Drive":
			_deploy(car)
		return
	if car.lane and car.lane.removed:
		car.lane = null
	var target := car.last_known
	if wanted.searching:
		# Cruise a small circuit at the last sighting, never follow a hidden hero.
		var phase := Time.get_ticks_msec() * 0.00012 + car.net_id % 6
		target += Vector3(sin(phase), 0, cos(phase)) * 22.0
	elif distance < 45.0 and hero.mode.name == &"Drive":
		var side := Vector3(cos(hero.facing), 0, -sin(hero.facing))
		if car.net_id % 2 == 0:
			target += hero.velocity * 0.45 + side * 2.3
		else:
			target += hero.velocity * 0.1
	if distance > 45.0 or wanted.searching:
		target = _lane_target(car, target)
	var toward := target - at
	toward.y = 0.0
	var angle := wrapf(atan2(toward.x, toward.z) - car.heading, -PI, PI)
	var speed := 22.0 if distance > 45.0 else 28.0
	if wanted.searching:
		speed = 7.0
	if absf(angle) > 0.5:
		speed = minf(speed, 7.0)
	if not wanted.searching and hero.mode.name != &"Drive" and distance < 22.0:
		speed = clampf((distance - 10.0) * 1.2, 0.0, 12.0)
		if distance < 16.0 and car.velocity.length() < 2.0:
			_deploy(car)
			return
	car.stuck_time = car.stuck_time + delta if car.velocity.length() < 1.0 and speed > 3.0 else 0.0
	if car.stuck_time > 2.0:
		car.reverse_time = 1.4
		car.stuck_time = 0.0
	car.controls.jump_held = speed < 0.2
	car.controls.stick = Vector2(clampf(-angle * 1.8, -1, 1), -speed / DriveVehicle.TOP_SPEED)
	if car.reverse_time > 0.0:
		car.reverse_time -= delta
		car.controls.stick = Vector2(clampf(angle, -1, 1), 0.7)


func _lane_target(car: PoliceCar, destination: Vector3) -> Vector3:
	if car.lane == null:
		return destination
	var lane := car.lane
	var at := WorldOrigin.to_world(car.global_position)
	# Project onto a few segments around progress, rather than searching all roads.
	var segment := lane.segment_at(car.lane_distance, 0)
	if segment < lane.points.size() - 2 and car.lane_distance >= lane.along[segment + 1] - 1.0:
		segment += 1
	var nearest := Geometry3D.get_closest_point_to_segment(at, lane.points[segment], lane.points[segment + 1])
	car.lane_distance = maxf(car.lane_distance, lane.along[segment] + nearest.distance_to(lane.points[segment]))
	if car.lane_distance >= lane.length - 10.0:
		var best: TrafficLanes.Lane
		var score := INF
		for next: TrafficLanes.Lane in graph.leaving(lane.to_node):
			var value := next.points[next.points.size() - 1].distance_squared_to(destination)
			if value < score:
				score = value
				best = next
		if best:
			car.lane = best
			car.lane_distance = 0.0
			lane = best
	var ahead := minf(lane.length, car.lane_distance + 10.0)
	return lane.point_on(lane.segment_at(ahead, 0), ahead)


func _deploy(car: PoliceCar) -> void:
	car.deployed = true
	car.ai_controlled = false
	car.velocity = Vector3.ZERO
	if wanted.encounters:
		var side := Vector3(cos(car.heading), 0, -sin(car.heading)) * 1.8
		for sign_value: float in [-1.0, 1.0]:
			var at := WorldOrigin.to_world(car.global_position) + side * sign_value
			wanted.encounters.spawn_police(at, wanted.hero, wanted.stars)
