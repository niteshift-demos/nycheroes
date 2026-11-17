extends Node3D
## Purchases, save/reload, applied powers, garage sight and both recovery paths.
## Run: godot --headless --path . res://tests/shops_test.tscn

const SAVE := "user://shops_test.cfg"
var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failures += 1


func _run() -> void:
	DirAccess.remove_absolute(SAVE)
	Settings.use_file(SAVE)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 1, 1000)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	hero.set_physics_process(false)
	var wallet := Wallet.new()
	add_child(wallet)
	var wanted := Wanted.new()
	wanted.hero = hero
	add_child(wanted)
	wanted.set_physics_process(false)
	var shops := CityShops.new()
	shops.hero = hero
	shops.wallet = wallet
	shops.wanted = wanted
	shops.locations = [CityShops._location("test", "Test Supply", &"shop", Vector3.ZERO)]
	add_child(shops)
	shops.set_physics_process(false)
	_check(not shops.respawn(), "no apartment keeps ordinary recovery location")
	shops._physics_process(0.1)
	_check(shops.active.get("kind") == &"shop", "walking into marker enters shop")
	shops.close()
	shops._physics_process(0.1)
	_check(shops.active.is_empty(), "closed panel stays closed inside the marker")
	hero.position.x = 30
	shops._physics_process(0.1)
	hero.position.x = 0
	shops._physics_process(0.1)
	_check(not shops.active.is_empty(), "leaving and returning reopens the shop")
	hero.position.x = 30
	shops._physics_process(0.1)
	_check(shops.active.is_empty(), "moving outside a service closes it in co-op")
	hero.position.x = 0
	shops._physics_process(0.1)
	_check(not shops.purchase("health") and HeroUpgrades.tier("health") == 0, "insufficient funds do not grant a tier")
	wallet.add(250000, "test")
	_check(shops.purchase("health") and wallet.balance == 248000 and hero.max_health == 125.0, "purchase charges $2000 and adds 25 health")
	_check(not shops.purchase("invalid"), "unknown upgrade rejected")
	for id: String in HeroUpgrades.NAMES:
		while HeroUpgrades.tier(id) < 3:
			_check(shops.purchase(id), "purchase " + id + " tier " + str(HeroUpgrades.tier(id)))
	_check(not shops.purchase("health") and HeroUpgrades.price("health") == -1, "three-tier cap cannot charge again")
	_check(wallet.balance == 40000, "six complete upgrades cost $210000")
	Settings.use_file(SAVE)
	_check(HeroUpgrades.tier("health") == 3 and Settings.get_value("cash") == 40000, "cash and tiers survive disk reload")
	shops.apply_upgrades()
	_check(hero.max_health == 175 and hero.punch_multiplier == 1.75 and hero.slam_multiplier == 1.75, "combat upgrades apply without stacking twice")
	_check((hero.get_mode(&"OnFoot") as OnFootMode).super_speed == 105 and (hero.get_mode(&"Flight") as FlightMode).boost_speed == 262.5, "speed and flight tunables scale by 75 percent")
	var target: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	add_child(target)
	target.position = Vector3(0, 0, -1.5)
	target.set_physics_process(false)
	hero.input.aim = Vector3.FORWARD
	hero.set_mode(&"Melee")
	(hero.get_mode(&"Melee") as MeleeMode).physics_update(0.17)
	_check(is_equal_approx(target.health, 12.5), "upgraded punch sends 87.5 damage through Combat")
	target.position = Vector3(14, 0, 0)
	hero.position = Vector3.ZERO
	hero._slam(Hero.MAX_FALL_SPEED)
	_check(target.is_down(), "upgraded slam reaches a target beyond the base radius")
	target.queue_free()
	hero.set_mode(&"OnFoot")
	var car := DriveVehicle.new()
	add_child(car)
	var drive := hero.get_mode(&"Drive") as DriveMode
	drive.car = car
	hero.set_mode(&"Drive")
	hero.health = 175
	hero.take_hit(35, Vector3.ZERO)
	_check(hero.health == 155, "car armor reduces incoming driver damage")
	shops.active = CityShops._location("garage", "Garage", &"garage", Vector3.ZERO)
	wanted.set_stars(3)
	var officer: PoliceOfficer = load("res://scenes/npc/police_officer.tscn").instantiate()
	add_child(officer)
	officer.global_position = Vector3(0, 0, 5)
	officer.set_physics_process(false)
	await get_tree().physics_frame
	var before := wallet.balance
	_check(shops.respray().contains("see you") and wanted.stars == 3 and wallet.balance == before, "visible police reject payment and keep wanted stars")
	officer.global_position = Vector3(0, 0, 500)
	var patrol := PoliceCar.new()
	patrol.suspect_id = Net.local_id()
	add_child(patrol)
	patrol.global_position = Vector3(0, 0, 10)
	patrol.set_physics_process(false)
	wanted.pursuit.cars.append(patrol)
	_check(shops.respray().contains("see you") and wallet.balance == before, "patrol car sight also blocks respray")
	patrol.global_position = Vector3(0, 0, 500)
	var paint := car.paint
	_check(shops.respray().contains("Wanted cleared") and wanted.stars == 0 and wallet.balance == before - 1500 and car.paint != paint, "unseen respray charges $500 per star, changes paint and clears wanted")
	_check(wanted.pursuit.cars.is_empty(), "paid garage removes the patrol response immediately")
	_check(shops.respray().contains("No wanted") and wallet.balance == before - 1500, "repeat respray cannot charge after stars clear")
	wanted.set_stars(5)
	wallet.spend(wallet.balance)
	_check(shops.respray().contains("Not enough") and wanted.stars == 5, "unaffordable respray preserves pursuit")
	hero.set_mode(&"OnFoot")
	_check(shops.respray().contains("Bring a car"), "garage requires an occupied car")
	wanted.set_stars(0)
	shops.active = CityShops._location("home", "Apartment", &"safehouse", Vector3(100, 0, 100))
	shops.visit_safehouse()
	_check(hero.health == 175, "entering safehouse restores upgraded max health")
	Settings.use_file(SAVE)
	WorldOrigin.shift(Vector3(500, 0, 500))
	hero.set_mode(&"KnockedOut")
	(hero.get_mode(&"KnockedOut") as KnockedOutMode).physics_update(4.0)
	_check(hero.world_position().distance_to(Vector3(100, 0.3, 100)) < 0.1 and hero.health == 175, "ordinary knockout returns to saved world position after origin shift")
	hero.set_mode(&"OnFoot")
	hero.global_position = Vector3.ZERO
	wanted.set_stars(2)
	hero.set_mode(&"KnockedOut")
	wanted._physics_process(2.1)
	_check(hero.mode.name == &"OnFoot" and hero.world_position().distance_to(Vector3(100, 0.3, 100)) < 0.1, "BUSTED returns to same saved safehouse")
	var streamed := false
	var calls: Array[Vector3] = []
	shops.travel = func(at: Vector3) -> void: calls.append(at)
	streamed = shops.respawn()
	_check(streamed and calls == [Vector3(100, 0, 100)], "distant recovery uses streaming-aware travel callback")
	shops.close()
	shops._physics_process(0.1)
	_check(shops.active.is_empty(), "closing does not reopen without re-entry")
	HeroUpgrades.reset()
	shops.apply_upgrades()
	_check(hero.max_health == 100 and (hero.get_mode(&"OnFoot") as OnFootMode).super_speed == 60, "reset removes upgrades and restores base effects")
	DirAccess.remove_absolute(SAVE)
	Settings.use_file("")
	print("Shops: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)
