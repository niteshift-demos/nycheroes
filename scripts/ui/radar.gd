class_name Radar
extends Control
## Camera-relative street radar. Public blip positions are absolute world
## coordinates; tracked nodes are converted with WorldOrigin on every update.
## Find the instance through the "radar" group or Game.radar.

signal map_requested
signal streets_changed(key: Vector2i, segments: PackedVector2Array)
signal waypoint_changed(world_position: Vector3, active: bool)

const WAYPOINT_COLOR := Color("cf91ff")
const WAYPOINT_ID := &"radar/waypoint"
## Edge radius leaves room for icons and the north letter inside the frame.
const EDGE_INSET := 15.0

class Blip extends RefCounted:
	var world_position := Vector3.ZERO
	var kind := &"waypoint"
	var color := Color.WHITE
	var node: WeakRef

class Overlay extends Control:
	var radar: Radar

	func _draw() -> void:
		radar.draw_overlay(self)

var hero: Hero
var city: CityStreamer
var players: PlayerSync
var encounters: EncounterDirector
var touch_controls: TouchControls
## Cached world-space line pairs, shared with WorldMap; unloaded tiles leave.
var street_tiles: Dictionary[Vector2i, PackedVector2Array] = {}
var blips: Dictionary[StringName, Blip] = {}
var world_center := Vector3.ZERO
var heading := 0.0
var radius_m := 180.0
var waypoint_active := false
var waypoint_position := Vector3.ZERO
var enabled := true
## CPU update time (excluding rendering), exposed for web profiling with ?radar_profile.
var _profile_usec := 0
var _profile_frames := 0
var _profile_max := 0
var _atlas: CityMapAtlas
var _streets: RadarStreets
var _overlay: Overlay
## Position-derived speed also covers a hero carried by a vehicle.
var _previous_world := Vector3.INF
var _cooldown := 0.0
var _builtins: Array[StringName] = []


func _ready() -> void:
	add_to_group("radar")
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	enabled = LaunchOptions.get_string("radar", "1") != "0" if LaunchOptions.has("radar") else bool(Settings.get_value("show_radar", true))
	Settings.changed.connect(func(key: String) -> void:
		if key == "show_radar":
			enabled = bool(Settings.get_value(key, true)))
	_atlas = CityMapAtlas.new()
	add_child(_atlas)
	_streets = RadarStreets.new()
	add_child(_streets)
	_overlay = Overlay.new()
	_overlay.radar = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	if city:
		city.traffic_lanes_changed.connect(_lanes_changed)
		var loaded := city.traffic_lanes()
		for key: Vector2i in loaded:
			var data: Array = loaded[key]
			_lanes_changed(key, data[0], data[1])


## Adds or replaces a fixed blip. Kinds: player, mission, enemy, police,
## waypoint, shop. Unknown kinds use a dot. Caller IDs must avoid "radar/".
func add_blip(id: StringName, world_position: Vector3, kind: StringName, color: Color) -> void:
	var blip := Blip.new()
	blip.world_position = world_position
	blip.kind = kind
	blip.color = color
	blips[id] = blip


## Moves an existing blip; a tracked blip becomes fixed. Missing IDs are ignored.
func update_blip(id: StringName, world_position: Vector3) -> void:
	if blips.has(id):
		blips[id].world_position = world_position
		blips[id].node = null


func remove_blip(id: StringName) -> void:
	blips.erase(id)


## Tracks a scene node without owning it. Freed nodes remove their blips.
func add_node_blip(id: StringName, node: Node3D, kind: StringName, color: Color) -> void:
	if not is_instance_valid(node):
		remove_blip(id)
		return
	add_blip(id, WorldOrigin.to_world(node.global_position), kind, color)
	blips[id].node = weakref(node)


func set_waypoint(world_position: Vector3) -> void:
	waypoint_active = true
	waypoint_position = world_position
	add_blip(WAYPOINT_ID, world_position, &"waypoint", WAYPOINT_COLOR)
	waypoint_changed.emit(world_position, true)


## Map pins use loaded collision height; sea level is a stable fallback beyond
## loaded tiles. CityStreamer returns scene Y, so restore the floating offset.
func place_map_waypoint(world_position: Vector3) -> void:
	if city:
		var height := city.ground_height_at(world_position)
		if is_finite(height):
			world_position.y = height + WorldOrigin.offset.y
	set_waypoint(world_position)


func clear_waypoint() -> void:
	waypoint_active = false
	remove_blip(WAYPOINT_ID)
	waypoint_changed.emit(waypoint_position, false)


## Radar-local pixel offset, optionally clamped to the round icon boundary.
func world_to_radar(world_position: Vector3, clamp_edge := true) -> Vector2:
	var delta := world_position - world_center
	var result := Vector2(delta.x, delta.z).rotated(heading) * pixels_per_meter()
	return result.limit_length(size.x * 0.5 - EDGE_INSET) if clamp_edge else result


## Inverse of the unclamped transform, at the given absolute world altitude.
func radar_to_world(point: Vector2, altitude := 0.0) -> Vector3:
	var delta := (point / pixels_per_meter()).rotated(-heading)
	return Vector3(world_center.x + delta.x, altitude, world_center.z + delta.y)


func pixels_per_meter() -> float:
	return (size.x * 0.5 - EDGE_INSET) / radius_m


