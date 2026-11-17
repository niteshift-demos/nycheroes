class_name CombatEffects
extends Node3D
## Visual effects for fights: blood sprays, blood pools under bodies, and the
## shockwave ring and dust of a ground slam. Lives in the "floating" group so
## effects stay put when the world origin shifts.

const MAX_POOLS := 40
const BLOOD_POOL_SHADER := preload("res://shaders/blood_pool.gdshader")
const SHOCKWAVE_SHADER := preload("res://shaders/shockwave_ring.gdshader")

var _drop_mesh: SphereMesh
var _dust_mesh: QuadMesh
var _dust_fade: Gradient
var _plane_mesh: PlaneMesh
var _pool_material: ShaderMaterial
var _pools: Array[Node3D] = []
var _fire_mesh: QuadMesh
var _debris_mesh: BoxMesh
## Cap simultaneous blasts so chain reactions cannot flood mobile fill rate.
var _explosions: Array[Node3D] = []


func _ready() -> void:
	add_to_group("floating")
	Combat.effects = self
	_drop_mesh = _sphere(0.035, _material(Color(0.42, 0.01, 0.01), 0.25))
	_dust_mesh = _soft_puff()
	_fire_mesh = _soft_puff()
	var fire_material := _fire_mesh.material as StandardMaterial3D
	fire_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.18, 0.12, 0.42)
	_debris_mesh.material = _material(Color("282524"), 1.0)
	_dust_fade = Gradient.new()
	_dust_fade.set_color(0, Color(0.78, 0.75, 0.68, 0.55))
	_dust_fade.set_color(1, Color(0.78, 0.75, 0.68, 0.0))
	_plane_mesh = PlaneMesh.new()
	_plane_mesh.size = Vector2.ONE
	_pool_material = ShaderMaterial.new()
	_pool_material.shader = BLOOD_POOL_SHADER


## A spray of blood droplets from `at`, mostly along `direction`.
func blood_burst(at: Vector3, direction: Vector3, amount := 1.0) -> void:
	var spray := _burst(_drop_mesh, at, int(14 * amount) + 6, 0.9)
	spray.direction = direction if direction.length_squared() > 0.01 else Vector3.UP
	spray.spread = 40.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.0 + 4.0 * amount
	spray.gravity = Vector3(0.0, -18.0, 0.0)
	spray.scale_amount_min = 0.6
	spray.scale_amount_max = 1.8


## A pool of blood spreading on the ground below `at`.
func blood_pool(at: Vector3, size := 1.6) -> void:
	var ground: Variant = _ground_below(at)
	if ground == null:
		return
	var pool := MeshInstance3D.new()
	pool.mesh = _plane_mesh
	pool.material_override = _pool_material
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.rotation.y = randf() * TAU
	pool.scale = Vector3(0.1, 1.0, 0.1)
	add_child(pool)
	pool.global_position = ground + Vector3.UP * 0.02
	var final_scale := Vector3(size * randf_range(0.8, 1.2), 1.0, size * randf_range(0.8, 1.2))
	create_tween().tween_property(pool, "scale", final_scale, 3.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_pools.append(pool)
	if _pools.size() > MAX_POOLS:
		_pools.pop_front().queue_free()


## A ground slam: an expanding ring and a burst of dust.
func shockwave(at: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _plane_mesh
	var material := ShaderMaterial.new()
	material.shader = SHOCKWAVE_SHADER
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.5, 1.0, 0.5)
	add_child(ring)
	ring.global_position = at + Vector3.UP * 0.15
	var tween := create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(radius * 2.4, 1.0, radius * 2.4), 0.45).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("strength", value), 1.0, 0.0, 0.45)
	tween.chain().tween_callback(ring.queue_free)

	var dust := _burst(_dust_mesh, at + Vector3.UP * 0.5, int(radius * 5.0), 1.4)
	dust.direction = Vector3.UP
	dust.spread = 85.0
	dust.flatness = 0.8
	dust.initial_velocity_min = radius * 1.2
	dust.initial_velocity_max = radius * 2.2
	dust.damping_min = radius * 1.5
	dust.damping_max = radius * 2.5
	dust.gravity = Vector3(0.0, 0.5, 0.0)
	dust.scale_amount_min = 1.5
	dust.scale_amount_max = 3.5
	dust.color_ramp = _dust_fade


