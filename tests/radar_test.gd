extends Node
## Synthetic radar regression: blip lifecycle, node tracking, camera-relative
## transforms, origin shifts, street unloads, map pan/zoom, waypoint input
## and standing police shown only while the local hero is wanted.
## Run: godot --headless --path . res://tests/radar_test.tscn

var _failed := 0


func _ready() -> void:
	var radar := Radar.new()
	add_child(radar)
	_check(radar.enabled == (LaunchOptions.get_string("radar", "1") != "0"), "launch option sets initial radar visibility")
	radar.set_process(false)
	radar.size = Vector2(204, 204)
	radar.world_center = Vector3(1000, 0, -2000)
	radar.heading = -PI / 2.0
	radar.radius_m = 200.0
	var east := radar.world_center + Vector3(100, 0, 0)
	_check(radar.world_to_radar(east).y < 0 and absf(radar.world_to_radar(east).x) < 0.001, "east faces up when camera looks east")
	_check(radar.radar_to_world(radar.world_to_radar(east, false)).is_equal_approx(east), "world/radar transforms round trip")
	_check(is_equal_approx(radar.world_to_radar(east + Vector3(10000, 0, 0)).length(), 87.0), "distant blips clamp inside edge")
	for kind: StringName in [&"player", &"mission", &"enemy", &"police", &"waypoint", &"shop"]:
		radar.add_blip(kind, east, kind, Color.CYAN)
		_check(radar.blips[kind].kind == kind, "register %s kind" % kind)
	radar.update_blip(&"mission", east + Vector3.RIGHT)
	_check(radar.blips[&"mission"].world_position == east + Vector3.RIGHT, "update existing blip")
	radar.remove_blip(&"mission")
	radar.update_blip(&"missing", east)
	_check(not radar.blips.has(&"mission") and not radar.blips.has(&"missing"), "remove and missing update are safe")
	var node := Node3D.new()
	add_child(node)
	node.add_to_group("floating")
	node.global_position = east
	radar.add_node_blip(&"tracked", node, &"player", Color.WHITE)
	var before := radar.blips[&"tracked"].world_position
	WorldOrigin.shift(Vector3(1000, 0, -1500))
	radar.refresh_node_blips()
	_check(radar.blips[&"tracked"].world_position == before, "tracked world coordinates survive origin shift")
	_check(radar.blips[&"enemy"].world_position == east, "fixed world coordinates survive origin shift")
	node.position += Vector3(20, 0, 30)
	radar.refresh_node_blips()
	_check(radar.blips[&"tracked"].world_position == before + Vector3(20, 0, 30), "tracked node moves in world coordinates")
	node.free()
	radar.refresh_node_blips()
	_check(not radar.blips.has(&"tracked"), "freed node blip removed")
	WorldOrigin.shift(-WorldOrigin.offset)
	var lanes: Array[PackedVector3Array] = [PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 20), Vector3(30, 0, 20)])]
	radar._lanes_changed(Vector2i.ZERO, lanes, PackedFloat32Array())
	_check(radar.street_tiles[Vector2i.ZERO].size() == 4, "streamed lane cached as line pairs")
	var map := WorldMap.new()
	map.radar = radar
	add_child(map)
	map.set_anchors_preset(Control.PRESET_TOP_LEFT)
	map.size = Vector2(800, 600)
	map.open()
	var point := Vector2(500, 350)
	var world := map.map_to_world(point)
	_check(map.world_to_map(world).is_equal_approx(point), "world/map transforms round trip")
	map.zoom_at(point, 1.2)
	_check(map.map_to_world(point).is_equal_approx(world), "zoom anchors street under cursor")
	map._begin_drag(point)
	map._end_drag(point)
	_check(radar.waypoint_active and radar.waypoint_position.is_equal_approx(world), "map click creates world waypoint")
	map._begin_drag(point)
	map._pan(point + Vector2(50, 30))
	map._end_drag(point + Vector2(50, 30))
	_check(radar.waypoint_position.is_equal_approx(world), "pan does not replace waypoint")
	radar.clear_waypoint()
	_check(not radar.waypoint_active and not radar.blips.has(Radar.WAYPOINT_ID), "clear removes waypoint")
	var empty: Array[PackedVector3Array] = []
	radar._lanes_changed(Vector2i.ZERO, empty, PackedFloat32Array())
	_check(radar.street_tiles.is_empty() and map._streets._tiles.is_empty(), "unloaded streets leave both maps")
	Settings.set_value("show_radar", false)
	_check(not radar.enabled, "setting hides radar")
	Settings.set_value("show_radar", true)
	_check(radar.enabled, "setting restores radar")
	map.close()
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	hero.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(hero)
	radar.hero = hero
	var officer: PoliceOfficer = load("res://scenes/npc/police_officer.tscn").instantiate()
	officer.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(officer)
	var police_id := StringName("radar/police/%d" % officer.get_instance_id())
	radar._refresh_builtins()
	_check(not radar.blips.has(police_id), "police hidden when local hero has no stars")
	hero.wanted_stars = 2
	radar._refresh_builtins()
	_check(radar.blips.has(police_id) and radar.blips[police_id].kind == &"police", "standing officers become police blips while wanted")
	_check(radar.blips[police_id].color in [Color("57a5ff"), Color("ff5967")], "police use blue/red flashing colors")
	officer.state = Thug.State.DOWN
	radar._refresh_builtins()
	_check(not radar.blips.has(police_id), "downed officers lose their blips")
	officer.state = Thug.State.IDLE
	hero.wanted_stars = 0
	radar._refresh_builtins()
	_check(not radar.blips.has(police_id), "cleared stars remove police blips")
	var car := DriveVehicle.new()
	car.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(car)
	car.velocity = Vector3(0, 0, 30)
	var drive := hero.get_mode(&"Drive") as DriveMode
	drive.car = car
	hero.set_mode(&"Drive")
	radar.radius_m = 180.0
	radar._previous_world = Vector3.INF
	radar._process(1.0)
	_check(hero.mode.name == &"Drive" and radar.radius_m > 300.0, "driving at 30 m/s zooms radar beyond 300 m")
	hero.set_mode(&"OnFoot")
	car.free()
	WorldMap.add_action()
	var map_key := InputMap.action_get_events(&"world_map")[0] as InputEventKey
	var car_key := InputMap.action_get_events(&"interact")[0] as InputEventKey
	_check(map_key.physical_keycode == KEY_COMMA and car_key.physical_keycode == KEY_G, "comma map key stays separate from G car interaction")
	radar.hero = null
	officer.free()
	hero.free()
	print("radar test finished: %d failures" % _failed)
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failed += 1
