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
## AI supplies the same input as a driver, without blaming NPC impacts on the hero.
var ai_controlled := false
var traffic: Traffic
var _mesh: MultiMesh
var _roll := 0.0
var _braking := false
## Zero health burns for three seconds, leaving time to get out before the blast.
var health := 100.0
## NPC crashes must not blame the hero; hero attacks and driven impacts do.
var _hero_damage := false
var burn_time := 0.0
var exploded := false
var slip := 0.0
var body_roll := 0.0
var body_pitch := 0.0
## Retain the last upward road velocity across a crest; a box otherwise flattens it.
var _ramp_rise := 0.0
var _impact_cooldown := 0.0
var _hood_cooldown := 0.0
var _material: ShaderMaterial
var _engine: LoopVoice
var _tyres: LoopVoice


func _ready() -> void:
	collision_layer = 0 if puppet else LAYER
	collision_mask = 0 if puppet else 1 | LAYER
	floor_snap_length = 0.25
	floor_constant_speed = false
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
	_material = (traffic._car_material() if traffic else _own_material()).duplicate() as ShaderMaterial
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.custom_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 12, 30))
	add_child(visual)
	_engine = _loop(&"engine", -10.0)
	_tyres = _loop(&"tyre_screech", -15.0)
	if paint == PoliceLivery.PAINT:
		add_child(PoliceLivery.new())
	_draw()


func _physics_process(delta: float) -> void:
	if puppet or driver or ai_controlled:
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
	if health <= 0.0:
		throttle = 0.0
	if not is_on_floor():
		acceleration = 0.0
	var target_speed := 0.0 if input.jump_held else throttle * (TOP_SPEED if throttle >= 0.0 else 9.0)
	var old_speed := speed
	speed = move_toward(speed, target_speed, acceleration * delta)
	if is_on_floor():
		var turn := input.stick.x * clampf(speed / 7.0, -1.0, 1.0)
		heading -= turn * (1.8 if input.jump_held else lerpf(1.5, 0.8, absf(speed) / TOP_SPEED)) * delta
	heading = wrapf(heading, -PI, PI)
	forward = Vector3(sin(heading), 0.0, cos(heading))
	var lateral := horizontal - forward * horizontal.dot(forward)
	slip = lateral.length()
	# Grip recovers smoothly after a slide, without snapping the tail to the nose.
	var grip := 1.2 if input.jump_held else lerpf(10.0, 4.0, smoothstep(2.0, 12.0, slip))
	lateral *= exp(-grip * delta) if is_on_floor() else 1.0
	body_roll = lerpf(body_roll, -input.stick.x * minf(absf(speed) / TOP_SPEED, 1.0) * 0.07, 1.0 - exp(-6.0 * delta))
	body_pitch = lerpf(body_pitch, clampf((speed - old_speed) / maxf(delta, 0.001) * 0.006, -0.08, 0.06), 1.0 - exp(-5.0 * delta))
	if input.jump_held:
		speed = move_toward(speed, 0.0, 12.0 * delta)
	horizontal = forward * speed + lateral
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var before := global_position
	_step(delta)
	if driver:
		_hit_people(before)


