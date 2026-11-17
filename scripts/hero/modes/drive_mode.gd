class_name DriveMode
extends HeroMode
## Converts a nearby traffic slot into a car, and keeps the driver at its seat.
## Car position uses the hero's ordinary snapshot; model/paint/seed are plain state.

var car: DriveVehicle
var _old_layer := 0
var _old_mask := 0
var _hint: Label
var _starter_pending := true


func interact() -> void:
	if hero.mode == self:
		if _leave_car():
			hero.set_mode(&"OnFoot")
		return
	if hero.mode.name != &"OnFoot":
		return
	var nearest: DriveVehicle
	var distance := 3.5
	for parked: DriveVehicle in hero.get_tree().get_nodes_in_group("drive_cars"):
		var reach := parked.global_position.distance_to(hero.global_position)
		if parked.driver == null and not parked.ai_controlled and parked.health > 0.0 and reach < distance:
			nearest = parked
			distance = reach
	if nearest:
		car = nearest
		if car is PoliceCar and car.is_in_group("police_cars"):
			Combat.report_crime(&"steal_police_car", hero.world_position(), 2.0)
			car.abandon_pursuit()
	else:
		for traffic: Traffic in hero.get_tree().get_nodes_in_group("traffic"):
			car = traffic.take_car(hero.world_position(), 3.5)
			if car:
				Combat.report_crime(&"carjack", hero.world_position(), 1.0)
				Combat.raise_danger(hero.world_position(), 20.0)
				break
	if car:
		hero.set_mode(&"Drive")


func enter(_previous: StringName) -> void:
	car.driver = hero
	_old_layer = hero.collision_layer
	_old_mask = hero.collision_mask
	hero.collision_layer = 0
	hero.collision_mask = 0
	_follow_car()


func physics_update(delta: float) -> StringName:
	if not is_instance_valid(car):
		return &"OnFoot"
	car.drive(hero.input, delta)
	_follow_car()
	return &""


func _follow_car() -> void:
	hero.global_position = car.global_position
	hero.velocity = car.velocity
	hero.facing = wrapf(car.heading + PI, -PI, PI)


## Try both doors, then behind: never place the hero inside a wall or another car.
func _leave_car() -> bool:
	var size := PropMeshes.CAR_SIZES[car.model]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (hero.get_node("Body") as CollisionShape3D).shape
	query.collision_mask = 1 | DriveVehicle.LAYER
	for offset: Vector3 in [Vector3(size.y * 0.5 + 0.85, 0, 0), Vector3(-size.y * 0.5 - 0.85, 0, 0), Vector3(0, 0, -size.x * 0.5 - 0.9)]:
		var at := car.global_position + Basis(Vector3.UP, car.heading) * offset + Vector3.UP * 0.15
		query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
		if hero.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			hero.global_position = at
			hero.velocity = Vector3.ZERO
			return true
	return false


func exit() -> void:
	if is_instance_valid(car):
		car.driver = null
		# Switching by knockout/teleport must also put the hero outside the body.
		if hero.global_position.distance_to(car.global_position) < 0.5:
			_leave_car()
	hero.collision_layer = _old_layer
	hero.collision_mask = _old_mask
	car = null


## Remote cars only draw: their owner's hero snapshot already interpolates motion.
func show_remote(model: int, paint: float, seed: float, health := 100.0, roll := 0.0, pitch := 0.0) -> void:
	if hero.mode != self:
		if is_instance_valid(car):
			car.queue_free()
		car = null
		return
	if not is_instance_valid(car) or car.model != model:
		if is_instance_valid(car):
			car.queue_free()
		car = DriveVehicle.new()
		car.model = clampi(model, 0, PropMeshes.CAR_SIZES.size() - 1)
		car.paint = paint
		car.seed = seed
		car.puppet = true
		car.traffic = hero.get_tree().get_first_node_in_group("traffic") as Traffic
		hero.add_child(car)
	car.paint = paint
	car.seed = seed
	car.health = clampf(health, 0.0, 100.0)
	car.body_roll = roll
	car.body_pitch = pitch
	car.velocity = hero.velocity
	car.heading = hero.facing + PI
	car.global_position = hero.global_position
	car.rotation.y = car.heading
	car._draw()


