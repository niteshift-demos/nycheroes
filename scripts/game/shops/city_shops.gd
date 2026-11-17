class_name CityShops
extends Node
## Local services: entry-triggered shops, garages and safehouse doors. Positions
## remain absolute through origin shifts; nearby markers snap onto loaded streets.

signal entered(location: Dictionary)
signal changed
signal exited

const COLORS := {&"shop": Color(0.3, 0.9, 0.75), &"garage": Color(1.0, 0.65, 0.2), &"safehouse": Color(0.4, 0.7, 1.0)}
var hero: Hero
var wallet: Wallet
var wanted: Wanted
var city: CityStreamer
var radar: Radar
var time_of_day: TimeOfDay
var can_enter: Callable
var travel: Callable
var locations: Array[Dictionary] = []
var active: Dictionary = {}
var _inside := ""
var _speed := 60.0
var _cruise := 33.0
var _boost := 150.0


func _ready() -> void:
	if LaunchOptions.get_string("upgrades") == "reset":
		HeroUpgrades.reset()
	_speed = (hero.get_mode(&"OnFoot") as OnFootMode).super_speed
	_cruise = (hero.get_mode(&"Flight") as FlightMode).cruise_speed
	_boost = (hero.get_mode(&"Flight") as FlightMode).boost_speed
	apply_upgrades()
	hero.safehouse_respawn = respawn
	if locations.is_empty():
		locations = catalog()
	for location in locations:
		_register(location)


static func catalog() -> Array[Dictionary]:
	# Landmark references and authored door offsets are documented in SHOPS.md.
	var union := Geo.to_world(40.73556, -73.99056)
	var brooklyn := Geo.to_world(40.69278, -73.99000)
	var bronx := Geo.to_world(40.82917, -73.92639)
	return [
		_location("union_supply", "Hero Supply · Union Square", &"shop", union + Vector3(55, 0, 15)),
		_location("brooklyn_supply", "Hero Supply · Downtown Brooklyn", &"shop", brooklyn + Vector3(-45, 0, 15)),
		_location("bronx_supply", "Hero Supply · The Bronx", &"shop", bronx + Vector3(150, 0, 150)),
		_location("union_garage", "Precinct Payoff · Union Square", &"garage", union + Vector3(80, 0, 100)),
		_location("brooklyn_garage", "Precinct Payoff · Brooklyn", &"garage", brooklyn + Vector3(-75, 0, 130)),
		_location("union_home", "Union Square apartment", &"safehouse", union + Vector3(90, 0, -110)),
		_location("brooklyn_home", "Brooklyn apartment", &"safehouse", brooklyn + Vector3(100, 0, 65)),
	]


static func _location(id: String, label: String, kind: StringName, at: Vector3) -> Dictionary:
	return {"id": id, "label": label, "kind": kind, "position": at, "color": COLORS[kind], "resolved": false}


func _register(location: Dictionary) -> void:
	if radar:
		radar.add_blip(StringName("shops/" + location.id), location.position, location.kind, location.color)


func _physics_process(_delta: float) -> void:
	if hero.frozen or hero.mode.name == &"KnockedOut" or (can_enter.is_valid() and not can_enter.call() and active.is_empty()):
		return
	var nearby := ""
	for location in locations:
		var at: Vector3 = location.position
		if hero.world_position().distance_to(at) > 200.0:
			continue
		if not location.resolved and city and city.has_collision_at(at):
			_resolve(location)
			at = location.position
		var offset := hero.world_position() - at
		if Vector2(offset.x, offset.z).length() > 12.0 or absf(offset.y) > 4.0:
			continue
		nearby = location.id
		if nearby != _inside and active.is_empty() and (not can_enter.is_valid() or can_enter.call()):
			active = location
			_inside = nearby
			if location.kind == &"safehouse":
				visit_safehouse()
			# Reproducible web QA fixture: seed heat only once the car is inside.
			# Sight and payment checks remain identical to ordinary play.
			if LaunchOptions.get_string("shop_check") == "garage" and location.kind == &"garage" \
					and hero.mode.name == &"Drive" and wanted:
				wanted.set_stars(3)
			entered.emit(location)
		break
	_inside = nearby
	if not active.is_empty() and nearby != active.id:
		close()
		exited.emit()