func _step(delta: float) -> void:
	rotation.y = heading
	velocity.y = maxf(velocity.y - 30.0 * delta, -55.0)
	for flow: Traffic in get_tree().get_nodes_in_group("traffic"):
		flow.solidify_sweep(global_position, velocity * delta, PropMeshes.CAR_SIZES[model], heading)
	var incoming := velocity
	move_and_slide()
	if is_on_floor() and not is_on_wall():
		var horizontal := Vector3(velocity.x, 0, velocity.z)
		var road_speed := Vector2(incoming.x, incoming.z).length()
		# Projecting a fresh horizontal vector onto a slope every tick loses speed.
		horizontal = horizontal.normalized() * road_speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		var rise := get_real_velocity().y
		if _ramp_rise > 1.0 and rise < _ramp_rise * 0.25 and road_speed > 8.0:
			velocity.y = minf(_ramp_rise, 8.0)
			_ramp_rise = 0.0
		else:
			_ramp_rise = maxf(rise, 0.0)
	elif _ramp_rise > 1.0:
		velocity.y = maxf(velocity.y, minf(_ramp_rise, 8.0))
		_ramp_rise = 0.0
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var normal := hit.get_normal()
		var other := hit.get_collider() as DriveVehicle
		# Physics reports a newly promoted/shifted body's teleport as velocity.
		# Plain car velocity survives origin shifts and gives the actual impact.
		var relative := incoming - (other.velocity if other else Vector3.ZERO)
		var closing := maxf(0.0, -relative.dot(normal))
		if (driver or ai_controlled) and absf(normal.y) < 0.3 and Vector2(velocity.x, velocity.z).length() > 0.5:
			heading = rotate_toward(heading, atan2(velocity.x, velocity.z), 2.5 * delta)
		if closing > 3.0 and _impact_cooldown <= 0.0 and (normal.y < 0.7 or incoming.y < -5.0):
			_impact_cooldown = 0.35
			var hero_impact := driver != null and incoming.dot(normal) < -3.0
			var other_hero_impact := other != null and other.driver != null and other.velocity.dot(normal) > 3.0
			take_hit((closing - 3.0) * 2.6, Vector3.ZERO, hero_impact or other_hero_impact or _hero_damage)
			Combat.impact.emit(hit.get_position(), minf(closing / 25.0, 1.0))
			GameAudio.play(&"car_crash", hit.get_position())
			if Combat.effects:
				Combat.effects.car_sparks(hit.get_position(), normal, closing)
			if other:
				other.take_hit((closing - 3.0) * 2.0, -normal * minf(closing * 0.65, 20.0) + Vector3.UP, hero_impact or _hero_damage)
			velocity *= 0.72
	_roll = fposmod(_roll + velocity.length() * delta / PropMeshes.CAR_WHEEL_RADII[model], TAU)
	_draw()


func _draw() -> void:
	if _material:
		_material.set_shader_parameter("damage_amount", 1.0 - health / 100.0)
		_material.set_shader_parameter("body_tilt", Vector2(body_roll, body_pitch))
	var size := PropMeshes.CAR_SIZES[model]
	# The shader rotates vertices itself, so cancel the body's basis in the instance.
	_mesh.set_instance_transform(0, Transform3D(Basis(Vector3.UP, -heading).scaled_local(Vector3(size.x, size.z, size.x)), Vector3.ZERO))
	_mesh.set_instance_custom_data(0, Color(heading, model, seed, 16.0))
	_mesh.set_instance_color(0, Color(0.0 if paint == PoliceLivery.PAINT else paint, 3.0 if _braking else 1.0, _roll, 0.0))


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
			Combat.strike(thug.body_center(), 0.4, 100.0, push, true, false)


func _contains_swept(at: Vector3, start: Vector3, size: Vector3) -> bool:
	var relative := at - global_position
	var nearest := Geometry3D.get_closest_point_to_segment(relative, start, Vector3.ZERO)
	var local := Basis(Vector3.UP, -heading) * (relative - nearest)
	return absf(local.x) < size.y * 0.5 + 0.3 and absf(local.z) < size.x * 0.5 + 0.3 and absf(local.y) < size.z + 0.5


static func _own_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/car.gdshader")
	return material


## Damage is separate from movement so punches, crashes and blasts share one path.
func take_hit(damage: float, push: Vector3, blame_hero := true) -> void:
	if puppet:
		return
	velocity += push.limit_length(45.0)
	if exploded:
		return
	_hero_damage = _hero_damage or (blame_hero and damage > 0.0)
	health = maxf(0.0, health - damage)
	if health <= 0.0 and burn_time <= 0.0:
		burn_time = 3.0
	_draw()


