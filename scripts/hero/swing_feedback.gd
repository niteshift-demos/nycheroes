extends Node
## Local swing guidance projects the actual wall hit, never the invisible
## pendulum pivot. It has no effect on physics or replicated hero state.

var swing: SwingMode
var _overlay: Control
var _background: StyleBoxFlat


func _ready() -> void:
	_background = StyleBoxFlat.new()
	_background.bg_color = Color(0.02, 0.03, 0.05, 0.85)
	_background.set_corner_radius_all(6)
	var layer := CanvasLayer.new()
	add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	_overlay.draw.connect(_draw_feedback)


func _process(_delta: float) -> void:
	_overlay.queue_redraw()


func _draw_feedback() -> void:
	var hero := swing.hero
	if not hero or hero.frozen or hero.is_remote() or not hero.mode:
		return
	var attached := hero.mode.name == &"Swing"
	if not attached and hero.mode.name != &"OnFoot":
		return
	var available := not swing.preview.is_empty()
	var color := Color(1.0, 0.85, 0.35) if attached else Color(0.3, 0.95, 1.0)
	var text := "No wall in reach · %d m range · look toward taller buildings" % swing.max_web_length
	if attached or available:
		var point: Vector3 = swing.web_point if attached else swing.preview.point
		var distance := (hero.global_position + Vector3.UP * SwingMode.HAND_HEIGHT).distance_to(point)
		text = "WEB ATTACHED · %.0f m · release to let go" % distance if attached else "WEB READY · %.0f / %d m · hold Web to swing" % [distance, swing.max_web_length]
		var camera := hero.get_viewport().get_camera_3d()
		if camera and not camera.is_position_behind(point):
			var projected := camera.unproject_position(point)
			var bounds := _overlay.get_viewport_rect().grow(-32.0)
			var at := projected.clamp(bounds.position, bounds.end)
			_overlay.draw_circle(at, 10.0, Color(0, 0, 0, 0.8))
			_overlay.draw_arc(at, 10.0, 0.0, TAU, 24, color, 2.5, true)
			_overlay.draw_circle(at, 2.5, color)
			if not bounds.has_point(projected):
				var toward := (projected - at).normalized()
				_overlay.draw_line(at + toward * 12.0, at + toward * 24.0, color, 3.0, true)
				_overlay.draw_string(ThemeDB.fallback_font, at + Vector2(15, 18), "WALL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	else:
		color = Color(0.9, 0.9, 0.9)
	var font := ThemeDB.fallback_font
	var font_size := mini(18, int(18.0 * (_overlay.size.x - 32.0) / maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, 1.0)))
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var at := Vector2((_overlay.size.x - extent.x) * 0.5, _overlay.size.y - 100.0)
	_overlay.draw_style_box(_background, Rect2(at + Vector2(-12, -24), extent + Vector2(24, 14)))
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
