class_name WorldMap
extends Control
## North-up atlas of all five boroughs. Drag to pan, wheel or +/- to zoom, click
## to set a world-space waypoint. No extra tile downloads or game teleporting.

signal toggled(open: bool)

var radar: Radar
var world_center := Vector2.ZERO
var pixels_per_meter := 0.65
var _atlas: CityMapAtlas
var _streets: RadarStreets
var _overlay: MapOverlay
var _buttons: Array[Button] = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _drag_distance := 0.0
var _touch_id := -1
var _touches: Dictionary[int, Vector2] = {}
var _pinched := false
var _opened_once := false
var _zoom_tween: Tween
var _zoom_target := 0.65
var _recapture := false
var _refresh := 0.0
var _paused_game := false

class MapOverlay extends Control:
	var map: WorldMap

	func _draw() -> void:
		map.draw_overlay(self)


static func add_action() -> void:
	if InputMap.has_action(&"world_map"):
		return
	InputMap.add_action(&"world_map")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_COMMA
	InputMap.action_add_event(&"world_map", key)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_atlas = CityMapAtlas.new()
	add_child(_atlas)
	_streets = RadarStreets.new()
	add_child(_streets)
	_overlay = MapOverlay.new()
	_overlay.map = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	for key: Vector2i in radar.street_tiles:
		_streets.set_tile(key, radar.street_tiles[key])
	radar.streets_changed.connect(_streets.set_tile)
	_add_button("−", func() -> void: zoom_smooth(size * 0.5, 0.75))
	_add_button("+", func() -> void: zoom_smooth(size * 0.5, 1.333333))
	_add_button("City", fit_city)
	_add_button("You", recenter)
	_add_button("Clear pin", radar.clear_waypoint)
	_add_button("Close  ,", func() -> void: close(true))
	resized.connect(_layout)
	_layout()
	Net.state_changed.connect(func() -> void:
		if _paused_game and Net.state != Net.State.OFFLINE:
			_release_pause())


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.custom_minimum_size = Vector2(44, 44)
	add_child(button)
	_buttons.append(button)


func _layout() -> void:
	if not _buttons.is_empty():
		_buttons.back().text = "Close" if Device.wants_touch_controls() else "Close  ,"
	var x := size.x - 16.0
	for i in range(_buttons.size() - 1, -1, -1):
		var button := _buttons[i]
		button.size = button.get_combined_minimum_size()
		x -= button.size.x
		button.position = Vector2(x, 48 if size.x < 650 else 16)
		x -= 8.0


func open() -> void:
	if visible:
		return
	visible = true
	_layout()
	_recapture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_paused_game = Net.state == Net.State.OFFLINE and not get_tree().paused
	if _paused_game:
		get_tree().paused = true
	if not _opened_once:
		fit_city()
		_opened_once = true
	toggled.emit(true)


