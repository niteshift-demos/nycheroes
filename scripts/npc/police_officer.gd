class_name PoliceOfficer
extends Thug
## Foot police share the thug movement, hit and replication paths, but only
## pursue their assigned wanted suspect. A departed suspect ends the pursuit.

var suspect_id := 0
var response_stars := 1
var _search_at := Vector3.ZERO
var recovery := AiRecovery.new()
var _detour := Vector3.ZERO


func setup(target: Hero, gang_index: int, angle: float) -> void:
	super.setup(target, gang_index, angle)
	_paint()


func setup_described(gang_index: int, facing_angle: float, health_left: float, down: bool) -> void:
	super.setup_described(gang_index, facing_angle, health_left, down)
	_paint()


func _paint() -> void:
	NpcLook.paint_police($Model, net_id, response_stars >= 5)
	# Uniforms and shield blips identify officers without a cloud of tiny,
	# aliased 3-D name tags over a ten-officer pursuit on a 360p phone.


func _nearest_hero() -> Hero:
	for candidate in Combat.heroes:
		var id := candidate.remote_id if candidate.is_remote() else Net.local_id()
		if id == suspect_id and candidate.wanted_stars > 0 and candidate.can_be_attacked():
			return candidate
	return null


func _physics_process(delta: float) -> void:
	var stamp := GtaTiming.begin()
	_policeofficer_timed_physics_process(delta)
	GtaTiming.end(&"officers", stamp)


func _policeofficer_timed_physics_process(delta: float) -> void:
	if frozen:
		return
	if not puppet and not is_down():
		var suspect := _nearest_hero()
		if suspect == null:
			queue_free()
			return
		hero = suspect
		var at := WorldOrigin.to_world(global_position)
		var chasing := state == State.CHASE or hero.wanted_searching
		if recovery.advance(at, delta, chasing and global_position.distance_to(hero.global_position) > 5.0, _facing):
			var toward := WorldOrigin.to_local(_search_at) - global_position if hero.wanted_searching else hero.global_position - global_position
			toward.y = 0.0
			var normal := -toward.normalized()
			for i in get_slide_collision_count():
				if absf(get_slide_collision(i).get_normal().y) < 0.3:
					normal = get_slide_collision(i).get_normal()
					break
			_detour = (normal.cross(Vector3.UP) * recovery.turn + normal * 0.4).normalized()
			var camera := get_viewport().get_camera_3d()
			if recovery.attempts >= 3 and at.distance_to(hero.world_position()) > 25.0 \
					and (camera == null or not camera.is_position_in_frustum(global_position + Vector3.UP)):
				Combat.unregister(self)
				queue_free()
				return
		if not hero.wanted_searching:
			_search_at = hero.world_position()
		if hero.wanted_searching:
			_release_attack_slot()
			state = State.IDLE
			var toward := WorldOrigin.to_local(_search_at) - global_position
			toward.y = 0.0
			_face(toward)
			velocity = toward.normalized() * minf(3.0, toward.length()) + Vector3.UP * (velocity.y - Hero.GRAVITY * delta)
			if recovery.reverse_time > 0.0:
				velocity.x = _detour.x * 3.0
				velocity.z = _detour.z * 3.0
			move_and_slide()
			_model.rotation.y = _facing
			_animate_movement(Vector2(velocity.x, velocity.z).length())
			return
		_cooldown = minf(_cooldown, 0.6 if response_stars >= 3 else 1.5)
	super._physics_process(delta)


func _surround_velocity(reachable: bool) -> Vector3:
	if recovery.reverse_time > 0.0:
		return _detour * RUN_SPEED
	return super._surround_velocity(reachable) * (1.25 if response_stars >= 3 else 1.0)


func _land_punch(flat: Vector3, distance: float, reachable: bool) -> void:
	var forward := Vector3(-sin(_facing), 0.0, -cos(_facing))
	if reachable and distance <= ATTACK_RANGE + 0.4 and forward.dot(flat.normalized()) >= 0.5:
		Combat.hurt_hero(hero, 18.0 if response_stars >= 5 else 10.0, forward * 3.0)
