class_name SafeReturn
extends RefCounted
## A session-only traversal retry point. World coordinates survive origin shifts;
## rechecking collision prevents returning into unloaded tiles or new obstacles.

const COOLDOWN := 15.0
const COMBAT_DELAY := 8.0
const ENEMY_RADIUS := 45.0
const MAX_DISTANCE := 250.0

var hero: Hero
var checkpoint := Vector3.INF
var checkpoint_facing := 0.0
var cooldown := 0.0
var combat_delay := 0.0
var message := "Stand still on dry ground to save a point."


func _init(owner_hero: Hero) -> void:
	hero = owner_hero
	hero.hurt.connect(func(_damage: float) -> void: combat_delay = COMBAT_DELAY)


## Called only for the locally owned hero, before its movement mode runs.
## Returns true on recovery so the caller skips movement for this tick.
func tick(delta: float) -> bool:
	cooldown = maxf(0.0, cooldown - delta)
	combat_delay = maxf(0.0, combat_delay - delta)
	if hero.input.attack_held or hero.mode.name in [&"Melee", &"Dive"] or hero.slam_pending or enemies_near(hero.global_position):
		combat_delay = COMBAT_DELAY
	var save := hero.input.checkpoint_pressed
	var recover := hero.input.return_pressed
	hero.input.checkpoint_pressed = false
	hero.input.return_pressed = false
	if not save and not recover:
		return false
	if hero.health <= 0.0 or hero.mode.name == &"KnockedOut":
		message = "Recover after you get back up."
		return false
	if combat_delay > 0.0 or enemies_near(hero.global_position):
		message = "Leave combat: stay clear of thugs for 8 seconds."
		return false
	if save:
		if not hero.grounded() or hero.mode.name != &"OnFoot" or hero.velocity.length() > 0.5:
			message = "Stand still on dry, solid ground to save."
		elif not safe_at(hero.global_position):
			message = "Unsafe ground: need dry support and room to stand."
		else:
			checkpoint = hero.world_position()
			checkpoint_facing = hero.facing
			message = "Safe point saved. Return within 250 m."
		return false
	if checkpoint == Vector3.INF:
		message = "Save a safe point first (K)."
	elif cooldown > 0.0:
		message = "Return cooling down: %d seconds." % ceili(cooldown)
	elif hero.world_position().distance_to(checkpoint) > MAX_DISTANCE:
		message = "Safe point is over 250 m away. Save a nearer one."
	else:
		var destination := WorldOrigin.to_local(checkpoint)
		if enemies_near(destination):
			message = "Thugs near the safe point. Try again later."
		elif not safe_at(destination):
			message = "Safe point blocked or not loaded. Try nearer or save again."
		else:
			hero.set_mode(&"OnFoot")
			hero.global_position = destination + Vector3.UP * 0.06
			hero.velocity = Vector3.ZERO
			hero.facing = checkpoint_facing
			hero.slam_pending = false
			hero.reset_visual_position()
			cooldown = COOLDOWN
			message = "Returned safely. Recovery cooldown: 15 seconds."
			return true
	return false


func enemies_near(at: Vector3) -> bool:
	for thug: Thug in Combat.thugs:
		if is_instance_valid(thug) and thug.health > 0.0:
			var distance := thug.global_position.distance_to(at)
			if distance >= ENEMY_RADIUS and not (distance < Thug.GIVE_UP_RANGE and thug.state in [Thug.State.CHASE, Thug.State.PUNCH, Thug.State.RECOVER]):
				continue
			return true
	return false


## Probe the whole footprint, rejecting edges, steep slopes, water and moving
## platforms. Only static world collision counts; trains are never checkpoints.
func safe_at(at: Vector3) -> bool:
	if at.y < 0.0:
		return false
	var space := hero.get_world_3d().direct_space_state
	var water := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2000.0,
		at + Vector3.UP * 0.05, CityStreamer.WATER_LAYER)
	if not space.intersect_ray(water).is_empty():
		return false
	for offset: Vector3 in [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0, -0.4)]:
		var ray := PhysicsRayQueryParameters3D.create(at + offset + Vector3.UP * 0.25,
			at + offset + Vector3.DOWN * 0.3, Hero.WORLD_LAYER | CityStreamer.WATER_LAYER)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or not hit.collider is StaticBody3D or hit.normal.y < 0.9:
			return false
		if (hit.collider.collision_layer & CityStreamer.WATER_LAYER) != 0:
			return false
	var body := hero.get_node("Body") as CollisionShape3D
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = body.shape
	clearance.transform = Transform3D(Basis.IDENTITY, at + body.position + Vector3.UP * 0.06)
	clearance.collision_mask = Hero.WORLD_LAYER | Combat.HERO_LAYER | Combat.NPC_LAYER | Trains.COLLISION_LAYER
	clearance.exclude = [hero.get_rid()]
	return space.intersect_shape(clearance, 1).is_empty()
