class_name DriveVehicle
extends CharacterBody3D
## A small sliding car body, using the traffic mesh and its per-instance appearance.
## Only occupied cars run controls; abandoned ones coast and can be pushed.

const LAYER := 64
const TOP_SPEED := 30.0
var model := 0
var paint := 0.0
var seed := 0.0
## Shader yaw faces +Z, whereas hero facing faces -Z.
var heading := 0.0
var driver: Hero
var puppet := false
var traffic: Traffic
var _mesh: MultiMesh
var _roll := 0.0
var _braking := false


func _ready() -> void:
	collision_layer = 0 if puppet else LAYER
	collision_mask = 0 if puppet else 1 | LAYER
	floor_snap_length = 0.65
	floor_stop_on_slope = true
	wall_min_slide_angle = 0.0
	if not puppet:
		add_to_group("floating")
		add_to_group("drive_cars")
	var size := PropMeshes.CAR_SIZES[model]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.y, size.z, size.x)
	shape.shape = box
	shape.position.y = size.z * 0.5 + 0.08
	add_child(shape)
	_mesh = MultiMesh.new()
	_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_mesh.use_colors = true
	_mesh.use_custom_data = true
	_mesh.mesh = PropMeshes.car()
	_mesh.instance_count = 1
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = _mesh
	visual.material_override = traffic._car_material() if traffic else _own_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.custom_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 12, 30))
	add_child(visual)
	_draw()


func _physics_process(delta: float) -> void:
	if puppet or driver:
		return
	velocity.x = move_toward(velocity.x, 0.0, delta * 4.0)
	velocity.z = move_toward(velocity.z, 0.0, delta * 4.0)
	_step(delta)
	var camera := get_viewport().get_camera_3d()
	if camera and global_position.distance_to(camera.global_position) > 420.0:
		queue_free()


## Steering follows the car, independent of the orbit camera; S brakes then reverses.
func drive(input: HeroInput, delta: float) -> void:
	var forward := Vector3(sin(heading), 0.0, cos(heading))
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.dot(forward)
	var throttle := -input.stick.y
	_braking = input.jump_held or throttle * speed < -0.5
	var acceleration := 16.0 if _braking else 8.0
	var target_speed := 0.0 if input.jump_held else throttle * (TOP_SPEED if throttle >= 0.0 else 9.0)
	speed = move_toward(speed, target_speed, acceleration * delta)
	if is_on_floor():
		var turn := input.stick.x * clampf(speed / 7.0, -1.0, 1.0)
		heading -= turn * (1.8 if input.jump_held else 1.2) * delta
	heading = wrapf(heading, -PI, PI)
	forward = Vector3(sin(heading), 0.0, cos(heading))
	var lateral := horizontal - forward * horizontal.dot(forward)
	lateral *= exp(-(1.2 if input.jump_held else 9.0) * delta)
	if input.jump_held:
		speed = move_toward(speed, 0.0, 12.0 * delta)
	horizontal = forward * speed + lateral
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var before := global_position
	_step(delta)
	_hit_people(before)


func _step(delta: float) -> void:
	rotation.y = heading
	velocity.y = maxf(velocity.y - 30.0 * delta, -55.0)
	var impact_speed := velocity.length()
	move_and_slide()
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if driver and absf(hit.get_normal().y) < 0.3 and Vector2(velocity.x, velocity.z).length() > 0.5:
			# Let a glancing impact guide the nose along the wall instead of repeatedly
			# losing forward speed to the same contact every tick.
			var along := atan2(velocity.x, velocity.z)
			heading = rotate_toward(heading, along, 2.5 * delta)
		var other := hit.get_collider() as DriveVehicle
		if other and other.driver == null:
			other.velocity += -hit.get_normal() * minf(impact_speed * 0.5, 10.0)
	_roll = fposmod(_roll + velocity.length() * delta / PropMeshes.CAR_WHEEL_RADII[model], TAU)
	_draw()


func _draw() -> void:
	var size := PropMeshes.CAR_SIZES[model]
	# The shader rotates vertices itself, so cancel the body's basis in the instance.
	_mesh.set_instance_transform(0, Transform3D(Basis(Vector3.UP, -heading).scaled_local(Vector3(size.x, size.z, size.x)), Vector3.ZERO))
	_mesh.set_instance_custom_data(0, Color(heading, model, seed, 16.0))
	_mesh.set_instance_color(0, Color(paint, 3.0 if _braking else 1.0, _roll, 0.0))


## Swept footprint catches people between ticks even at the 30 m/s speed limit.
func _hit_people(before: Vector3) -> void:
	if velocity.length() < 4.0:
		return
	var size := PropMeshes.CAR_SIZES[model]
	var start := before - global_position
	var push := velocity * 0.8 + Vector3.UP * 5.0
	for pedestrian: Pedestrian in get_tree().get_nodes_in_group("pedestrians"):
		if not pedestrian.is_knocked_down() and _contains_swept(WorldOrigin.to_local(pedestrian.world_position), start, size):
			pedestrian.take_hit(push, &"vehicular_assault")
	for thug: Thug in Combat.thugs:
		if not thug.is_down() and _contains_swept(thug.global_position, start, size):
			Combat.strike(thug.body_center(), 0.4, 100.0, push, true)


func _contains_swept(at: Vector3, start: Vector3, size: Vector3) -> bool:
	var relative := at - global_position
	var nearest := Geometry3D.get_closest_point_to_segment(relative, start, Vector3.ZERO)
	var local := Basis(Vector3.UP, -heading) * (relative - nearest)
	return absf(local.x) < size.y * 0.5 + 0.3 and absf(local.z) < size.x * 0.5 + 0.3 and absf(local.y) < size.z + 0.5


static func _own_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/car.gdshader")
	return material
