extends Node
## Headless check of landmark exploration (LandmarkDiscovery and the HUD):
## - Where the landmarks are: their latitudes and longitudes, through
##   Geo.to_world, land on the points tools/citygen/landmarks.py anchors
##   Columbus Circle, the Unisphere and the Wonder Wheel to, and every one is
##   inside the map.
## - No two landmarks' radii overlap (one spot never finds two at once), a spot
##   finds only its own landmark and only once, and nothing is found from above
##   MAX_ALTITUDE.
## - In the real city: the hero starting at Times Square discovers it once the
##   ground has loaded, and the HUD counts it and shows its banner. Then the
##   hero is sent (the Go to box's travel_to) to the Flatiron Building, 1.9 km
##   away, past a floating origin shift: it's discovered there too, the count
##   is 2, and the marker points to the nearest landmark left.
## Run: godot --headless --path . res://tests/landmark_discovery_test.tscn -- --solo=1 [--tiles=DIR | --tiles_url=URL]

const SETTINGS_FILE := "user://landmark_discovery_test_settings.cfg"
const MAX_LOAD_WAIT := 90.0
## (east, north) anchors in tools/citygen/landmarks.py (Landmark.at, CC_CENTER).
const ANCHORS := {
	"Columbus Circle": Vector2(304.61, 1118.08),
	"Unisphere": Vector2(11859.8, -1278.2),
	"Wonder Wheel": Vector2(538.0, -20425.5),
}

var _world: Game
var _city: CityStreamer
var _hero: Hero
var _checks: Array[String] = []
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Tester")
	_check_positions()
	_check_rules()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_hero = _world.get_node("Hero")
	if not await _wait_for_city():
		_check(false, "the city loaded at Times Square")
		_finish()
		return
	await _check_in_city()
	_finish()


func _index(landmark_name: String) -> int:
	for n in LandmarkDiscovery.LANDMARKS.size():
		if LandmarkDiscovery.LANDMARKS[n].name == landmark_name:
			return n
	return -1


func _check_positions() -> void:
	var discovery := LandmarkDiscovery.new()
	add_child(discovery)
	for landmark_name: String in ANCHORS:
		var at := discovery.positions[_index(landmark_name)]
		var anchor: Vector2 = ANCHORS[landmark_name]
		var off := Vector2(at.x - anchor.x, -at.z - anchor.y).length()
		_check(off < 1.0, "%s is where the tiles anchor it (%.2f m off)" % [landmark_name, off])
	var inside := true
	for at in discovery.positions:
		inside = inside and absf(at.x) < 30000.0 and absf(at.z) < 30000.0
	_check(inside, "every landmark is on the map")
	discovery.queue_free()


func _check_rules() -> void:
	var discovery := LandmarkDiscovery.new()
	add_child(discovery)
	var closest := INF
	var pair := ""
	for a in discovery.total():
		for b in range(a + 1, discovery.total()):
			var gap := discovery.flat_distance(a, discovery.positions[b]) \
				- float(LandmarkDiscovery.LANDMARKS[a].radius) - float(LandmarkDiscovery.LANDMARKS[b].radius)
			if gap < closest:
				closest = gap
				pair = "%s / %s" % [LandmarkDiscovery.LANDMARKS[a].name, LandmarkDiscovery.LANDMARKS[b].name]
	_check(closest > 0.0, "no two landmarks' radii overlap (closest: %s, %.0f m apart)" % [pair, closest])
	var events: Array = []
	discovery.discovered.connect(func(n: int, found: int, total: int) -> void: events.append([n, found, total]))
	var esb := _index("Empire State Building")
	var high := discovery.positions[esb] + Vector3.UP * (LandmarkDiscovery.MAX_ALTITUDE + 50.0)
	_check(discovery.check(high) == 0, "nothing is found from above %.0f m" % LandmarkDiscovery.MAX_ALTITUDE)
	var edge := discovery.positions[esb] + Vector3(LandmarkDiscovery.LANDMARKS[esb].radius + 5.0, 10.0, 0.0)
	_check(discovery.check(edge) == 0, "just outside a landmark's radius finds nothing")
	var near := discovery.positions[esb] + Vector3(LandmarkDiscovery.LANDMARKS[esb].radius - 5.0, 300.0, 0.0)
	_check(discovery.check(near) == 1 and events == [[esb, 1, discovery.total()]],
		"inside its radius (flying by its crown) finds it, once (%s)" % [events])
	_check(discovery.check(near) == 0 and discovery.found_count() == 1, "and not again")
	_check(discovery.nearest_unfound(discovery.positions[esb]) != esb, "the nearest left skips the ones found")
	discovery.queue_free()


func _check_in_city() -> void:
	var discovery := _world.discovery
	var hud: GameHud = _world.get_node("HUD/GameHud")
	await _wait(0.5)
	var times_square := _index("Times Square")
	_check(discovery.found[times_square] and discovery.found_count() == 1,
		"starting at Times Square discovers it once the ground has loaded (%d found)" % discovery.found_count())
	_check(not hud._banners.is_empty() and hud._banners[0][0] == times_square, "the HUD shows its banner")
	_check(hud.discovery == discovery, "the HUD counts it")
	var flatiron := _index("Flatiron Building")
	var shift_before := WorldOrigin.offset
	_world.travel_to(discovery.positions[flatiron])
	var started := Time.get_ticks_msec()
	while _hero.frozen and Time.get_ticks_msec() - started < MAX_LOAD_WAIT * 1000.0:
		await _wait(0.25)
	await _wait(0.5)
	_check(WorldOrigin.offset != shift_before, "the floating origin moved on the way (%s)" % WorldOrigin.offset)
	_check(discovery.found[flatiron] and discovery.found_count() == 2,
		"standing by the Flatiron Building discovers it after the shift (%.0f m from its middle, %d found)" % [
			discovery.flat_distance(flatiron, _hero.world_position()), discovery.found_count()])
	var next := discovery.nearest_unfound(_hero.world_position())
	_check(next == _index("Empire State Building"),
		"the marker points to the nearest landmark left (%s)" % LandmarkDiscovery.LANDMARKS[next].name)


func _wait_for_city() -> bool:
	var started := Time.get_ticks_msec()
	while _city.loaded_counts[0] == 0 or _city.pending_count() > 0 or _hero.frozen:
		await _wait(0.5)
		if Time.get_ticks_msec() - started > MAX_LOAD_WAIT * 1000.0:
			return false
	return true


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _check(ok: bool, what: String) -> void:
	_checks.append(("ok      " if ok else "FAILED  ") + what)
	if not ok:
		_failed += 1


func _finish() -> void:
	print("\n".join(_checks))
	print("%d checks, %d failed" % [_checks.size(), _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	get_tree().quit(1 if _failed else 0)
