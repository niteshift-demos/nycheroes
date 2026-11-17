class_name StoryObjectives
extends Node3D
## Small mission-step runtime. Everything owned here is removed on retry or
## abandon. Absolute route positions and floating bodies survive city shifts.

var director: MissionDirector
var step: Dictionary
var car: DriveVehicle
var targets: Array[StoryVehicle] = []
var witness: Node3D
var witness_health := 100.0
var elapsed := 0.0
var ring_index := 0
var _escape_goal := 0
var _wave := 0.0
var _lost := 0.0
var _spawned := false
var _ring: MeshInstance3D


func begin(definition: Dictionary) -> void:
	step = definition
	if step.kind == "escape_wanted" and director.wanted:
		var stars := int(step.stars)
		director.wanted.set_stars(maxi(stars, director.wanted.stars))
		_escape_goal = maxi(0, director.wanted.stars - stars)
	if step.kind == "fly_through":
		_ring = MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = float(step.radius) - 1.0
		mesh.outer_radius = float(step.radius) + 1.0
		mesh.rings = 24
		mesh.ring_segments = 8
		_ring.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.GOLD
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring.material_override = material
		_ring.rotation.x = PI * 0.5
		_ring.add_to_group("floating")
		add_child(_ring)
		_ring.global_position = WorldOrigin.to_local(step.items[0])


func target() -> Vector3:
	if step.kind == "fly_through":
		return step.items[mini(ring_index, step.items.size() - 1)]
	if step.kind == "escape_wanted" and director.hero:
		return director.hero.world_position() + Vector3.UP * 100.0
	if is_instance_valid(car):
		return WorldOrigin.to_world(car.global_position)
	for vehicle in targets:
		if is_instance_valid(vehicle) and vehicle.relay_health > 0.0:
			return WorldOrigin.to_world(vehicle.global_position)
	return step.position


## Returns -1 for failure, 0 while active, 1 for completion.
func advance(delta: float, position: Vector3) -> int:
	var hero := director.hero
	if hero == null:
		return 0
	var driving := hero.mode.name == &"Drive"
	var drive := hero.get_mode(&"Drive") as DriveMode
	match String(step.kind):
		"drive_to":
			return int(driving and position.distance_to(step.position) <= float(step.radius))
		"steal_car":
			if not bool(step.marked):
				return int(driving)
			if not _spawned:
				car = _make_car(step.position, false)
				_spawned = car != null
			return int(_spawned and driving and drive.car == car)
		"chase", "destroy":
			if not _spawned and position.distance_to(step.position) < 160.0:
				var count := int(step.get("count", 1))
				for i in count:
					var vehicle := _make_car(step.position + Vector3(i * 9, 0, 0), true) as StoryVehicle
					if vehicle == null:
						for partial in targets:
							partial.free()
						targets.clear()
						return 0
					vehicle.fleeing = step.kind == "chase"
					vehicle.ai_controlled = vehicle.fleeing
					targets.append(vehicle)
				_spawned = true
			if not _spawned:
				return 0
			var down := 0
			for vehicle in targets:
				if not is_instance_valid(vehicle):
					return -1
				if vehicle.relay_health <= 0:
					down += 1
			if step.kind == "chase":
				_lost = _lost + delta if position.distance_to(target()) > 350 else 0.0
				if _lost > 8.0:
					return -1
			return int(down == targets.size())
		"escape_wanted":
			return int(director.wanted != null and director.wanted.stars <= _escape_goal)
		"fly_through":
			if hero.mode.name == &"Flight" and position.distance_to(target()) <= float(step.radius):
				ring_index += 1
				if ring_index == step.items.size():
					return 1
				_ring.global_position = WorldOrigin.to_local(target())
		"protect":
			if not _spawned:
				if position.distance_to(step.position) > 90.0 or not _ground_ready(step.position):
					return 0
				witness = Node3D.new()
				witness.add_to_group("floating")
				add_child(witness)
				witness.global_position = WorldOrigin.to_local(_ground(step.position))
				var mannequin: Node3D = load("res://scenes/npc/thug.tscn").instantiate()
				var model := mannequin.get_node("Model").duplicate() as Node3D
				mannequin.free()
				witness.add_child(model)
				NpcLook.paint_pedestrian(model)
				var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if player:
					player.play(&"Idle")
				var label := Label3D.new()
				label.text = "WITNESS · PROTECT"
				label.position.y = 2.7
				label.modulate = Color.CYAN
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				witness.add_child(label)
				_spawned = true
			if position.distance_to(step.position) > 100.0:
				_lost += delta
				if _lost > 10.0:
					return -1
			else:
				_lost = 0.0
				elapsed += delta
			_wave -= delta
			var alive := 0
			for thug in director.gang:
				if is_instance_valid(thug) and not thug.is_down():
					alive += 1
					if thug.global_position.distance_to(witness.global_position) < 3.0:
						witness_health -= delta * 7.0
			if witness_health <= 0.0:
				return -1
			if _wave <= 0.0 and alive < 5:
				_wave = 18.0
				var spawn := _ground(step.position + Vector3(16, 0, 8))
				var wave := director.encounters.spawn_gang(spawn, 2, Vector3.RIGHT, hero)
				for thug in wave:
					thug.story_victim = witness
				director.gang.append_array(wave)
			return int(elapsed >= float(step.duration))
	return 0


