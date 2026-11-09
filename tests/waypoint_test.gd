extends Node
## Headless check of the player's waypoint (Waypoint), in the real city at
## Times Square:
## - Its compass points and distances read right ("NE", "85 m", "1.24 km").
## - The options menu's Mark, with a typed latitude and longitude (the Empire
##   State Building; no internet needed), closes the menu and sets the
##   waypoint there without moving the hero; the HUD tells of it. Distance
##   (about 1060 m) and bearing (south) are right, and both survive a
##   floating-origin shift. Off the map, Mark keeps the menu open.
## - The HUD places its marker at the screen's edge while it's behind the
##   camera, and on screen when the camera turns to it.
## - The menu's Clear clears it and then greys out.
## - G (the "waypoint" action) marks the street the camera looks down at,
##   near the hero; G again, looking at it, clears it.
## - Walking (real HeroInput) to a waypoint a few dozen meters down the
##   street says it's reached and clears it; one set where the hero stands
##   waits for them to leave first.
## - An address's waypoint (inside its building, here a block off Broadway)
##   moves onto the nearest sidewalk once its streets are loaded.
## Uses a settings file of its own, not the player's.
## Run: godot --headless --path . res://tests/waypoint_test.tscn -- --solo=1 [--tiles=DIR]

const SETTINGS_FILE := "user://waypoint_test_settings.cfg"
const MAX_LOAD_WAIT := 90.0
const EMPIRE_STATE := "40.748441, -73.985656"

var _world: Game
var _city: CityStreamer
var _options: OptionsPanel
var _hud: GameHud
var _hero: Hero
var _camera: ThirdPersonCamera
var _waypoint: Waypoint
var _messages: Array[String] = []
var _checks: Array[String] = []
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Tester")  # (no name prompt)
	_check_formatting()
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_options = _world.get_node("HUD/OptionsPanel")
	_hud = _world.get_node("HUD/GameHud")
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_waypoint = _world.get_node("Waypoint")
	_waypoint.changed.connect(func(message: String) -> void: _messages.append(message))
	get_tree().root.size = Vector2i(1280, 720)  # (room for markers: headless windows are tiny)
	if not await _wait_for_city():
		_check(false, "the city loaded at Times Square")
		_finish()
		return
	_check(_hud.waypoint == _waypoint and _options.waypoint == _waypoint and InputMap.has_action(&"waypoint"),
		"Game hands the waypoint to the HUD and the menu, and G is bound")
	await _check_mark_from_menu()
	await _check_mark_by_looking()
	await _check_address_sidewalk()
	await _check_arrival()
	_finish()


func _check_formatting() -> void:
	_check(Waypoint.compass_point(0.0) == "N" and Waypoint.compass_point(44.0) == "NE"
		and Waypoint.compass_point(180.0) == "S" and Waypoint.compass_point(337.6) == "N"
		and Waypoint.compass_point(-90.0) == "W", "compass points")
	_check(Waypoint.format_distance(84.6) == "85 m" and Waypoint.format_distance(1240.0) == "1.24 km"
		and Waypoint.format_distance(12345.0) == "12.3 km", "distances")


func _check_mark_from_menu() -> void:
	var start := _hero.world_position()
	_options.open()
	_options._address.text = "42.6526, -73.7562"  # Albany
	_options._address_mark.pressed.emit()
	_check(_options.visible and not _waypoint.is_set() and _options._address_note.text.contains("isn't on the city's map"),
		"Mark somewhere off the map keeps the menu open and sets nothing")
	_check(_options._waypoint_clear.disabled, "Clear is greyed out without a waypoint")
	var went: Array = []
	_options.place_chosen.connect(func(at: Vector3) -> void: went.append(at), CONNECT_ONE_SHOT)
	_options._address.text = EMPIRE_STATE
	_options._address_mark.pressed.emit()
	var address := Geo.to_world(40.748441, -73.985656)
	_check(not _options.visible and went.is_empty() and _waypoint.is_set()
		and _waypoint.target.distance_to(address) < 0.01 and _waypoint.label == EMPIRE_STATE,
		"Mark closes the menu and sets the waypoint at the address, without going there")
	await _wait(0.3)
	_check(_hero.world_position().distance_to(start) < 2.0 and not _hero.frozen, "the hero stays where it was")
	_check(_hud.current_notices().size() > 0 and _hud.current_notices()[-1].begins_with("Waypoint set"),
		"the HUD tells of it (%s)" % ", ".join(_hud.current_notices()))
	var distance := _waypoint.distance()
	_check(absf(distance - Vector2(address.x - _hero.world_position().x, address.z - _hero.world_position().z).length()) < 0.01
		and distance > 1000.0 and distance < 1120.0, "about 1.06 km away (%.1f m)" % distance)
	_check(Waypoint.compass_point(_waypoint.bearing()) == "S", "to the south (%.1f degrees)" % _waypoint.bearing())
	# A floating-origin shift moves the scene, not the waypoint.
	var bearing := _waypoint.bearing()
	WorldOrigin.shift(Vector3(400.0, 0.0, -300.0))
	_check(_waypoint.target.distance_to(address) < 0.01 and absf(_waypoint.distance() - distance) < 0.05
		and absf(_waypoint.bearing() - bearing) < 0.01, "an origin shift changes neither its place, distance nor bearing")
	# Behind the camera (it looks north at the start): at the bottom edge.
	_camera.yaw = 0.0
	_camera.pitch = -0.15
	await _wait(0.2)
	var placed := _hud._place_marker(WorldOrigin.to_local(_waypoint.target))
	_check(not placed.is_empty() and not placed.on_screen and (placed.direction as Vector2).y > 0.5,
		"behind the camera, its marker sits at the screen's bottom edge (%s)" % placed.get("direction"))
	_camera.yaw = PI  # facing south
	_camera.pitch = 0.0
	await _wait(0.2)
	placed = _hud._place_marker(WorldOrigin.to_local(_waypoint.target))
	_check(not placed.is_empty() and placed.on_screen, "turned to face it, the marker is on screen (%s)" % placed.get("point"))
	_options.open()
	_options._refresh()
	_check(not _options._waypoint_clear.disabled, "Clear is there to press with a waypoint set")
	_options._waypoint_clear.pressed.emit()
	_options._refresh()
	_check(not _waypoint.is_set() and _options._waypoint_clear.disabled and _messages[-1] == "Waypoint cleared",
		"Clear clears it")
	_options.close()


