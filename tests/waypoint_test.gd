extends Node
## Headless check of the player's waypoint (Waypoint, GameHud's compass
## line, the options menu's Mark and Clear), in the real city at Times Square:
## - G looking at the sky marks nothing and says why; looking at the street
##   just in front of the hero (closer than Waypoint.ARRIVE_RADIUS) neither.
## - G looking up Broadway marks the street there; G again clears it, and G
##   is ignored while the options menu is open.
## - The compass bearing: ahead is 0, a quarter turn left puts it on the right.
## - It survives a floating origin shift (same world spot, same distance).
## - It's saved, and a new Waypoint reads it back.
## - The hero, walking up Broadway with W held, reaches it: it clears itself
##   and says "Reached".
## - The options menu: a latitude and longitude and Mark put the waypoint on
##   the Empire State Building (about 1.06 km off), close the menu and leave
##   the hero where it is; somewhere off the map marks nothing; Clear clears.
## Uses a settings file of its own, not the player's.
## Run: godot --headless --path . res://tests/waypoint_test.tscn -- --solo=1 [--tiles=DIR | --tiles_url=URL]

const SETTINGS_FILE := "user://waypoint_test_settings.cfg"
const MAX_LOAD_WAIT := 90.0
const MAX_WALK := 40.0
const EMPIRE_STATE := "40.748441, -73.985656"

var _world: Game
var _city: CityStreamer
var _options: OptionsPanel
var _hero: Hero
var _camera: ThirdPersonCamera
var _waypoint: Waypoint
var _hud: GameHud
var _checks: Array[String] = []
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	Settings.use_file(SETTINGS_FILE)
	Settings.set_value("player_name", "Tester")  # (no name prompt)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_options = _world.get_node("HUD/OptionsPanel")
	_hud = _world.get_node("HUD/GameHud")
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_waypoint = _world.get_node("Waypoint")
	if not await _wait_for_city():
		_check(false, "the city loaded at Times Square")
		_finish()
		return
	_check(not _waypoint.is_set() and _hud.waypoint == _waypoint, "no waypoint at first; the HUD has it")
	await _check_marking()
	await _check_walking_there()
	await _check_menu()
	_finish()


func _check_marking() -> void:
	var failures: Array[String] = []
	_waypoint.mark_failed.connect(func(reason: String) -> void: failures.append(reason))
	_camera.yaw = _hero.facing
	_camera.pitch = 1.1  # the sky
	await _frames(3)
	await _press_g()
	_check(not _waypoint.is_set() and failures.size() == 1 and failures[0].begins_with("Nothing to mark")
		and _hud.current_notices().has(failures[0]), "G at the sky marks nothing and says so (%s)" % ", ".join(failures))
	_camera.pitch = -1.0  # the street at the hero's feet
	await _frames(3)
	await _press_g()
	_check(not _waypoint.is_set() and failures.size() == 2 and failures[1].contains("right here"),
		"G at the street under the hero marks nothing (%s)" % (failures[1] if failures.size() > 1 else "no reason"))
	_camera.pitch = -0.02  # up Broadway
	await _frames(3)
	await _press_g()
	var distance := _waypoint.ground_distance()
	_check(_waypoint.is_set() and distance > Waypoint.ARRIVE_RADIUS and distance < Waypoint.MARK_RANGE,
		"G up Broadway marks a spot %.0f m ahead (%s)" % [distance, ", ".join(failures)])
	_check(_waypoint.label == Waypoint.DEFAULT_LABEL and _hud.current_notices().has(
		"Waypoint set: %s away" % GameHud.distance_text(distance)), "the HUD says it's set and how far")
	_check(absf(_waypoint.bearing_from_view()) < 0.1, "the compass points straight ahead (%.2f rad)" % _waypoint.bearing_from_view())
	_camera.yaw += PI * 0.5  # a quarter turn left: it's on the right
	await _frames(2)
	_check(absf(_waypoint.bearing_from_view() - PI * 0.5) < 0.1,
		"turned left, it's to the right (%.2f rad)" % _waypoint.bearing_from_view())
	_camera.yaw = _hero.facing
	var saved: Variant = Settings.get_value(Waypoint.SETTING, [])
	var spot := _waypoint.world_position
	_check(saved is Array and (saved as Array).size() == 4 and Vector3(saved[0], saved[1], saved[2]).is_equal_approx(spot),
		"it's saved in the settings")
	var reread := Waypoint.new()
	reread.hero = _hero
	reread.camera_rig = _camera
	add_child(reread)
	_check(reread.is_set() and reread.world_position.is_equal_approx(spot), "a new game reads it back")
	reread.queue_free()
	# A floating origin shift: the same spot in the world, the same distance.
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	await _frames(2)
	_check(_waypoint.world_position == spot and absf(_waypoint.ground_distance() - distance) < 0.5,
		"it stays put through a floating origin shift (%.1f m, was %.1f m)" % [_waypoint.ground_distance(), distance])
	WorldOrigin.shift(Vector3(-500.0, 0.0, 0.0))
	await _frames(2)
	# The options menu open: G is the menu's, not the waypoint's.
	_options.open()
	await _press_g()
	_check(_waypoint.is_set(), "G does nothing with the options menu open")
	_options.close(false, false)
	await _frames(2)
	await _press_g()
	_check(not _waypoint.is_set() and _hud.current_notices().has("Waypoint cleared"), "G again clears it")
	_check((Settings.get_value(Waypoint.SETTING, [0]) as Array).is_empty(), "and the setting with it")
	await _press_g()
	_check(_waypoint.is_set() and _waypoint.world_position.distance_to(spot) < 1.0, "G marks it again")