func status() -> String:
	match String(step.kind):
		"protect":
			return "  %ds · witness %d%%" % [maxi(0, ceili(float(step.duration) - elapsed)), maxi(0, ceili(witness_health))]
		"fly_through":
			return "  %d / %d" % [ring_index, step.items.size()]
		"chase":
			return "  %d m" % int(director.hero.world_position().distance_to(target())) if director.hero else ""
	return ""


func _ground_ready(position: Vector3) -> bool:
	return director.encounters != null and director.encounters.city.has_collision_at(position)


func _ground(position: Vector3) -> Vector3:
	var ground := director.encounters.city.ground_height_at(position, 5.0)
	if is_finite(ground):
		position.y = ground + WorldOrigin.offset.y + 0.15
	return position


func _make_car(position: Vector3, destructible: bool) -> DriveVehicle:
	if not _ground_ready(position):
		return null
	var city := director.encounters.city
	var best := INF
	var spot := position
	var along := Vector3.FORWARD
	for tile: Array in city.traffic_lanes().values():
		for lane: PackedVector3Array in tile[0]:
			for i in lane.size() - 1:
				var nearest := Geometry3D.get_closest_point_to_segment(position, lane[i], lane[i + 1])
				# Several authored props can project onto one lane point. Sample
				# nearby positions along that segment and keep their bodies apart.
				var offsets := PackedFloat32Array([0.0])
				if step.kind == "destroy":
					offsets = PackedFloat32Array([0.0, 9.0, -9.0, 18.0, -18.0])
				var direction := (lane[i + 1] - lane[i]).normalized()
				for offset in offsets:
					var point := Geometry3D.get_closest_point_to_segment(nearest + direction * offset, lane[i], lane[i + 1])
					if not _clear_of_targets(point):
						continue
					var distance := Vector2(point.x - position.x, point.z - position.z).length()
					if distance < best:
						best = distance
						spot = point.move_toward(lane[i + 1], 28.0) if step.kind == "chase" else point
						along = lane[i + 1] - lane[i]
	if best > 120.0:
		return null  # Wait for actual road lanes, never put a car in a building.
	var vehicle: DriveVehicle = StoryVehicle.new() if destructible else DriveVehicle.new()
	vehicle.model = CityTileDecoder.CAR_VAN if destructible else 0
	vehicle.paint = 1.0
	vehicle.heading = atan2(along.x, along.z)
	vehicle.traffic = get_tree().get_first_node_in_group("traffic") as Traffic
	if vehicle is StoryVehicle:
		vehicle.city = city
	add_child(vehicle)
	vehicle.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.25
	return vehicle


func _clear_of_targets(position: Vector3) -> bool:
	for vehicle in targets:
		if is_instance_valid(vehicle) and WorldOrigin.to_world(vehicle.global_position).distance_to(position) < 7.0:
			return false
	return true
