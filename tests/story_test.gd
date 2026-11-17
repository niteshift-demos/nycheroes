extends Node
## Every new objective's positive/negative path, tracked damage, failure,
## story unlock persistence, boss resilience, descriptions and origin shifts.
## godot --headless --path . res://tests/story_test.tscn

class TestCity extends CityStreamer:
	func ground_height_at(_at: Vector3, _search := INF) -> float:
		return 0.0
	func has_collision_at(_at: Vector3) -> bool:
		return true
	func traffic_lanes() -> Dictionary:
		var lanes: Array[PackedVector3Array] = [PackedVector3Array([Vector3(0, 0, -200), Vector3(0, 0, 200)]),
			PackedVector3Array([Vector3(10, 0, -200), Vector3(10, 0, 200)])]
		return {Vector2i.ZERO: [lanes, PackedFloat32Array()]}

var _failures := 0
var hero: Hero
var director: MissionDirector
var wanted: Wanted
var encounters: EncounterDirector
var wallet: Wallet


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func begin(step: Dictionary) -> void:
	director.finish(false)
	var mission := MissionCatalog.make("step", "Step", 100, "", Vector3(9000, 0, 0))
	mission.steps = [step]
	director.start_mission(mission)


func _run() -> void:
	var path := "user://story_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.use_file(path)
	hero = load("res://scenes/hero/hero.tscn").instantiate()
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(hero)
	var city := TestCity.new()
	city.process_mode = Node.PROCESS_MODE_DISABLED
	encounters = EncounterDirector.new()
	encounters.hero = hero
	encounters.city = city
	encounters.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(encounters)
	wanted = Wanted.new()
	wanted.hero = hero
	wanted.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(wanted)
	wallet = Wallet.new()
	add_child(wallet)
	director = MissionDirector.new()
	director.hero = hero
	director.encounters = encounters
	director.wanted = wanted
	director.wallet = wallet
	director.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(director)
	var chapters := StoryCatalog.all()
	check(chapters.size() == 12 and director.available_missions().filter(func(m: Mission) -> bool: return m.chapter > 0).size() == 1,
		"twelve chapters, exactly one story giver")
	check(not director.start_mission(chapters[1]), "locked chapter cannot start")
	var position := Vector3(0, 0, 30)
	begin(Mission.drive_to(position, "Drive", 4))
	director.advance(0.1, position)
	check(director.active != null, "drive checkpoint rejects foot arrival")
	var car := DriveVehicle.new()
	car.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(car)
	var drive := hero.get_mode(&"Drive") as DriveMode
	drive.car = car
	hero.set_mode(&"Drive")
	director.advance(0.1, position)
	check(director.active == null, "drive checkpoint accepts occupied car")
	hero.set_mode(&"OnFoot")
	begin(Mission.steal_car(Vector3.ZERO, "Steal"))
	director.advance(0.1, Vector3.ZERO)
	var marked := director.story_objectives.car
	drive.car = car
	hero.set_mode(&"Drive")
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null, "marked theft rejects a different car")
	hero.set_mode(&"OnFoot")
	drive.car = marked
	hero.set_mode(&"Drive")
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null and is_instance_valid(marked) and marked.driver == hero, "marked takeover completes and preserves occupied car")
	hero.set_mode(&"OnFoot")
	begin(Mission.steal_car(Vector3.ZERO, "Any", false))
	drive.car = car
	hero.set_mode(&"Drive")
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null, "unmarked theft accepts any car")
	hero.set_mode(&"OnFoot")
	begin(Mission.chase(Vector3.ZERO, "Chase"))
	director.advance(0.1, Vector3.ZERO)
	var van := director.story_objectives.targets[0]
	check(van.fleeing and not van.is_in_group("drive_cars"), "fleeing target uses DriveVehicle and cannot be hijacked before disabling")
	van._choose_lane()
	await get_tree().physics_frame
	await get_tree().physics_frame
	van._follow_lane(0.1)
	check(van.velocity.length() > 0.0, "chase AI accelerates through the real car controller")
	var target := director.current_target()
	WorldOrigin.shift(Vector3(500, 0, 0))
	check(director.current_target().distance_to(target) < 0.01, "moving target survives origin shift")
	WorldOrigin.shift(Vector3(-500, 0, 0))
	Combat.area_hit.emit(target + Vector3.UP, 3, 80)
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null and van.health == 80, "one punch damages only the chase relay without premature completion")
	Combat.area_hit.emit(target + Vector3.UP, 3, 80)
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null, "disabled chase target completes")
	begin(Mission.chase(Vector3.ZERO, "Timeout"))
	director.advance(151.0, Vector3.ZERO)
	check(director.active == null and director.banner == "MISSION FAILED", "chase timeout fails")
	begin(Mission.destroy(Vector3.ZERO, 2, "Destroy"))
	director.advance(0.1, Vector3.ZERO)
	var targets := director.story_objectives.targets.duplicate()
	targets[0].damage(160)
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null, "destroy requires every marked car")
	targets[1].damage(160)
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null, "destroy completes after every relay is disabled")
	begin(Mission.escape_wanted(Vector3.ZERO, 2, "Escape"))
	director.advance(0.1, Vector3.ZERO)
	check(wanted.stars == 2 and director.active != null, "escape raises a real pursuit and cannot pass immediately")
	wanted.advance_heat(24, false)
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null, "escape requires all requested stars")
	wanted.advance_heat(18, false)
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null and wanted.stars == 0, "Wanted decay completes escape")
	var rings: Array[Vector3] = [Vector3(0, 50, 0), Vector3(0, 70, 0)]
	begin(Mission.fly_through(rings, "Fly", 5))
	director.advance(0.1, rings[0])
	check(director.story_objectives.ring_index == 0, "sky rings reject walking or driving")
	hero.set_mode(&"Flight")
	director.advance(0.1, rings[1])
	check(director.story_objectives.ring_index == 0, "sky rings require route order")
	director.advance(0.1, rings[0])
	director.advance(0.1, rings[1])
	check(director.active == null, "flight through ordered rings completes")
	hero.set_mode(&"OnFoot")
	begin(Mission.protect(Vector3.ZERO, 4, "Protect"))
	director.advance(0.1, Vector3.ZERO)
	check(director.gang.size() == 2 and director.story_objectives.witness != null, "protect creates a witness and EncounterDirector attack wave")
	director.story_objectives.witness_health = 0
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null and director.banner == "MISSION FAILED", "dead witness fails protect")
	begin(Mission.protect(Vector3.ZERO, 4, "Protect"))
	director.advance(0.1, Vector3.ZERO)
	director.advance(4.1, Vector3.ZERO)
	check(director.active == null, "living witness survives full duration")
	begin(Mission.boss(Vector3.ZERO, 4, "Boss"))
	director.advance(0.1, Vector3.ZERO)
	var boss := director.gang[0]
	boss.take_hit(100, Vector3.UP, true)
	check(boss.health == 800 and not boss.is_down(), "boss health resists instant-launch wins")
	var description := encounters._describe(boss)
	var copy := encounters._spawn_thug(description, 42)
	check(copy.story_variant == 4 and copy.health == 800 and copy.puppet, "boss variant and health survive co-op descriptions")
	copy.queue_free()
	boss._story_cooldown = 0
	boss._advance_story_special(0.1)
	check(boss._story_windup > 0 and boss._story_warning.visible, "boss warns before special attack")
	director.finish(false)
	for chapter in chapters:
		check(director.start_mission(chapter), "chapter %d unlocks in order" % chapter.chapter)
		director.finish(true)
		var saved := StoryCampaign.new()
		check(saved.completed == chapter.chapter, "chapter %d saved immediately" % chapter.chapter)
	var before := wallet.balance
	check(not director.retry() and wallet.balance == before, "completed story cannot replay for duplicate rewards")
	var disk := ConfigFile.new()
	disk.load(path)
	check(disk.get_value("settings", StoryCampaign.KEY) == 12, "completed campaign persisted to disk")
	director.story.reset()
	check(StoryCampaign.new().completed == 0, "story reset persists")
	city.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Story: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures else 0)
