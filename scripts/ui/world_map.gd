class_name WorldMap
extends Control
## North-up map of loaded streets. Drag to pan, wheel or +/- to zoom, click
## to set a world-space waypoint. No extra tile downloads or game teleporting.

signal toggled(open: bool)

var radar: Radar
var world_center := Vector2.ZERO
var pixels_per_meter := 0.65
var _streets: RadarStreets
var _overlay: MapOverlay
var _buttons: Array[Button] = []
var _dragging := false
var _drag_start := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _drag_distance := 0.0
var _touch_id := -1
var _recapture := false
var _refresh := 0.0

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
	_streets = RadarStreets.new()
	add_child(_streets)
	_overlay = MapOverlay.new()
	_overlay.map = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	for key: Vector2i in radar.street_tiles:
		_streets.set_tile(key, radar.street_tiles[key])
	radar.streets_changed.connect(_streets.set_tile)
	_add_button("−", func() -> void: zoom_at(size * 0.5, 0.75))
	_add_button("+", func() -> void: zoom_at(size * 0.5, 1.333333))
	_add_button("Center", recenter)
	_add_button("Clear pin", radar.clear_waypoint)
	_add_button("Close  ,", func() -> void: close(true))
	resized.connect(_layout)
	_layout()


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	button.custom_minimum_size = Vector2(44, 44)
	add_child(button)
	_buttons.append(button)


func _layout() -> void:
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
	_recapture = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	recenter()
	toggled.emit(true)


func close(by_pointer := false) -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	_touch_id = -1
	if _recapture and (by_pointer or not Device.is_web()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(false)


func recenter() -> void:
	world_center = Vector2(radar.world_center.x, radar.world_center.z)


func world_to_map(world: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(world.x, world.z) - world_center) * pixels_per_meter


func map_to_world(point: Vector2) -> Vector3:
	var world := world_center + (point - size * 0.5) / pixels_per_meter
	return Vector3(world.x, 0.0, world.y)


## Zoom stays anchored under the cursor instead of sliding the chosen street.
func zoom_at(point: Vector2, factor: float) -> void:
	var before := map_to_world(point)
	pixels_per_meter = clampf(pixels_per_meter * factor, 0.06, 3.0)
	var after := map_to_world(point)
	world_center += Vector2(before.x - after.x, before.z - after.z)


func _process(delta: float) -> void:
	if not visible:
		return
	_streets.place(size * 0.5, world_center, 0.0, pixels_per_meter)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.05
		queue_redraw()
		_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.is_action_pressed(&"world_map") or event.keycode == KEY_ESCAPE:
				close()
			elif event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS:
				zoom_at(size * 0.5, 1.333333)
			elif event.keycode == KEY_MINUS:
				zoom_at(size * 0.5, 0.75)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed and _touch_id == -1:
			for button in _buttons:
				if button.get_global_rect().has_point(event.position):
					button.pressed.emit()
					return
			_touch_id = event.index
			_begin_drag(event.position)
		elif not event.pressed and event.index == _touch_id:
			_end_drag(event.position)
			_touch_id = -1
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if event.index == _touch_id:
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
			zoom_at(event.position, 1.2)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(event.position, 1.0 / 1.2)
	elif event is InputEventMouseMotion and _dragging:
		_pan(event.position)
		accept_event()


func _begin_drag(at: Vector2) -> void:
	if at.y < _header_height() or at.y > size.y - 42:
		return
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
		radar.set_waypoint(map_to_world(at))
	_dragging = false


func _header_height() -> float:
	return 124.0 if size.x < 650 else 84.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101c26"))
	# A quiet grid distinguishes unmapped areas from the actual street network.
	var step := 500.0 * pixels_per_meter
	var origin := size * 0.5 - world_center * pixels_per_meter
	for x in range(int(fposmod(origin.x, step)), int(size.x), maxi(1, int(step))):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("1a2a35"))
	for y in range(int(fposmod(origin.y, step)), int(size.y), maxi(1, int(step))):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("1a2a35"))


func draw_overlay(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	for blip: Radar.Blip in radar.blips.values():
		Radar.draw_blip(canvas, world_to_map(blip.world_position), blip.kind, blip.color)
	var player_at := world_to_map(radar.world_center)
	canvas.draw_circle(player_at, 9, Color("152633"))
	Radar.draw_blip(canvas, player_at, &"player", Color.WHITE)
	canvas.draw_string(font, player_at + Vector2(12, 5), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	canvas.draw_rect(Rect2(0, 0, size.x, _header_height()), Color("101c26"))
	canvas.draw_rect(Rect2(0, size.y - 42, size.x, 42), Color("101c26"))
	canvas.draw_string(font, Vector2(20, 36), "NEW YORK", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffdc86"))
	var hint := "N ↑   LOADED STREETS  ·  Drag to pan · Tap to place a waypoint" if size.x >= 650 else "N ↑   Loaded streets · Drag / tap to pin"
	canvas.draw_string(font, Vector2(20, _header_height() - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b4c5d2"))
	var text := "Tap to set waypoint" if size.x < 650 else "Click to set waypoint · Wheel / + − to zoom"
	if radar.waypoint_active:
		text = "WAYPOINT  ·  %d m from you" % int(radar.waypoint_position.distance_to(radar.world_center))
	canvas.draw_string(font, Vector2(20, size.y - 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Radar.WAYPOINT_COLOR)
	var bar_m := 100.0 if pixels_per_meter > 0.4 else 500.0
	var at := Vector2(size.x - bar_m * pixels_per_meter - 24, size.y - 18)
	canvas.draw_line(at, at + Vector2(bar_m * pixels_per_meter, 0), Color.WHITE, 2)
	canvas.draw_string(font, at + Vector2(0, -8), "%d m" % int(bar_m), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