func _burst(mesh: Mesh, at: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.mesh = mesh
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.global_position = at
	particles.local_coords = true
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


func _ground_below(at: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 6.0, Combat.WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else null


## A camera-facing quad with a soft round falloff, tinted by the particle color.
static func _soft_puff() -> QuadMesh:
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	var mesh := QuadMesh.new()
	mesh.material = material
	return mesh


static func _sphere(radius: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material
	return mesh


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


## A bounded burst of hot metal and chips; reuses the fight particle lifetime path.
func car_sparks(at: Vector3, direction: Vector3, speed: float) -> void:
	var mesh := _sphere(0.055, _material(Color(1.0, 0.48, 0.07), 0.7))
	var sparks := _burst(mesh, at, 18, 0.7)
	sparks.direction = direction
	sparks.spread = 65.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = minf(speed, 18.0)
	sparks.gravity = Vector3(0, -20, 0)


## Small CPU puffs keep hood smoke/fire affordable on WebGL and phones.
func car_smoke(at: Vector3, burning: bool) -> void:
	var puff := _burst(_dust_mesh, at, 5, 1.6)
	puff.direction = Vector3.UP
	puff.spread = 18.0
	puff.initial_velocity_min = 1.5
	puff.initial_velocity_max = 3.0
	puff.gravity = Vector3(0, 0.8, 0)
	puff.scale_amount_min = 0.4
	puff.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.25, 0.02, 0.9) if burning else Color(0.18, 0.18, 0.18, 0.65))
	fade.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	fade.add_point(0.35, Color(0.12, 0.12, 0.12, 0.6))
	puff.color_ramp = fade


## Three bounded CPU bursts: expanding hot lobes, rising soot and tumbling
## metal. No GPU particles, scene texture reads, shadow maps or imported art.
func car_explosion(at: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	_explosions.append(root)
	if _explosions.size() > 3:
		var old: Node3D = _explosions.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var fire := _burst(_fire_mesh, at + Vector3.UP * 1.2, 18, 1.1)
	fire.direction = Vector3.UP
	fire.spread = 100.0
	fire.initial_velocity_min = 3.0
	fire.initial_velocity_max = 8.0
	fire.damping_min = 3.0
	fire.damping_max = 5.0
	fire.gravity = Vector3(0, 1.5, 0)
	fire.scale_amount_min = 3.0
	fire.scale_amount_max = 5.5
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.2))
	swell.add_point(Vector2(0.18, 1.0))
	swell.add_point(Vector2(1.0, 0.4))
	fire.scale_amount_curve = swell
	var heat := Gradient.new()
	heat.set_color(0, Color(1.0, 0.95, 0.65, 1.0))
	heat.add_point(0.2, Color(1.0, 0.5, 0.06, 1.0))
	heat.add_point(0.55, Color(0.8, 0.12, 0.01, 0.8))
	heat.set_color(1, Color(0.2, 0.02, 0.0, 0.0))
	fire.color_ramp = heat
	var smoke := _burst(_dust_mesh, at + Vector3.UP, 14, 3.2)
	smoke.direction = Vector3.UP
	smoke.spread = 55.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 5.0
	smoke.gravity = Vector3(0, 1.2, 0)
	smoke.scale_amount_min = 3.0
	smoke.scale_amount_max = 6.0
	var soot := Gradient.new()
	soot.set_color(0, Color(0.09, 0.07, 0.06, 0.15))
	soot.add_point(0.4, Color(0.14, 0.13, 0.12, 0.7))
	soot.set_color(1, Color(0.18, 0.17, 0.16, 0.0))
	smoke.color_ramp = soot
	var debris := _burst(_debris_mesh, at + Vector3.UP, 12, 1.8)
	debris.direction = Vector3.UP
	debris.spread = 75.0
	debris.initial_velocity_min = 6.0
	debris.initial_velocity_max = 14.0
	debris.gravity = Vector3(0, -20, 0)
	debris.angular_velocity_min = -400.0
	debris.angular_velocity_max = 400.0
	# Particles use global coordinates; reparent under a floating ancestor and
	# local particle transforms keep an in-flight burst attached through a shift.
	for particles: CPUParticles3D in [fire, smoke, debris]:
		particles.local_coords = true
		particles.reparent(root, true)
	var light := OmniLight3D.new()
	light.position.y = 2.0
	light.light_color = Color(1.0, 0.45, 0.08)
	light.light_energy = 5.0
	light.omni_range = 14.0
	light.shadow_enabled = false
	root.add_child(light)
	# A few mesh lobes give even a low-frame-rate browser an immediate flash;
	# CPU particle buffers can take their first simulation step a frame later.
	for offset: Vector3 in [Vector3(-1.4, 1.1, 0), Vector3(1.2, 1.5, 0.3), Vector3(0, 2.6, -0.4)]:
		var lobe := MeshInstance3D.new()
		lobe.mesh = _fire_mesh
		var glow := (_fire_mesh.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		glow.albedo_color = Color(1.0, 0.6, 0.08, 1.0)
		lobe.material_override = glow
		lobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lobe)
		lobe.position = offset
		lobe.scale = Vector3.ONE * 5.0
		var flare := root.create_tween().set_parallel()
		flare.tween_property(lobe, "scale", Vector3.ONE * 7.5, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flare.tween_property(glow, "albedo_color:a", 0.0, 1.0).set_delay(0.15)
		flare.chain().tween_callback(lobe.queue_free)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.24)
	tween.tween_callback(light.queue_free)
	tween.tween_interval(3.4)
	tween.tween_callback(func() -> void:
		_explosions.erase(root)
		if is_instance_valid(root):
			root.queue_free())
