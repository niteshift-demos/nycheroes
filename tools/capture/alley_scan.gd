extends Node
## Finds narrow gaps between tall buildings (for a wall kick video): loads the
## real city around --spawn and prints spots with walls on both sides 4-9 m
## apart, at least 15 m tall, and open sky between.
## Run: godot --headless --path . res://tools/capture/alley_scan.tscn -- --spawn=X,Y,Z --tiles_url=...

const AVENUE := Vector3(0.485, 0.0, -0.875)
const CROSS := Vector3(0.875, 0.0, 0.485)

var _world: Game
var _hero: Hero
var _city: CityStreamer


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_run.call_deferred()


func _run() -> void:
	while _hero.frozen or _city.pending_count() > 0:
		await get_tree().physics_frame
	for n in 30:
		await get_tree().physics_frame
	var space := _hero.get_world_3d().direct_space_state
	var center := _hero.world_position()
	var found := 0
	for gx in range(-60, 61):
		for gz in range(-60, 61):
			var world := center + AVENUE * gx * 3.0 + CROSS * gz * 3.0
			var ground := _city.ground_height_at(Vector3(world.x, 400.0, world.z))
			if is_nan(ground) or absf(ground - center.y) > 6.0:
				continue  # a roof, or far off the street level
			var p := WorldOrigin.to_local(Vector3(world.x, ground + 2.0, world.z))
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 40.0, 1)).is_empty():
				continue
			for axis: Vector3 in [AVENUE, CROSS]:
				var a := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + axis * 10.0, 1))
				var b := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - axis * 10.0, 1))
				if a.is_empty() or b.is_empty():
					continue
				var gap: float = p.distance_to(a.position) + p.distance_to(b.position)
				if gap < 4.0 or gap > 9.0 or absf(a.normal.y) > 0.2 or absf(b.normal.y) > 0.2:
					continue
				var hp := p + Vector3.UP * 15.0
				if space.intersect_ray(PhysicsRayQueryParameters3D.create(hp, hp + axis * 10.0, 1)).is_empty() \
						or space.intersect_ray(PhysicsRayQueryParameters3D.create(hp, hp - axis * 10.0, 1)).is_empty():
					continue
				print("ALLEY at %s ground %.1f gap %.1f axis %s" % [Vector3(world.x, ground, world.z).round(), ground, gap, "avenue" if axis == AVENUE else "cross"])
				found += 1
	print("found %d" % found)
	get_tree().quit()