func _check_walking_there() -> void:
	var reached: Array[String] = []
	_waypoint.reached.connect(func(what: String) -> void: reached.append(what), CONNECT_ONE_SHOT)
	var start := _hero.world_position()
	var target := _waypoint.world_position
	var to := Vector2(target.x - start.x, target.z - start.z)
	_camera.yaw = atan2(-to.x, -to.y)
	_camera.pitch = -0.15
	Input.action_press(&"move_forward")
	var started := Time.get_ticks_msec()
	while reached.is_empty() and Time.get_ticks_msec() - started < MAX_WALK * 1000.0:
		await _frames(1)
	Input.action_release(&"move_forward")
	var walked := Vector2(_hero.world_position().x - start.x, _hero.world_position().z - start.z).length()
	_check(reached == [Waypoint.DEFAULT_LABEL] and not _waypoint.is_set(),
		"walking up Broadway reaches it after %.0f m in %.1f s" % [walked, (Time.get_ticks_msec() - started) / 1000.0])
	_check(_hud.current_notices().has("Reached Waypoint") and not _hud.current_notices().has("Waypoint cleared"),
		"the HUD says \"Reached\" (and not \"cleared\")")


func _check_menu() -> void:
	await _frames(10)  # (the "cleared" notice)
	var before := _hero.world_position()
	_options.open()
	_check(_options._address_mark.is_visible_in_tree() and _options._waypoint_clear.disabled,
		"the Go to box has Mark; Clear is off with no waypoint")
	_options._address.text = "42.6526, -73.7562"  # Albany
	_options._address_mark.pressed.emit()
	_check(_options.visible and not _waypoint.is_set() and _options._address_note.text.contains("isn't on the city's map"),
		"Mark somewhere off the map marks nothing and says so")
	var chosen: Array = []
	_options.place_chosen.connect(func(at: Vector3) -> void: chosen.append(at), CONNECT_ONE_SHOT)
	_options._address.text = EMPIRE_STATE
	_options._address_mark.pressed.emit()
	var address := Geo.to_world(40.748441, -73.985656)
	var off := Vector2(_waypoint.world_position.x - address.x, _waypoint.world_position.z - address.z).length()
	_check(_waypoint.is_set() and off < 0.01 and _waypoint.label == EMPIRE_STATE,
		"Mark puts the waypoint on the Empire State Building (%s, %.2f m off)" % [_waypoint.label, off])
	_check(not _options.visible and chosen.is_empty(), "the menu closes, and nobody travels")
	await _frames(5)
	_check(_hero.world_position().distance_to(before) < 2.0 and not _hero.frozen, "the hero stays where it was")
	var distance := _waypoint.ground_distance()
	var expected := Vector2(address.x - before.x, address.z - before.z).length()
	_check(absf(distance - expected) < 1.0 and distance > 800.0, "it's %s away" % GameHud.distance_text(distance))
	_options.open()
	_check(not _options._waypoint_clear.disabled and _options._waypoint_note.text.contains("m away"),
		"the menu's Waypoint row says what and how far (%s)" % _options._waypoint_note.text)
	_options._waypoint_clear.pressed.emit()
	_check(not _waypoint.is_set() and _options._waypoint_clear.disabled and _options._waypoint_note.text.begins_with("None"),
		"Clear clears it")
	_options.close(false, false)


func _press_g() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_G
		key.keycode = KEY_G
		key.pressed = pressed
		Input.parse_input_event(key)
		await _frames(2)


func _wait_for_city() -> bool:
	var started := Time.get_ticks_msec()
	while _city.loaded_counts[0] == 0 or _city.pending_count() > 0 or _hero.frozen:
		await _wait(0.5)
		if Time.get_ticks_msec() - started > MAX_LOAD_WAIT * 1000.0:
			return false
	return true


func _frames(count: int) -> void:
	for n in count:
		await get_tree().physics_frame
	await get_tree().process_frame


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