func _check_mark_by_looking() -> void:
	_camera.yaw = 0.0
	_camera.pitch = -0.3  # down the street ahead
	await _wait(0.3)
	var camera := get_viewport().get_camera_3d()
	var press := InputEventAction.new()
	press.action = &"waypoint"
	press.pressed = true
	Input.parse_input_event(press)
	await _wait(0.1)
	var release := InputEventAction.new()
	release.action = &"waypoint"
	Input.parse_input_event(release)
	var away := _waypoint.distance()
	var below := _hero.world_position().y - _waypoint.target.y
	_check(_waypoint.is_set() and _waypoint.label == "Marked spot" and away > 4.0 and away < 80.0
		and absf(below) < 3.0, "G marks the street the camera looks down at (%.1f m away, %.1f m below the hero)" % [away, below])
	_check(camera.global_position.direction_to(WorldOrigin.to_local(_waypoint.target)).angle_to(-camera.global_basis.z) < 0.05,
		"right where the camera looks")
	_waypoint.mark_where_looking(camera)
	_check(not _waypoint.is_set() and _messages[-1] == "Waypoint cleared", "G again, looking at it, clears it")
	# The sky, from high over the towers.
	var sky := Camera3D.new()
	_world.add_child(sky)
	sky.global_position = _hero.global_position + Vector3.UP * 900.0
	sky.rotation = Vector3(0.4, 0.0, 0.0)
	_waypoint.mark_where_looking(sky)
	_check(not _waypoint.is_set() and _messages[-1].begins_with("Look at the city"), "the sky can't be marked")
	# Straight down from there: past the loaded collision's reach? Still the city or the ground.
	sky.rotation = Vector3(-0.6, 0.0, 0.0)
	var spot := _waypoint.look_spot(sky)
	_check(spot != Vector3.INF and spot.y < 400.0, "looking down from high up marks the city below (%s)" % spot)
	sky.queue_free()


func _check_address_sidewalk() -> void:
	# Midblock west of Broadway at 45th St: inside the buildings.
	var address := _hero.world_position() + Vector3(-60.0, 0.0, -40.0)
	address.y = 0.0
	_waypoint.set_target(address, "In a building", true)
	await _wait(0.2)
	var moved := Vector2(_waypoint.target.x - address.x, _waypoint.target.z - address.z).length()
	var on_lane := _city.sidewalk_near(_waypoint.target, 5.0)
	_check(moved > 0.5 and moved < Waypoint.STREET_SEARCH and on_lane != Vector3.INF
		and Vector2(on_lane.x - _waypoint.target.x, on_lane.z - _waypoint.target.z).length() < 0.1,
		"an address's waypoint moves onto the nearest sidewalk (%.1f m)" % moved)
	_waypoint.set_target(address, "Exactly here")
	await _wait(0.2)
	_check(_waypoint.target == address, "a marked spot stays exactly where it was marked")
	_waypoint.clear()


func _check_arrival() -> void:
	_waypoint.set_target(_hero.world_position())
	await _wait(0.5)
	_check(_waypoint.is_set(), "set where the hero stands, it isn't reached until they leave and come back")
	_waypoint.clear()
	# Thirty-five meters up Broadway (north at the start), walked with HeroInput.
	_camera.yaw = 0.0
	_camera.pitch = -0.15
	var goal := _hero.world_position() + Vector3(0.0, 0.0, -35.0)
	_waypoint.set_target(goal, "Up the street")
	var started := Time.get_ticks_msec()
	var input: PlayerInput = _world.get_node("PlayerInput")
	input.process_mode = Node.PROCESS_MODE_DISABLED  # (drives the hero below instead)
	while _waypoint.is_set() and Time.get_ticks_msec() - started < 20000:
		var toward := goal - _hero.world_position()
		toward.y = 0.0
		_hero.input.move = toward.normalized()
		_hero.input.stick = Vector2(0.0, -1.0)
		await get_tree().physics_frame
	_hero.input.clear()
	input.process_mode = Node.PROCESS_MODE_INHERIT
	_check(not _waypoint.is_set() and _messages[-1] == "You reached your waypoint: Up the street",
		"walking there reaches it, says so and clears it (%s)" % _messages[-1])
	_check(Vector2(goal.x - _hero.world_position().x, goal.z - _hero.world_position().z).length() < Waypoint.ARRIVE_RADIUS + 1.0,
		"within %d m of it" % int(Waypoint.ARRIVE_RADIUS))


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
	get_tree().paused = false
	get_tree().quit(1 if _failed else 0)