func close(by_pointer := false) -> void:
	if not visible:
		return
	visible = false
	_release_pause()
	_dragging = false
	_touch_id = -1
	_touches.clear()
	_pinched = false
	if _recapture and (by_pointer or not Device.is_web()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(false)


## Navigation from Pause must not spend a solo mission's clock. Only release
## the pause this map owns; online rooms keep their shared simulation running.
func _release_pause() -> void:
	if _paused_game:
		_paused_game = false
		get_tree().paused = false


func _exit_tree() -> void:
	_release_pause()


func recenter() -> void:
	_stop_zoom()
	pixels_per_meter = 0.35
	world_center = Vector2(radar.world_center.x, radar.world_center.z)


func world_to_map(world: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(world.x, world.z) - world_center) * pixels_per_meter


func map_to_world(point: Vector2) -> Vector3:
	var world := world_center + (point - size * 0.5) / pixels_per_meter
	return Vector3(world.x, 0.0, world.y)


## Zoom stays anchored under the cursor instead of sliding the chosen street.
func zoom_at(point: Vector2, factor: float) -> void:
	var before := map_to_world(point)
	pixels_per_meter = clampf(pixels_per_meter * factor, 0.006, 3.0)
	var after := map_to_world(point)
	world_center += Vector2(before.x - after.x, before.z - after.z)


func _process(delta: float) -> void:
	if not visible:
		return
	_atlas.place(size * 0.5, world_center, 0.0, pixels_per_meter, size)
	_streets.visible = pixels_per_meter > 0.25
	_streets.place(size * 0.5, world_center, 0.0, pixels_per_meter)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.05
		queue_redraw()
		_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadButton and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			if event.is_action_pressed(&"world_map") or event.keycode == KEY_ESCAPE:
				close()
			elif event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS:
				zoom_smooth(size * 0.5, 1.333333)
			elif event.keycode == KEY_MINUS:
				zoom_smooth(size * 0.5, 0.75)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed:
			for button in _buttons:
				if button.get_global_rect().has_point(event.position):
					button.pressed.emit()
					return
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_touch_id = event.index
				_pinched = false
				_begin_drag(event.position)
			else:
				_pinched = true
				_dragging = false
		elif _touches.has(event.index):
			if not _pinched and event.index == _touch_id:
				_end_drag(event.position)
			_touches.erase(event.index)
			if _touches.is_empty():
				_touch_id = -1
				_pinched = false
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if not _touches.has(event.index):
			return
		if _touches.size() == 2:
			var points: Array[Vector2] = _touches.values()
			var old_center := (points[0] + points[1]) * 0.5
			var old_distance := points[0].distance_to(points[1])
			_touches[event.index] = event.position
			points = _touches.values()
			var new_center := (points[0] + points[1]) * 0.5
			if old_distance > 1.0:
				zoom_at(old_center, points[0].distance_to(points[1]) / old_distance)
			world_center -= (new_center - old_center) / pixels_per_meter
		else:
			_touches[event.index] = event.position
			if event.index == _touch_id and not _pinched:
				_pan(event.position)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_end_drag(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_smooth(event.position, 1.2)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_smooth(event.position, 1.0 / 1.2)
	elif event is InputEventMouseMotion and _dragging:
		_pan(event.position)
		accept_event()


func _begin_drag(at: Vector2) -> void:
	if at.y < _header_height() or at.y > size.y - (78 if size.x >= 650 else 42):
		return
	_stop_zoom()
	_dragging = true
	_drag_start = at
	_last_pointer = at
	_drag_distance = 0.0


func _pan(at: Vector2) -> void:
	if not _dragging:
		return
	_drag_distance = maxf(_drag_distance, at.distance_to(_drag_start))
	if _drag_distance > 6.0:
		world_center -= (at - _last_pointer) / pixels_per_meter
	_last_pointer = at


func _end_drag(at: Vector2) -> void:
	if _dragging and maxf(_drag_distance, at.distance_to(_drag_start)) <= 6.0:
		radar.place_map_waypoint(map_to_world(at))
	_dragging = false


func _header_height() -> float:
	return 124.0 if size.x < 650 else 84.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("183544"))


func draw_overlay(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	CityMapLabels.draw(canvas, self)
	for blip: Radar.Blip in radar.blips.values():
		Radar.draw_blip(canvas, world_to_map(blip.world_position), blip.kind, blip.color)
	var player_at := world_to_map(radar.world_center)
	canvas.draw_circle(player_at, 9, Color("152633"))
	var arrow := PackedVector2Array([Vector2(0, -10), Vector2(6, 7), Vector2(0, 3), Vector2(-6, 7)])
	for i in arrow.size():
		arrow[i] = player_at + arrow[i].rotated(-radar.hero.facing if radar.hero else 0.0)
	canvas.draw_colored_polygon(arrow, Color.WHITE)
	canvas.draw_string(font, player_at + Vector2(12, 5), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	canvas.draw_rect(Rect2(0, 0, size.x, _header_height()), Color("101c26"))
	canvas.draw_rect(Rect2(0, size.y - 42, size.x, 42), Color("101c26"))
	canvas.draw_string(font, Vector2(20, 36), "NEW YORK", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffdc86"))
	var touch := Device.wants_touch_controls()
	var hint := "N UP · FIVE BOROUGHS · Drag / pinch / tap" if touch or size.x < 650 else "NORTH UP   ·   FIVE BOROUGHS   ·   Drag to explore · Click to pin"
	canvas.draw_string(font, Vector2(20, _header_height() - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b4c5d2"))
	var text := "Tap the map to set a waypoint · + − to zoom" if touch else "Tap to set waypoint" if size.x < 650 else "Click to set waypoint · Wheel / + − to zoom"
	if radar.waypoint_active:
		text = "WAYPOINT  ·  %d m from you" % int(radar.waypoint_position.distance_to(radar.world_center))
	canvas.draw_string(font, Vector2(20, size.y - 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Radar.WAYPOINT_COLOR)
	# Keep the same legend on portrait phones; wrap instead of omitting it.
	var labels := ["Story", "Contract", "Hostile", "Police", "Player", "Waypoint", "Park", "Highway"]
	var colors := [Radar.STORY_COLOR, Radar.CONTRACT_COLOR, GameHud.MARKER_COLOR, Color("57a5ff"), Color.WHITE, Radar.WAYPOINT_COLOR, Color("426b58"), Color("e8ba79")]
	var kinds: Array[StringName] = [&"story", &"mission", &"enemy", &"police", &"player", &"waypoint", &"shop", &"shop"]
	var positions: Array[Vector2] = []
	var legend_at := Vector2(24.0, 0.0)
	for label in labels:
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 38.0
		if legend_at.x + width > size.x - 16.0:
			legend_at = Vector2(24.0, legend_at.y + 24.0)
		positions.append(legend_at)
		legend_at.x += width
	var legend_top := size.y - 72.0 - legend_at.y
	canvas.draw_rect(Rect2(0, legend_top - 16.0, size.x, legend_at.y + 32.0), Color(0.06, 0.11, 0.15, 0.93))
	for i in labels.size():
		var at := positions[i] + Vector2(0, legend_top)
		Radar.draw_blip(canvas, at, kinds[i], colors[i])
		canvas.draw_string(font, at + Vector2(13, 5), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colors[i])
	var credit := "NYC Open Data · © OpenStreetMap contributors"
	var credit_at := Vector2(20, legend_top - 22.0)
	canvas.draw_string_outline(font, credit_at, credit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color("192c36"))
	canvas.draw_string(font, credit_at, credit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("a8bdc7"))
	var bar_m := 100.0 if pixels_per_meter > 0.4 else 500.0 if pixels_per_meter > 0.08 else 5000.0
	var at := Vector2(size.x - bar_m * pixels_per_meter - 24, size.y - 18)
	canvas.draw_line(at, at + Vector2(bar_m * pixels_per_meter, 0), Color.WHITE, 2)
	canvas.draw_string(font, at + Vector2(0, -8), "%d m" % int(bar_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


## Fit the actual five-borough extent with space for the header and legend.
func fit_city() -> void:
	_stop_zoom()
	world_center = CityMapAtlas.ORIGIN + Vector2.ONE * CityMapAtlas.EXTENT * 0.5
	pixels_per_meter = minf((size.x - 80.0) / CityMapAtlas.EXTENT, (size.y - _header_height() - 120.0) / CityMapAtlas.EXTENT)


func _stop_zoom() -> void:
	if _zoom_tween and _zoom_tween.is_running():
		_zoom_tween.kill()


## Short anchored wheel interpolation; repeated wheel ticks accumulate a target.
func zoom_smooth(point: Vector2, factor: float) -> void:
	if not _zoom_tween or not _zoom_tween.is_running():
		_zoom_target = pixels_per_meter
	_stop_zoom()
	_zoom_target = clampf(_zoom_target * factor, 0.006, 3.0)
	_zoom_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_method(func(ppm: float) -> void: zoom_at(point, ppm / pixels_per_meter), pixels_per_meter, _zoom_target, 0.16)
