extends Node3D
## Cross-feature regression: stranded AI, burned police witnesses, BUSTED
## during a story call, snapshot generations, and effects across origin shifts.
## godot --headless --path . res://tests/gta_integration_test.tscn

class Street extends CityStreamer:
	func _ready() -> void:
		set_process(false)
	func has_collision_at(_at: Vector3) -> bool:
		return true
	func ground_height_at(_at: Vector3, _search := INF) -> float:
		return 0.0
	func lanes_near(_at: Vector3, _radius: float) -> Array[PackedVector3Array]:
		return [PackedVector3Array([Vector3(-20, 0, -20), Vector3(20, 0, -20)])]

class ParkedCar extends DriveVehicle:
	var moves := 0
	func _step(delta: float) -> void:
		moves += 1
		super._step(delta)

var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failed += 1


func check_animation(hero: Hero, transition: String) -> void:
	var animator := hero.get_node("Model") as HeroAnimator
	animator._process(1.0 / 60.0)
	animator._player.advance(0.2)
	check(animator._player.is_playing() and animator._player.has_animation(animator._player.assigned_animation) \
		and animator._player.assigned_animation != &"RESET", "hero animation plays after " + transition)


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://gta_integration_test.cfg"))
	Settings.use_file("user://gta_integration_test.cfg")
	var recovery := AiRecovery.new()
	check(recovery.advance(Vector3.ZERO, 2.1, true, 0.0) and recovery.reverse_time > 0.0,
		"stationary AI starts a full reverse with nonzero steering")
	var first_turn := recovery.turn
	for tick in 16:
		recovery.advance(Vector3.ZERO, 0.1, true, 0.0)
	check(recovery.reverse_time == 0.0 and recovery.attempts == 1, "reverse finishes before another stuck decision")
	recovery.advance(Vector3.ZERO, 2.1, true, 0.0)
	check(recovery.attempts == 2 and recovery.turn == -first_turn, "repeated failed corner alternates escape direction")
	recovery.advance(Vector3(9, 0, 0), 0.1, true, 0.0)
	check(recovery.attempts == 0, "real travel clears failed attempts")
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.position.y = -0.5
	var parked := ParkedCar.new()
	add_child(parked)
	parked.position = Vector3(-40, 0.2, -40)
	for tick in 45:
		await get_tree().physics_frame
	var moves := parked.moves
	for tick in 10:
		await get_tree().physics_frame
	check(parked.is_on_floor() and parked.moves == moves, "settled physical car sleeps without repeating collision or mesh updates")
	var resting := parked.global_position
	parked.take_hit(1.0, Vector3(6, 1, 0), false)
	for tick in 10:
		await get_tree().physics_frame
	check(parked.moves > moves and parked.global_position.distance_to(resting) > 0.2, "a hit wakes the parked car and moves its real body")
	parked.queue_free()
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	hero.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(hero)
	hero.frozen = false
	var animator := hero.get_node("Model") as HeroAnimator
	var skeleton := animator.find_child("Skeleton3D", true, false) as Skeleton3D
	var arm := skeleton.find_bone("DEF-upper_arm.L")
	check(animator._player.is_playing() and animator._player.assigned_animation == &"Idle" \
		and not skeleton.get_bone_pose_rotation(arm).is_equal_approx(Quaternion.IDENTITY),
		"first frame is posed Idle before browser skin warm-up can freeze the bind pose")
	animator._player.process_mode = Node.PROCESS_MODE_DISABLED
	check(not skeleton.get_bone_pose_rotation(arm).is_equal_approx(Quaternion.IDENTITY), "skin warm-up holds a posed arm")
	animator._player.process_mode = Node.PROCESS_MODE_INHERIT
	check_animation(hero, "skin warm-up release")
	var ride := DriveVehicle.new()
	add_child(ride)
	await get_tree().physics_frame
	(hero.get_mode(&"Drive") as DriveMode).car = ride
	hero.set_mode(&"Drive")
	check_animation(hero, "entering a car")
	hero.set_mode(&"OnFoot")
	check_animation(hero, "leaving a car")
	ride.queue_free()
	var placement := Game.new()
	placement.hero = hero
	placement.hero_camera = ThirdPersonCamera.new()
	placement.travel_to(Vector3(20, 0, 20))
	check_animation(hero, "story travel through Game.travel_to")
	hero.global_position = Vector3.ZERO
	hero.frozen = false
	placement.hero_camera.free()
	placement.free()
	var city := Street.new()
	add_child(city)
	var encounters := EncounterDirector.new()
	encounters.hero = hero
	encounters.city = city
	encounters.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(encounters)
	var wanted := Wanted.new()
	wanted.hero = hero
	wanted.city = city
	wanted.encounters = encounters
	wanted.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(wanted)
	var radar := Radar.new()
	radar.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(radar)
	var wallet := Wallet.new()
	add_child(wallet)
	wallet.add(10000, "fixture")
	var missions := MissionDirector.new()
	missions.hero = hero
	missions.encounters = encounters
	missions.wanted = wanted
	missions.wallet = wallet
	missions.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(missions)
	var stats := PlayerStats.new()
	add_child(stats)
	var pause := PauseMenu.new()
	pause.stats = stats
	pause.missions = missions
	pause.wallet = wallet
	pause.radar = radar
	add_child(pause)
	var atlas := WorldMap.new()
	atlas.radar = radar
	add_child(atlas)
	pause.map_requested.connect(atlas.open)
	pause.open()
	pause._leave(pause.map_requested)
	atlas.close()
	check(not get_tree().paused, "pause to map to resume restores simulation")
	check_animation(hero, "pause → map → resume")
	pause.queue_free()
	atlas.queue_free()
	check(radar.blips[&"mission/giver/times_square"].color == Radar.CONTRACT_COLOR,
		"contract radar blip uses the same purple as its HUD label and map legend")
	await get_tree().physics_frame
	var patrol := wanted.pursuit.spawn(Vector3(0, 0, 20), PI)
	patrol.process_mode = Node.PROCESS_MODE_DISABLED
	wanted.set_stars(3)
	check(wanted.police_see_hero(), "live patrol sees its suspect")
	patrol.take_hit(1000, Vector3.ZERO, false)
	check(not wanted.police_see_hero() and not wanted.witnessed(hero.world_position()),
		"disabled patrol cannot prolong pursuit or report a crime")
	patrol.explode()
	wanted.pursuit.advance(0.0)
	check(not patrol.is_in_group("police_cars") and not wanted.pursuit.cars.has(patrol),
		"burned patrol releases its fleet slot and police blip")
	var officer := encounters.spawn_police(Vector3(30, 0, 0), hero, 3)
	officer.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	officer.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	officer.frozen = true
	officer._physics_process(3.0)
	check(officer.recovery.attempts == 0, "unloaded foot officer never runs recovery or pursuit physics")
	officer.frozen = false
	officer.state = Thug.State.CHASE
	officer._physics_process(2.1)
	check(officer.recovery.reverse_time > 0.0, "blocked officer starts a wall detour")
	officer.recovery = AiRecovery.new()
	officer.global_position = hero.global_position + Vector3(3, 0, 0)
	officer.surround_angle = 0.0
	officer.state = Thug.State.CHASE
	officer._physics_process(2.1)
	check(officer.recovery.reverse_time > 0.0, "nearby blocked officer also detours instead of waiting against the corner")
	officer.recovery = AiRecovery.new()
	officer.global_position = hero.global_position + Vector3(0, 0, Thug.SURROUND_RADIUS)
	officer.state = Thug.State.CHASE
	officer._physics_process(2.1)
	check(officer.recovery.attempts == 0, "officer already at its surrounding spot does not invent a stuck manoeuvre")
	wanted.set_stars(5)
	for i in Wanted.MAX_POLICE - wanted.response_count():
		var extra := encounters.spawn_police(Vector3(60 + i * 2, 0, 0), hero, 5)
		extra.process_mode = Node.PROCESS_MODE_DISABLED
	var deploying := wanted.pursuit.spawn(Vector3(70, 0, 20), PI)
	deploying.process_mode = Node.PROCESS_MODE_DISABLED
	wanted.pursuit._deploy(deploying)
	check(wanted.response_count() == Wanted.MAX_POLICE, "patrol deployment shares the ten-officer cap with foot reinforcements")
	var mission := StoryCatalog.all()[0]
	missions.start_mission(mission, true)
	missions.gang.append_array(encounters.spawn_gang(Vector3(8, 0, 8), 2, Vector3.RIGHT, hero))
	var owned := missions.gang.duplicate()
	var before := wallet.balance
	wanted.set_stars(3)
	hero.take_hit(1000, Vector3.ZERO)
	check(missions.active == null and missions.phone_lines.is_empty() and missions.story.completed == 0,
		"BUSTED interrupts a story call without advancing its checkpoint")
	check(wallet.balance == before - mini(1000, ceili(before * 0.1)), "story arrest charges the fine once")
	check(not radar.blips.has(MissionRadar.OBJECTIVE_ID), "failed story clears its target blip")
	await get_tree().process_frame
	check(not is_instance_valid(owned[0]) and not is_instance_valid(owned[1]), "failed story releases its standing gang")
	var shops := CityShops.new()
	shops.hero = hero
	shops.wallet = wallet
	shops.wanted = wanted
	shops.radar = radar
	shops.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(shops)
	Settings.set_value("safehouse_position", Vector3(100, 0, 100))
	wanted._physics_process(2.1)
	check(hero.mode.name == &"OnFoot" and hero.health == hero.max_health, "BUSTED recovery restores a playable hero")
	check_animation(hero, "BUSTED at the saved safehouse")
	check(hero.world_position().distance_to(Vector3(100, 0.3, 100)) < 0.01 and missions.story.completed == 0,
		"safehouse arrest respawn keeps the unfinished story checkpoint")
	hero.set_mode(&"KnockedOut")
	(hero.mode as KnockedOutMode).physics_update(4.0)
	hero.set_mode(&"OnFoot")
	check_animation(hero, "ordinary knockout and safehouse respawn")
	check(missions.retry() and missions.step_index == 0 and missions.story.completed == 0,
		"retry returns to the same chapter's first step")
	missions.finish(false)
	var sync := PlayerSync.new()
	sync.hero = hero
	sync.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sync)
	var buffer := SnapshotBuffer.new()
	sync._snapshots[0] = buffer
	var state := sync._encode(hero)
	check(state.size() == 22, "combined drive/wanted/damage snapshot is 22 fields")
	for size in [13, 15, 18, 21, 22]:
		var packet := state.slice(0, size)
		packet[0] = size * 1000
		sync._hero_state(packet)
		check(not buffer.is_empty() and (buffer.sample()[1] as Array).size() == size,
			"PlayerSync accepts the %d-field snapshot generation" % size)
	var malformed := state.slice(0, 20)
	malformed[0] = 99999
	sync._hero_state(malformed)
	check((buffer.sample()[1] as Array).size() == 22, "PlayerSync rejects a partial damage snapshot")
	var boss := encounters.spawn_gang(Vector3(0, 0, 30), 1, Vector3.RIGHT, hero)[0]
	boss.set_story_variant(4)
	boss.set_story_variant(4, false)
	check(boss.story_tag().begins_with("ALDEN VOSS · BOSS") and boss.find_children("*", "Label3D", false, false).is_empty(),
		"boss uses native-resolution HUD text without aliased 3-D labels")
	check(boss.find_children("*", "MeshInstance3D", false, false).size() == 1, "reapplying boss appearance does not leak warning rings")
	var effects := CombatEffects.new()
	effects.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(effects)
	WorldOrigin.shift(Vector3(500, 0, 0))
	var at := WorldOrigin.to_local(Vector3(20, 0, 10))
	effects.car_explosion(at)
	var blast := effects._explosions[0]
	check(blast.global_position.distance_to(at) < 0.01, "new explosion after an origin shift appears at the car")
	var particle_count := 0
	for child in blast.get_children():
		if child is CPUParticles3D:
			particle_count += 1
			check(child.local_coords and child.amount <= 18 and child.one_shot, "explosion burst is bounded and follows the floating ancestor")
	check(particle_count == 3, "explosion has fire, soot and metal bursts")
	WorldOrigin.shift(Vector3(500, 0, 0))
	check(WorldOrigin.to_world(blast.global_position).distance_to(Vector3(20, 0, 10)) < 0.01,
		"live explosion survives the next origin shift exactly once")
	WorldOrigin.shift(Vector3(-1000, 0, 0))
	effects.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(4.0).timeout
	check(effects._explosions.is_empty() and effects.get_child_count() == 0, "finished explosion frees particles, flash light and its root")
	print("GTA integration: %d failure(s)" % _failed)
	get_tree().quit(1 if _failed else 0)