func _ready() -> void:
	if hero.is_remote():
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -76.0
	_hint.offset_bottom = -38.0
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)


func _process(_delta: float) -> void:
	if hero.is_remote() or hero.mode == null:
		return
	if _starter_pending and not hero.frozen:
		_starter_pending = false
		if LaunchOptions.has("car"):
			var starter := DriveVehicle.new()
			starter.heading = hero.facing + PI
			starter.traffic = hero.get_tree().get_first_node_in_group("traffic") as Traffic
			hero.get_parent().add_child(starter)
			starter.global_position = hero.global_position + Vector3(cos(hero.facing), 0, -sin(hero.facing)) * 2.5
			if LaunchOptions.has("car_crash"):
				_seed_crash(starter)
	_hint.visible = not hero.frozen and (hero.mode == self or (hero.mode.name == &"OnFoot" and can_take_car()))
	var condition := "FIRE — GET OUT!" if hero.mode == self and car.health <= 0.0 else "Car %d%%" % roundi(car.health) if hero.mode == self else ""
	if Device.wants_touch_controls():
		_hint.text = "%d km/h • %s • Stick: drive   BRAKE: slide   EXIT" % [roundi(hero.horizontal_speed() * 3.6), condition] if hero.mode == self else "CAR: take a nearby car"
		return
	_hint.text = "%d km/h   •   %s   •   WASD drive   Space brake   G / R3 exit" % [roundi(hero.horizontal_speed() * 3.6), condition] if hero.mode == self else "G / R3: take a nearby car"


func _exit_tree() -> void:
	if is_instance_valid(car) and not car.puppet:
		car.driver = null


## Matches interact's reach and excludes occupied, burning and burned cars.
func can_take_car() -> bool:
	for parked: DriveVehicle in hero.get_tree().get_nodes_in_group("drive_cars"):
		if parked.driver == null and not parked.ai_controlled and parked.health > 0.0 and parked.global_position.distance_to(hero.global_position) < 3.5:
			return true
	for flow: Traffic in hero.get_tree().get_nodes_in_group("traffic"):
		if flow.nearest_car(hero.world_position(), 3.5) >= 0:
			return true
	return false


## Opt-in reproducible street crash: a worn starter and one stopped traffic row.
## Uses the same promotion, collision and explosion paths as ordinary traffic.
func _seed_crash(starter: DriveVehicle) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(starter):
		return
	starter.health = 40.0
	# The opt-in check needs one street, keeping software-rendered QA practical.
	if starter.traffic and starter.traffic.city:
		starter.traffic.city.load_distances.assign([100.0, 200.0, 700.0])
	var flow := Traffic.new()
	flow.max_cars = 1
	flow.city = starter.traffic.city if starter.traffic else null
	hero.get_parent().add_child(flow)
	flow.set_process(false)
	var at := WorldOrigin.to_world(starter.global_position)
	var forward := Vector3(sin(starter.heading), 0, cos(starter.heading))
	var target := at + forward * 38.0
	var lines: Array[PackedVector3Array] = [PackedVector3Array([at, at + forward * 100.0])]
	flow.set_tile_lanes(Vector2i(99999, 99999), lines, PackedFloat32Array([1, 2, 12, 0, 1, -1, 0]))
	var lane: TrafficLanes.Lane = flow.lanes.tiles[Vector2i(99999, 99999)][0]
	flow._add_car(lane, 40.35, 0, target, 0, 100, false)
	flow._v[0] = 0.0
	flow._draw()
	var started := Time.get_ticks_usec()
	for i in 1000:
		flow.solidify_sweep(starter.global_position, forward * 0.5, PropMeshes.CAR_SIZES[starter.model], starter.heading)
	print("[car-check] nearby query average %.4f ms; stopped traffic 38 m ahead" % ((Time.get_ticks_usec() - started) / 1000000.0))
