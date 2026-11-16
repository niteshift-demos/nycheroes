class_name PoliceOfficer
extends Thug
## Foot police share the thug movement, hit and replication paths, but only
## pursue their assigned wanted suspect. A departed suspect ends the pursuit.

var suspect_id := 0
var response_stars := 1
var _search_at := Vector3.ZERO


func setup(target: Hero, gang_index: int, angle: float) -> void:
	super.setup(target, gang_index, angle)
	_paint()


func setup_described(gang_index: int, facing_angle: float, health_left: float, down: bool) -> void:
	super.setup_described(gang_index, facing_angle, health_left, down)
	_paint()


func _paint() -> void:
	NpcLook.paint_police($Model, net_id, response_stars >= 5)
	var tag := Label3D.new()
	tag.text = "NYPD" if response_stars < 5 else "NYPD • HEAVY"
	tag.position.y = 2.15
	tag.font_size = 24
	tag.pixel_size = 0.008
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.5, 0.72, 1.0)
	add_child(tag)


func _nearest_hero() -> Hero:
	for candidate in Combat.heroes:
		var id := candidate.remote_id if candidate.is_remote() else Net.local_id()
		if id == suspect_id and candidate.wanted_stars > 0 and candidate.can_be_attacked():
			return candidate
	return null


func _physics_process(delta: float) -> void:
	if not puppet and not is_down():
		var suspect := _nearest_hero()
		if suspect == null:
			queue_free()
			return
		hero = suspect
		if not hero.wanted_searching:
			_search_at = hero.world_position()
		if hero.wanted_searching:
			_release_attack_slot()
			state = State.IDLE
			var toward := WorldOrigin.to_local(_search_at) - global_position
			toward.y = 0.0
			_face(toward)
			velocity = toward.normalized() * minf(3.0, toward.length()) + Vector3.UP * (velocity.y - Hero.GRAVITY * delta)
			move_and_slide()
			_model.rotation.y = _facing
			_animate_movement(Vector2(velocity.x, velocity.z).length())
			return
		_cooldown = minf(_cooldown, 0.6 if response_stars >= 3 else 1.5)
	super._physics_process(delta)


func _surround_velocity(reachable: bool) -> Vector3:
	return super._surround_velocity(reachable) * (1.25 if response_stars >= 3 else 1.0)


func _land_punch(flat: Vector3, distance: float, reachable: bool) -> void:
	var forward := Vector3(-sin(_facing), 0.0, -cos(_facing))
	if reachable and distance <= ATTACK_RANGE + 0.4 and forward.dot(flat.normalized()) >= 0.5:
		Combat.hurt_hero(hero, 18.0 if response_stars >= 5 else 10.0, forward * 3.0)
