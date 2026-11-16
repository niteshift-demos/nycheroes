extends Node3D
## Synthetic street checks: witnesses and occlusion, innocent gang fights,
## police spawning/chasing, bounded response, escape, replication and BUSTED.
## Run: godot --headless --path . res://tests/wanted_test.tscn

class Street extends CityStreamer:
	func _ready() -> void:
		set_process(false)
	func has_collision_at(_at: Vector3) -> bool:
		return true
	func lanes_near(_at: Vector3, _radius: float) -> Array[PackedVector3Array]:
		return [PackedVector3Array([Vector3(-2, 0, 28), Vector3(2, 0, 28)])]
	func ground_height_at(_at: Vector3, _search_from := INF) -> float:
		return 0.0

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failures += 1


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.position.y = -0.5
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	var city := Street.new()
	add_child(city)
	var director := EncounterDirector.new()
	director.hero = hero
	director.city = city
	add_child(director)
	director.set_process(false)
	var wanted := Wanted.new()
	wanted.hero = hero
	wanted.city = city
	wanted.encounters = director
	add_child(wanted)
	wanted.set_physics_process(false)
	await get_tree().physics_frame
	Combat.report_crime(&"carjacking", Vector3(1000, 0, 1000), 1.0)
	_check(wanted.stars == 0, "unwitnessed crime leaves stars clear")
	var ped: Pedestrian = load("res://scenes/npc/pedestrian.tscn").instantiate()
	add_child(ped)
	ped.setup(hero, PackedVector3Array([Vector3(0, 0, -2), Vector3(0, 0, 2)]), 0, 0.5)
	ped.set_process(false)
	Combat.shockwave(Vector3.ZERO, 3.0, 0.0, 3.0)
	_check(wanted.stars == 0 and ped._down_time == 0.0, "harmless shockwave cannot hurt civilians or raise heat")
	Combat.strike(Vector3.UP, 3.0, 20.0, Vector3.BACK * 3.0, false)
	_check(wanted.stars == 1 and ped._down_time > 0.0, "civilian hit is witnessed and knocks victim down")
	var heat := wanted.heat
	Combat.strike(Vector3.UP, 3.0, 20.0, Vector3.ZERO, false)
	_check(is_equal_approx(wanted.heat, heat), "fallen civilian cannot farm repeated crimes")
	var bone := ped._ragdoll.get_child(0) as PhysicalBone3D
	var before_shift := WorldOrigin.to_world(bone.global_position)
	WorldOrigin.shift(Vector3(500, 0, 0))
	_check(WorldOrigin.to_world(bone.global_position).distance_to(before_shift) < 0.05, "civilian ragdoll survives an origin shift")
	WorldOrigin.shift(Vector3(-500, 0, 0))
	wanted.set_stars(0)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1, 5, 20)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	add_child(wall)
	wall.position = Vector3(5, 2, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Combat.report_crime(&"carjacking", Vector3(10, 0, 0), 1.0)
	_check(wanted.stars == 0, "wall blocks a nearby witness")
	wall.queue_free()
	ped.remove_from_group("pedestrians")
	var gang := director.spawn_gang(Vector3(3, 0, 0), 1, Vector3.RIGHT)
	Combat.strike(gang[0].body_center(), 1.0, 20.0, Vector3.ZERO, false)
	_check(wanted.stars == 0, "attacking gang members is not a crime")
	gang[0].queue_free()
	wanted.set_stars(3)
	for i in 15:
		wanted._spawn_response()
	_check(Combat.thugs.filter(func(t: Thug) -> bool: return t is PoliceOfficer).size() == 6, "three stars spawn at most six police")
	var officer: PoliceOfficer
	for thug in Combat.thugs:
		if thug is PoliceOfficer:
			officer = thug
			break
	var start_distance := officer.global_position.distance_to(hero.global_position)
	await get_tree().create_timer(1.0).timeout
	_check(officer.global_position.distance_to(hero.global_position) < start_distance, "police chase the wanted hero")
	Combat.shockwave(officer.global_position, 0.5, 0.0, 3.0)
	_check(wanted.stars == 3, "harmless shockwave near police does not raise heat")
	Combat.strike(officer.body_center(), 0.5, 20.0, Vector3.ZERO, false)
	_check(wanted.stars == 4, "attacking police raises wanted level")
	var description := director._describe(officer)
	# Avoid the synthetic copy overwriting the authoritative id in Combat.
	description[0] = int(description[0]) + 1000000
	var copy := director._spawn_thug(description, 2) as PoliceOfficer
	_check(copy != null and copy.puppet and copy.suspect_id == Net.local_id(), "police identity and suspect survive encounter replication")
	copy.queue_free()
	var sync := PlayerSync.new()
	var state := sync._encode(hero)
	_check(state.size() == 15 and state[13] == wanted.stars, "wanted stars travel in plain hero state")
	var remote: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	remote.remote_id = 2
	add_child(remote)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(float(state[0]), state)
	sync._follow(remote, snapshots)
	_check(remote.wanted_stars == wanted.stars and hero.wanted_stars == 4, "remote hero receives wanted state without changing local heat")
	remote.queue_free()
	sync.free()
	wanted.advance_heat(Wanted.SEARCH_DELAY + 0.1, false)
	_check(wanted.searching, "stars flash while police search")
	wanted.advance_heat(1.0, true)
	_check(not wanted.searching and wanted.stars == 4, "police sight resets escape timer")
	wanted.advance_heat(Wanted.SEARCH_DELAY + Wanted.DECAY_TIME + 0.1, false)
	_check(wanted.stars == 3, "escaping police removes one star")
	for i in 3:
		wanted.advance_heat(Wanted.DECAY_TIME + 0.1, false)
	_check(wanted.stars == 0 and not wanted.searching, "remaining hidden clears the pursuit")
	wanted.set_stars(0)
	ped.add_to_group("pedestrians")
	ped._process(5.0)
	Combat.shockwave(Vector3.ZERO, 8.0, 100.0, 8.0)
	_check(wanted.stars > 0 and ped._down_time > 0.0, "damaging landing slam reports bystander injuries")
	wanted.set_stars(5)
	hero.take_hit(1000.0, Vector3.ZERO)
	_check(wanted.stars == 0 and wanted._bust_wait > 0.0, "knockout while wanted triggers BUSTED")
	wanted._physics_process(2.1)
	_check(hero.health == Hero.MAX_HEALTH and hero.mode.name == &"OnFoot", "BUSTED restores the hero on a nearby sidewalk")
	wanted.enabled = false
	wanted.set_stars(5)
	_check(wanted.stars == 0, "police disabled suppresses wanted stars")
	print("wanted_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