func refresh_node_blips() -> void:
	for id: StringName in blips.keys():
		var blip := blips[id]
		if blip.node:
			var node := blip.node.get_ref() as Node3D
			if not is_instance_valid(node):
				remove_blip(id)
			else:
				blip.world_position = WorldOrigin.to_world(node.global_position)


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	visible = enabled
	var diameter := 136.0 if touch_controls else 204.0
	size = Vector2.ONE * diameter
	var viewport_size := get_viewport_rect().size
	position = Vector2(24.0, viewport_size.y - diameter - 80.0)
	if touch_controls:
		position = Vector2(touch_controls.safe_insets.x + 16.0, touch_controls.safe_insets.y + 94.0)
	if hero:
		world_center = hero.world_position()
		var speed := hero.velocity.length()
		if _previous_world != Vector3.INF:
			speed = maxf(speed, world_center.distance_to(_previous_world) / maxf(delta, 0.001))
		_previous_world = world_center
		var look_ahead := 5.0 if hero.mode and hero.mode.name == &"Drive" else 3.0
		radius_m = lerpf(radius_m, clampf(180.0 + speed * look_ahead, 180.0, 850.0), 1.0 - exp(-3.0 * delta))
	var camera := get_viewport().get_camera_3d()
	if camera:
		var forward := -camera.global_basis.z
		heading = atan2(-forward.x, -forward.z)
	if visible:
		_atlas.place(size * 0.5, Vector2(world_center.x, world_center.z), heading, pixels_per_meter(), size)
		_streets.place(size * 0.5, Vector2(world_center.x, world_center.z), heading, pixels_per_meter())
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = 0.05
		_refresh_builtins()
		refresh_node_blips()
		if visible:
			queue_redraw()
			_overlay.queue_redraw()
	if LaunchOptions.has("radar_profile"):
		var elapsed := Time.get_ticks_usec() - started
		_profile_usec += elapsed
		_profile_max = maxi(_profile_max, elapsed)
		_profile_frames += 1
		if _profile_frames == 300:
			print("Radar CPU update: mean %.3f ms, max %.3f ms / 300 frames; %d cached tiles" % [float(_profile_usec) / 300000.0, float(_profile_max) / 1000.0, street_tiles.size()])
			_profile_frames = 0
			_profile_usec = 0
			_profile_max = 0


func _refresh_builtins() -> void:
	for id in _builtins:
		remove_blip(id)
	_builtins.clear()
	if players:
		for peer: int in players.remote_heroes:
			var id := StringName("radar/player/%d" % peer)
			add_node_blip(id, players.remote_heroes[peer], &"player", Net.player_color(peer).lightened(0.35))
			_builtins.append(id)
	if hero and hero.wanted_stars > 0:
		var color := Color("57a5ff") if (Time.get_ticks_msec() / 400) % 2 == 0 else Color("ff5967")
		for thug: Thug in Combat.thugs:
			if not is_instance_valid(thug) or not thug is PoliceOfficer or thug.is_down():
				continue
			var id := StringName("radar/police/%d" % thug.get_instance_id())
			add_node_blip(id, thug, &"police", color)
			_builtins.append(id)
	if encounters and hero:
		var thug := encounters.nearest_thug(hero.world_position())
		if thug:
			add_node_blip(&"radar/target", thug, &"enemy", GameHud.MARKER_COLOR)
			_builtins.append(&"radar/target")


func _lanes_changed(key: Vector2i, lanes: Array[PackedVector3Array], _info: PackedFloat32Array) -> void:
	var segments := PackedVector2Array()
	for lane in lanes:
		for i in range(1, lane.size()):
			segments.append(Vector2(lane[i - 1].x, lane[i - 1].z))
			segments.append(Vector2(lane[i].x, lane[i].z))
	if segments.is_empty():
		street_tiles.erase(key)
	else:
		street_tiles[key] = segments
	_streets.set_tile(key, segments)
	streets_changed.emit(key, segments)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		map_requested.emit()


func _input(event: InputEvent) -> void:
	# TouchControls consumes touches in _input, before the GUI sees them.
	if visible and event is InputEventScreenTouch and event.pressed and get_global_rect().has_point(event.position):
		get_viewport().set_input_as_handled()
		map_requested.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("183544"))


func draw_overlay(canvas: Control) -> void:
	var center := size * 0.5
	for blip: Blip in blips.values():
		draw_blip(canvas, center + world_to_radar(blip.world_position), blip.kind, blip.color)
	var arrow := PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	var yaw := hero.facing if hero else 0.0
	for i in arrow.size():
		arrow[i] = center + arrow[i].rotated(heading - yaw)
	canvas.draw_colored_polygon(arrow, Color.WHITE)
	var north := center + Vector2(0, -1).rotated(heading) * (size.x * 0.5 - 12.0)
	canvas.draw_circle(north, 9, Color("17252e"))
	canvas.draw_string(ThemeDB.fallback_font, north + Vector2(-4, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffdc86"))
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = Color("c1ccd5")
	border.set_border_width_all(3)
	border.set_corner_radius_all(8)
	canvas.draw_style_box(border, Rect2(Vector2.ZERO, size))
	canvas.draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 9), "%d m  ·  MAP ," % int(radius_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## Shared, small silhouettes keep every kind readable without bitmap assets.
static func draw_blip(canvas: CanvasItem, at: Vector2, kind: StringName, color: Color) -> void:
	canvas.draw_circle(at, 6.5, Color("101820"))
	match kind:
		&"story":
			canvas.draw_string(ThemeDB.fallback_font, at + Vector2(-5, 6), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
		&"mission", &"waypoint":
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(5, 0), at + Vector2(0, 6), at + Vector2(-5, 0)]), color)
		&"police":
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -5), at + Vector2(5, -5), at + Vector2(4, 3), at + Vector2(0, 6), at + Vector2(-4, 3)]), color)
		&"shop":
			canvas.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), color)
		&"enemy":
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 4), at + Vector2(-5, 4)]), color)
		_:
			canvas.draw_circle(at, 4.0, color)
