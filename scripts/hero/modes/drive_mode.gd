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
		if parked.driver == null and reach < distance:
			nearest = parked
			distance = reach
	if nearest:
		car = nearest
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
func show_remote(model: int, paint: float, seed: float) -> void:
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
	_hint.visible = not hero.frozen and hero.mode.name in [&"OnFoot", &"Drive"]
	if Device.wants_touch_controls():
		_hint.text = "%d km/h   •   Stick: drive   BRAKE: slide   EXIT: get out" % roundi(hero.horizontal_speed() * 3.6) if hero.mode == self else "CAR: take a nearby car"
		return
	_hint.text = "%d km/h   •   WASD drive   Space handbrake   G / R3 exit" % roundi(hero.horizontal_speed() * 3.6) if hero.mode == self else "G / R3: take a nearby car"


func _exit_tree() -> void:
	if is_instance_valid(car) and not car.puppet:
		car.driver = null
