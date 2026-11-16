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
	var director := MissionDirector.new()
	director.process_mode = Node.PROCESS_MODE_DISABLED
	director.wallet = wallet
	add_child(director)
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
	director.advance(2.1, Vector3.ZERO)
	_check(director.active == null and director.banner == "MISSION FAILED" and wallet.balance == 12450, "expired timer fails without payout")
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
	mission.steps = [Mission.defeat_gang_at(Vector3(12, 0, 0), 2, "Fight")]
	director.start_mission(mission)
	director.advance(0.1, Vector3.ZERO)
	_check(director.gang.size() == 2, "mission spawns through EncounterDirector")
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
	director.banner_remaining = 0.0
	director.advance(0.1, mission.giver)
	# Use a catalog giver to exercise the same entry path as touch movement.
	var giver: Mission = director.catalog[0]
	director.advance(0.1, giver.giver)
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
	city.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Missions: %d failure(s)" % _failed)
	get_tree().quit(1 if _failed else 0)