func _process(delta: float) -> void:
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	_hood_cooldown -= delta
	if health < 40.0 and not exploded and _hood_cooldown <= 0.0:
		_hood_cooldown = 0.3
		if Combat.effects:
			var hood := global_position + Basis(Vector3.UP, heading) * Vector3(0, 1.0, PropMeshes.CAR_SIZES[model].x * 0.3)
			Combat.effects.car_smoke(hood, health <= 0.0)
	if not puppet and burn_time > 0.0:
		burn_time -= delta
		if burn_time <= 0.0:
			explode()
	if not GameAudio.can_play():
		_engine.silence()
		_tyres.silence()
		return
	var speed := velocity.length()
	_engine.target = (0.5 + minf(speed / TOP_SPEED, 0.5)) if (driver or puppet or ai_controlled) and health > 0.0 else 0.0
	_engine.pitch = 0.75 + minf(speed / TOP_SPEED, 1.0) * 1.5
	_engine.update(delta, 5.0)
	_tyres.target = clampf((slip - 2.0) / 6.0, 0.0, 1.0) if (driver or ai_controlled) and is_on_floor() else 0.0
	_tyres.update(delta, 10.0)


## Burned cars stay solid but cannot be restarted. Blast damage reaches the driver.
func explode() -> void:
	if exploded or puppet:
		return
	exploded = true
	ai_controlled = false
	health = 0.0
	burn_time = 0.0
	body_pitch = -0.1
	var occupant := driver
	if is_instance_valid(occupant):
		occupant.set_mode(&"OnFoot")
		Combat.hurt_hero(occupant, 65.0, Vector3.UP * 12.0)
	Combat.shockwave(global_position, 9.0, 80.0, 18.0, _hero_damage)
	for hero: Hero in Combat.heroes:
		if hero != occupant and not hero.is_remote() and hero.global_position.distance_to(global_position) < 9.0:
			Combat.hurt_hero(hero, 45.0, (hero.global_position - global_position).normalized() * 12.0 + Vector3.UP * 6.0)
	for pedestrian: Pedestrian in get_tree().get_nodes_in_group("pedestrians"):
		if _hero_damage and pedestrian.global_position.distance_to(global_position) < 20.0:
			Combat.report_crime(&"car_explosion", WorldOrigin.to_world(global_position), 1.5)
			break
	GameAudio.play(&"slam", global_position)
	if Combat.effects:
		Combat.effects.car_sparks(global_position + Vector3.UP, Vector3.UP, 30.0)
		Combat.effects.car_smoke(global_position + Vector3.UP, true)
	_draw()


func _loop(sound: StringName, db: float) -> LoopVoice:
	var player := AudioStreamPlayer3D.new()
	var files := SoundBank.streams(sound)
	player.stream = files[0] if not files.is_empty() else null
	player.bus = &"SFX"
	player.unit_size = 8.0
	player.max_distance = 65.0
	add_child(player)
	return LoopVoice.new(player, db, 0.5)


static func box_distance(point: Vector3, at: Vector3, size: Vector3, yaw: float) -> float:
	var local := Basis(Vector3.UP, -yaw) * (point - at - Vector3.UP * size.z * 0.5)
	return (local.abs() - Vector3(size.y, size.z, size.x) * 0.5).max(Vector3.ZERO).length()


## Continuous separating-axis test, including elevation, avoids fast heroes tunneling.
static func swept_overlap(at: Vector3, motion: Vector3, size: Vector3, yaw: float, other: Vector3, other_size: Vector3, other_yaw: float) -> bool:
	var a := Basis(Vector3.UP, yaw)
	var b := Basis(Vector3.UP, other_yaw)
	var offset := at + Vector3.UP * size.z * 0.5 - other - Vector3.UP * other_size.z * 0.5
	var enter := 0.0
	var leave := 1.0
	for axis: Vector3 in [a.x, a.z, b.x, b.z, Vector3.UP]:
		var radius := (absf(axis.dot(a.x)) * size.y + absf(axis.dot(a.z)) * size.x + absf(axis.y) * size.z + absf(axis.dot(b.x)) * other_size.y + absf(axis.dot(b.z)) * other_size.x + absf(axis.y) * other_size.z) * 0.5 + 0.05
		var distance := offset.dot(axis)
		var speed := motion.dot(axis)
		if absf(speed) < 0.0001:
			if absf(distance) > radius:
				return false
		else:
			var first := (-radius - distance) / speed
			var last := (radius - distance) / speed
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter > leave:
				return false
	return true
