extends Node
## Every new objective's positive/negative path, tracked damage, failure,
## story unlock persistence, boss resilience, descriptions and origin shifts.
## godot --headless --path . res://tests/story_test.tscn

class TestCity extends CityStreamer:
	var overhang := false
	func ground_height_at(_at: Vector3, _search := INF) -> float:
		return (16.0 if _search > 5.0 else 10.0) if overhang else 0.0
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
	var pilot := StoryPlaytest.new()
	hero.set_mode(&"Flight")
	hero.position = Vector3(0, 350, 0)
	var controls := HeroInput.new()
	pilot._fly_to(Vector3(80, 20, 0), controls, hero)
	check(controls.aim.x > 0.9 and is_zero_approx(controls.aim.y),
		"QA pilot clears the rooftop horizontally before descending to the street")
	check(hero.position == Vector3(0, 350, 0) and hero.health == 100,
		"QA routing feeds input without moving or healing the hero")
	hero.position = Vector3(0, 5, 0)
	pilot._fly_to(Vector3(200, 5, 0), controls, hero)
	check(controls.aim.y > 0.99, "QA pilot rises above park buildings before crossing to low targets")
	pilot.free()
	hero.set_mode(&"OnFoot")
	hero.position = Vector3.ZERO
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
	var radar := Radar.new()
	radar.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(radar)
	director = MissionDirector.new()
	director.hero = hero
	director.encounters = encounters
	director.wanted = wanted
	director.wallet = wallet
	director.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(director)
	var removed_gang := encounters.spawn_gang(Vector3.ZERO, 2, Vector3.RIGHT, hero)
	for member in removed_gang:
		member.free()
	encounters._clear_far_gangs()
	check(encounters._gangs.is_empty(), "encounter cleanup accepts freed story actors without typed callback errors")
	city.overhang = true
	begin(Mission.boss(Vector3(0, 10, 0), 2, "Under the stadium overhang"))
	director.active.chapter = 7
	director.advance(0.1, Vector3(0, 10, 0))
	check(director.gang.size() == 1 and WorldOrigin.to_world(director.gang[0].global_position).y < 11.0,
		"story boss keeps the street surface beneath a six-metre overhead structure")
	director.finish(false)
	begin(Mission.protect(Vector3(0, 10, 0), 45, "Street witness"))
	director.advance(0.1, Vector3(0, 10, 0))
	check(director.gang.size() == 2 and director.gang[0].global_position.y < 11.0,
		"protection attackers use the witness street rather than the overhead structure")
	director.finish(false)
	city.overhang = false
	var chapters := StoryCatalog.all()
	check(chapters.size() == 12 and director.available_missions().filter(func(m: Mission) -> bool: return m.chapter > 0).size() == 1,
		"twelve chapters, exactly one story giver")
	check(radar.blips.has(&"mission/giver/story_01") and radar.blips[&"mission/giver/story_01"].kind == &"story"
		and radar.blips[&"mission/giver/story_01"].color == Color.GOLD
		and not radar.blips.has(&"mission/giver/story_02"), "only the unlocked story has a gold S radar blip")
	check(not director.start_mission(chapters[1]), "locked chapter cannot start")
	var menu := PauseMenu.new()
	menu.missions = director
	menu.wallet = wallet
	menu.radar = radar
	menu.stats = PlayerStats.new()
	menu.add_child(menu.stats)
	add_child(menu)
	menu.show_page("missions")
	check(menu.mission_status(chapters[0]) == "AVAILABLE" and menu.mission_status(chapters[1]) == "LOCKED",
		"pause menu uses saved chapter locks rather than contract replay status")
	check((menu._content.get_child(0) as Label).text.begins_with("THE BORROWED SKYLINE")
		and not (menu._content.get_child(2) as Button).disabled and menu._content.get_child(4) is Label,
		"Missions page shows story progress first and hides locked chapter waypoints")
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
	begin(Mission.steal_car(Vector3.ZERO, "Broken recovery car"))
	director.advance(0.1, Vector3.ZERO)
	director.story_objectives.car.take_hit(1000, Vector3.ZERO, false)
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null and director.banner == "MISSION FAILED", "destroyed marked recovery car fails instead of leaving an impossible theft")
	begin(Mission.steal_car(Vector3.ZERO, "Any", false))
	drive.car = car
	hero.set_mode(&"Drive")
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null, "unmarked theft accepts any car")
	hero.set_mode(&"OnFoot")
	begin(Mission.chase(Vector3.ZERO, "Chase"))
	director.advance(0.1, Vector3.ZERO)
	var van := director.story_objectives.targets[0]
	check(van.fleeing and van.ai_controlled and van.is_in_group("drive_cars"), "fleeing target uses the shared car damage group and AI blocks hijacking")
	van._choose_lane()
	await get_tree().physics_frame
	await get_tree().physics_frame
	van._follow_lane(0.1)
	check(van.velocity.length() > 0.0, "chase AI accelerates through the real car controller")
	var target := director.current_target()
	WorldOrigin.shift(Vector3(500, 0, 0))
	check(director.current_target().distance_to(target) < 0.01, "moving target survives origin shift")
	WorldOrigin.shift(Vector3(-500, 0, 0))
	Combat.strike(WorldOrigin.to_local(target) + Vector3.UP, 3, 80, Vector3.ZERO, false)
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null and van.relay_health == 80, "one punch damages only the chase relay without premature completion")
	Combat.strike(WorldOrigin.to_local(target) + Vector3.UP, 3, 80, Vector3.ZERO, false)
	director.advance(0.1, Vector3.ZERO)
	check(director.active == null, "disabled chase target completes")
	begin(Mission.chase(Vector3.ZERO, "Timeout"))
	director.advance(151.0, Vector3.ZERO)
	check(director.active == null and director.banner == "MISSION FAILED", "chase timeout fails")
	begin(Mission.destroy(Vector3.ZERO, 3, "Destroy"))
	director.advance(0.1, Vector3.ZERO)
	var targets := director.story_objectives.targets.duplicate()
	var separated := true
	for i in targets.size():
		for j in i:
			separated = separated and targets[i].global_position.distance_to(targets[j].global_position) >= 7.0
	check(separated, "three relay cars cannot overlap on the same road projection")
	targets[0].damage(160)
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null, "destroy requires every marked car")
	targets[1].damage(160)
	director.advance(0.1, Vector3.ZERO)
	check(director.active != null, "third relay remains required")
	targets[2].damage(160)
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
	var roof_job := MissionCatalog.make("roof", "Roof", 0, "", Vector3(9000, 0, 0))
	roof_job.chapter = 1
	roof_job.steps = [Mission.boss(Vector3(500, 314, 0), 4, "Roof fight")]
	hero.global_position = Vector3(500, 340, 0)
	director.start_mission(roof_job)
	check(encounters._foci().has(Vector3(500, 314, 0)), "nearby elevated story objective retains tile collision at Low quality")
	director.finish(false)
	var platform := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	shape.shape = box
	platform.add_child(shape)
	add_child(platform)
	platform.global_position = Vector3(500, 319.5, 0)
	var edge_boss: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	add_child(edge_boss)
	edge_boss.global_position = Vector3(503.5, 320.2, 0)
	hero.global_position = Vector3(501, 320, 0)
	edge_boss.setup(hero, 0, 0)
	edge_boss.set_story_variant(4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	edge_boss.take_hit(50, Vector3(50, 1, 0), true)
	for tick in 30:
		await get_tree().physics_frame
	check(edge_boss.global_position.x < 504.5 and edge_boss.global_position.y > 319.5,
		"surviving launch hit cannot push a powered boss off its rooftop")
	edge_boss.queue_free()
	platform.queue_free()
	hero.global_position = Vector3.ZERO
	for chapter in chapters:
		check(director.start_mission(chapter), "chapter %d unlocks in order" % chapter.chapter)
		if chapter.chapter == 1:
			director.advance(0.1, chapter.steps[0].position)
			check(director.step_index == 0 and director.phone_lines.size() == 2, "opening phone call holds objective progress")
			director.next_call()
			check(director.phone_lines.size() == 1, "phone Next advances a line")
			director.skip_calls()
			check(director.phone_lines.is_empty(), "phone Skip dismisses the call")
		director.finish(true)
		if chapter.chapter == 1:
			check(menu.mission_status(chapters[0]) == "PASSED" and menu.mission_status(chapters[1]) == "AVAILABLE",
				"passing a story chapter unlocks the next Missions-page entry")
			var display := GameHud.new()
			display.process_mode = Node.PROCESS_MODE_DISABLED
			display.visible = false
			display.hero = hero
			display.missions = director
			add_child(display)
			display._process(0.1)
			check(display.banner_title == "MISSION PASSED" and display.banner_detail.contains("10,000"),
				"story completion uses the shared HUD result banner")
			display.free()
			menu.free()
			check(radar.blips.has(&"mission/giver/story_02") and not radar.blips.has(&"mission/giver/story_01"), "finishing a chapter replaces its S giver with the next one")
		var saved := StoryCampaign.new()
		check(saved.completed == chapter.chapter, "chapter %d saved immediately" % chapter.chapter)
	var before := wallet.balance
	check(not director.retry() and wallet.balance == before, "completed story cannot replay for duplicate rewards")
	var disk := ConfigFile.new()
	disk.load(path)
	check(disk.get_value("settings", StoryCampaign.KEY) == 12, "completed campaign persisted to disk")
	director.story.reset()
	check(StoryCampaign.new().completed == 0, "story reset persists")
	director.story.completed = 1
	director.banner_remaining = 0.0
	director._inside_givers.clear()
	var next_chapter: Mission
	for definition in director.catalog:
		if definition.chapter == 2:
			next_chapter = definition
	director.advance(0.1, next_chapter.giver)
	check(director.active == next_chapter, "Empire State story giver wins over the replayable courier at the same location")
	director.finish(false)
	director.story.reset()
	city.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Story: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures else 0)