## Snap authored doors to the nearest sidewalk segment, using its true altitude.
func _resolve(location: Dictionary) -> void:
	var at: Vector3 = location.position
	var best := INF
	for lane in city.lanes_near(at, 100.0):
		for i in lane.size() - 1:
			var point := Geometry3D.get_closest_point_to_segment(at, lane[i], lane[i + 1])
			var distance := point.distance_squared_to(at)
			if distance < best:
				best = distance
				location.position = point
	if best < INF:
		location.resolved = true
		_register(location)


func close() -> void:
	active = {}


func purchase(id: String) -> bool:
	if active.get("kind") != &"shop" or not HeroUpgrades.purchase(id, wallet):
		return false
	apply_upgrades()
	changed.emit()
	return true


func apply_upgrades() -> void:
	hero.max_health = Hero.MAX_HEALTH * HeroUpgrades.multiplier("health")
	hero.health = minf(hero.health, hero.max_health)
	hero.punch_multiplier = HeroUpgrades.multiplier("punch")
	hero.slam_multiplier = HeroUpgrades.multiplier("slam")
	hero.car_armor_multiplier = HeroUpgrades.multiplier("armor")
	(hero.get_mode(&"OnFoot") as OnFootMode).super_speed = _speed * HeroUpgrades.multiplier("speed")
	var flight := hero.get_mode(&"Flight") as FlightMode
	flight.cruise_speed = _cruise * HeroUpgrades.multiplier("flight")
	flight.boost_speed = _boost * HeroUpgrades.multiplier("flight")


## Recheck sight at payment time: a searching flag can be up to half a second old.
func respray() -> String:
	if active.get("kind") != &"garage":
		return "Enter a Precinct Payoff garage."
	var drive := hero.get_mode(&"Drive") as DriveMode
	if hero.mode != drive or not is_instance_valid(drive.car):
		return "Bring a car into the garage."
	if not wanted or wanted.stars == 0:
		return "No wanted stars to clear."
	if wanted.police_see_hero():
		return "Police can see you. Break line of sight first."
	var cost := 500 * wanted.stars
	if not wallet.spend(cost):
		return "Not enough cash — need %s." % Wallet.format_cash(cost)
	drive.car.paint = fposmod(floorf(drive.car.paint) + 1.0, 12.0)
	drive.car._draw()
	wanted.set_stars(0)
	wanted._clear_response()
	if wanted.pursuit:
		wanted.pursuit.advance(0.0)
	changed.emit()
	return "Paid %s. New paint. Wanted cleared." % Wallet.format_cash(cost)


func visit_safehouse() -> void:
	if active.get("kind") != &"safehouse":
		return
	hero.health = hero.max_health
	Settings.set_value("safehouse_position", active.position)
	Settings.set_value("safehouse_name", active.label)


func sleep() -> void:
	if active.get("kind") == &"safehouse" and time_of_day:
		time_of_day.set_clock(fposmod(time_of_day.clock + 8.0, 24.0))
		visit_safehouse()
		changed.emit()


## Called by both recovery paths. Game.travel_to holds the hero until collision
## streams in; standalone tests can exercise the same saved world coordinates.
func respawn() -> bool:
	var at: Variant = Settings.get_value("safehouse_position", Vector3.INF)
	if not at is Vector3 or not (at as Vector3).is_finite():
		return false
	if travel.is_valid():
		travel.call(at)
	else:
		hero.global_position = WorldOrigin.to_local(at) + Vector3.UP * 0.3
	return true


## Nearby doors use the ordinary HUD's projected 3D marker style.
func markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location in locations:
		if hero.world_position().distance_to(location.position) < 350.0:
			result.append(location)
	return result
