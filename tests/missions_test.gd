extends Node
## Wallet persistence and validation; mission progression, timeout/retry,
## pickups, giver entry, floating origin and real EncounterDirector gangs.
## Run: godot --headless --path . res://tests/missions_test.tscn

class TestCity extends CityStreamer:
	func ground_height_at(_position: Vector3, _search_from := INF) -> float:
		return 0.0
	func has_collision_at(_position: Vector3) -> bool:
		return true

var _failed := 0
var _events: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", text])
	if not ok:
		_failed += 1


func _run() -> void:
	var path := "user://missions_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_file(path)
	var wallet := Wallet.new()
	add_child(wallet)
	wallet.changed.connect(func(_balance: int) -> void: _events.append("cash"))
	wallet.add(12500, "test reward")
	_check(wallet.balance == 12500 and _events.size() == 1, "cash reward emits changed")
	_check(not wallet.spend(-2) and not wallet.spend(12501), "negative spending and overdrafts rejected")
	wallet.add(-50, "invalid")
	_check(wallet.spend(50) and wallet.balance == 12450, "spending debits once; negative earnings ignored")
	var disk := ConfigFile.new()
	disk.load(path)
	_check(disk.get_value("settings", "cash") == 12450, "cash saved immediately")
	Settings.use_file(path)
	var reloaded := Wallet.new()
	add_child(reloaded)
	_check(reloaded.balance == 12450 and Wallet.format_cash(12450) == "$12,450", "saved balance reloads and formats")
	reloaded.queue_free()
	var radar := Radar.new()
	radar.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(radar)
	var director := MissionDirector.new()
	director.process_mode = Node.PROCESS_MODE_DISABLED
	director.wallet = wallet
	add_child(director)
	var navigation := director.get_node("MissionRadar") as MissionRadar
	_check(radar.blips.has(&"mission/giver/times_square") and radar.blips[&"mission/giver/times_square"].kind == &"mission"
		and radar.blips[&"mission/giver/times_square"].color == Color.YELLOW, "available givers have yellow mission radar blips")
	director.mission_started.connect(func(id: String) -> void: _events.append("start:" + id))
	director.mission_step_changed.connect(func(id: String, _at: Vector3) -> void: _events.append("step:" + id))
	director.mission_finished.connect(func(id: String, success: bool) -> void: _events.append("end:" + id + str(success)))
	var mission := MissionCatalog.make("test", "Test route", 5000, "Test", Vector3(9000, 0, 0))
	mission.steps = [Mission.go_to(Vector3(100, 0, 0), 5.0, "Reach A"),
		Mission.reach_in_time(Vector3(200, 0, 0), 2.0, "Reach B", 5.0)]
	_check(director.start_mission(mission) and not director.start_mission(mission), "one local mission at a time")
	director.advance(0.1, Vector3.ZERO)
	_check(director.step_index == 0 and director.current_target() == Vector3(100, 0, 0), "outside radius does not progress")
	WorldOrigin.shift(Vector3(500, 0, 0))
	_check(director.current_target() == Vector3(100, 0, 0), "target survives origin shift")
	WorldOrigin.shift(Vector3(-500, 0, 0))
	director.advance(0.1, Vector3(100, 0, 0))
	_check(director.step_index == 1 and director.remaining == 2.0, "arrival advances and starts timer")
	_check(radar.waypoint_active and radar.waypoint_position == Vector3(200, 0, 0)
		and radar.blips[MissionRadar.OBJECTIVE_ID].world_position == Vector3(200, 0, 0)
		and not radar.blips.has(&"mission/giver/times_square"), "step changes set the objective blip and world waypoint")
	director.advance(2.1, Vector3.ZERO)
	_check(director.active == null and director.banner == "MISSION FAILED" and wallet.balance == 12450, "expired timer fails without payout")
	_check(not radar.waypoint_active and not radar.blips.has(MissionRadar.OBJECTIVE_ID)
		and radar.blips.has(&"mission/giver/times_square"), "finish clears navigation and restores available givers")
	_check(director.retry() and director.step_index == 0, "retry resets route")
	director.advance(0.1, Vector3(100, 0, 0))
	director.advance(0.5, Vector3(200, 0, 0))
	director.finish(true)
	_check(director.active == null and wallet.balance == 17450 and director.banner.begins_with("MISSION PASSED"), "finish pays exactly once")
	_check(_events.has("start:test") and _events.has("step:test") and _events.has("end:testtrue") and _events.has("end:testfalse"), "integration signals include mission ids")
	var pickups: Array[Vector3] = [Vector3(5, 0, 0), Vector3(25, 0, 0)]
	mission.steps = [Mission.collect(pickups, "Collect", 2.0)]
	director.start_mission(mission)
	director.advance(0.1, pickups[0])
	director.advance(0.1, pickups[0])
	_check(director.collected.size() == 1 and director.current_target() == pickups[1], "pickup counted once and radar moves to next")
	director.advance(0.1, pickups[1])
	_check(director.active == null and wallet.balance == 22450, "all collectibles complete mission")
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(hero)
	var city := TestCity.new()
	city.process_mode = Node.PROCESS_MODE_DISABLED
	var encounters := EncounterDirector.new()
	encounters.city = city
	encounters.hero = hero
	encounters.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(encounters)
	director.hero = hero
	director.encounters = encounters
	mission.id = "side_job"
	mission.steps = [Mission.defeat_gang_at(Vector3(12, 0, 0), 2, "Fight")]
	director.start_mission(mission)
	director.advance(0.1, Vector3.ZERO)
	_check(director.gang.size() == 2, "mission spawns through EncounterDirector")
	navigation.refresh()
	var enemy_id := StringName("mission/enemy/%d" % director.gang[0].get_instance_id())
	_check(radar.blips.has(enemy_id) and radar.blips[enemy_id].kind == &"enemy" and radar.blips[enemy_id].node != null,
		"side-job crew members have tracked enemy radar blips")
	var outsider: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	add_child(outsider)
	outsider.global_position = Vector3(1000, 0, 0)
	outsider.go_down(Vector3.UP)
	director.advance(0.1, Vector3.ZERO)
	_check(director.active != null, "unrelated fights cannot advance tracked gang")
	for thug in director.gang:
		thug.go_down(Vector3.UP)
	director.advance(0.1, Vector3.ZERO)
	_check(director.active == null and wallet.balance == 27550, "defeated mission gang pays mission plus local assist bounties")
	_check(not radar.blips.has(enemy_id) and not radar.waypoint_active, "finished side jobs remove crew blips and waypoint")
	director.banner_remaining = 0.0
	director.advance(0.1, mission.giver)
	# Use a catalog giver to exercise the same entry path as touch movement.
	var giver: Mission = director.catalog[0]
	director.advance(0.1, giver.giver - Vector3.UP * 18.0)
	_check(director.active == giver, "walking into giver starts mission without keyboard")
	director.finish(false)
	director.banner_remaining = 0.0
	director.advance(0.1, giver.giver)
	_check(director.active == null, "standing in giver cannot repeatedly restart")
	director.start_mission(mission)
	director.advance(0.1, Vector3.ZERO)
	var canceled := director.gang.duplicate()
	director.finish(false)
	_check(canceled.all(func(thug: Thug) -> bool: return not Combat.thugs.has(thug) and thug.is_queued_for_deletion()), "abandon removes standing crew before retry")
	hero.frozen = false
	var car := DriveVehicle.new()
	car.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(car)
	car.global_position = Vector3(100, 0, 0)
	var drive := hero.get_mode(&"Drive") as DriveMode
	drive.car = car
	hero.set_mode(&"Drive")
	var race := MissionCatalog.make("car_race", "Car checkpoint", 700, "Drive through", Vector3(9000, 0, 0))
	race.steps = [Mission.reach_in_time(Vector3(140, 0, 0), 10.0, "Drive to the checkpoint", 5.0)]
	director.start_mission(race)
	director._process(0.1)
	_check(director.active == race, "car outside checkpoint does not advance race")
	car.global_position = Vector3(140, 0, 0)
	drive._follow_car()
	director._process(0.1)
	_check(hero.mode.name == &"Drive" and director.active == null and wallet.balance == 28250,
		"Drive mode follows the car through a timed checkpoint and earns cash")
	hero.set_mode(&"OnFoot")
	hero.global_position = Vector3.ZERO
	car.queue_free()
	var wanted := Wanted.new()
	wanted.hero = hero
	wanted.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(wanted)
	var arrested := MissionDirector.new()
	arrested.process_mode = Node.PROCESS_MODE_DISABLED
	arrested.wallet = wallet
	arrested.wanted = wanted
	add_child(arrested)
	wallet.spend(wallet.balance - 5000)
	arrested.start_mission(mission)
	wanted.set_stars(2)
	hero.take_hit(1000.0, Vector3.ZERO)
	_check(arrested.active == null and arrested.banner == "MISSION FAILED" and wallet.balance == 4500,
		"Wanted.busted fails the mission and fines ten percent")
	wanted._physics_process(2.1)
	wallet.add(15500, "fine cap test")
	wanted.set_stars(2)
	hero.take_hit(1000.0, Vector3.ZERO)
	_check(wallet.balance == 19000 and arrested.banner == "BUSTED  -$1,000", "bust fine is capped at one thousand outside missions")
	var officer: PoliceOfficer = load("res://scenes/npc/police_officer.tscn").instantiate()
	add_child(officer)
	officer.go_down(Vector3.UP)
	_check(wallet.balance == 19000, "police defeats never pay a gang bounty")
	city.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Missions: %d failure(s)" % _failed)
	get_tree().quit(1 if _failed else 0)
