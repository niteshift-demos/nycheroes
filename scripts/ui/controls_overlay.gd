class_name ControlsOverlay
extends Control
## Readable keyboard help over the game, independent of the debug stats.
## It only observes the current mode; it never captures movement or mouse input.

const GROUND: Array[Array] = [
	["WASD", "Move"], ["Mouse", "Look around"],
	["Space", "Jump / hold to charge"], ["Shift", "Super speed"],
	["F", "Start flying"], ["Left click", "Punch / dive in air"],
	["E / Right click", "Hold to web swing"],
]
const FLIGHT: Array[Array] = [
	["WASD", "Fly"], ["Mouse", "Look around"],
	["Space", "Climb"], ["C", "Descend / land"],
	["Shift", "Boost"], ["F", "Stop flying"], ["Left click", "Dive attack"],
]
const FREE_CAMERA: Array[Array] = [
	["WASD", "Move camera"], ["Mouse", "Look around"],
	["Space / C", "Up / down"], ["Shift", "Boost"],
	["Wheel", "Change speed"], ["F1", "Back to hero"],
]
const SWING: Array[Array] = [
	["WASD", "Steer swing"], ["Mouse", "Look around"],
	["E / Right click", "Release to let go"],
	["F", "Start flying"], ["Left click", "Dive attack"],
]
const BACKGROUND := Color(0.025, 0.04, 0.065, 0.94)
const ACCENT := Color(0.4, 0.85, 1.0)
const KEY_INK := Color(0.04, 0.06, 0.09)

@export var hero: Hero
@export var free_camera: FreeFlyCamera

var expanded := true
var _context: StringName = &""
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	expanded = bool(Settings.get_value("show_controls", true))
	resized.connect(queue_redraw)


## Called by Game after its typing/menu guards, so H in an address is text.
func toggle_expanded() -> void:
	expanded = not expanded
	Settings.set_value("show_controls", expanded)
	queue_redraw()


func _process(_delta: float) -> void:
	if not hero or not hero.mode:
		return
	var context: StringName = &"FreeCamera" if free_camera and free_camera.current else hero.mode.name
	if context != _context:
		_context = context
		queue_redraw()


func _draw() -> void:
	if not _font or size.x < 240.0 or size.y < 240.0:
		return
	if not expanded:
		var badge := Rect2(size - Vector2(244.0, 82.0), Vector2(224.0, 58.0))
		_box(badge, BACKGROUND, Color(0.45, 0.55, 0.65))
		_key(badge.position + Vector2(14.0, 11.0), "H", 36.0, 36.0, 20)
		draw_string(_font, badge.position + Vector2(64.0, 37.0), "Controls", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22)
		return
	var rows: Array[Array] = GROUND
	var title := "On foot"
	match _context:
		&"Flight":
			rows = FLIGHT
			title = "Flight"
		&"FreeCamera":
			rows = FREE_CAMERA
			title = "Free camera"
		&"Swing":
			rows = SWING
			title = "Web swing"
		&"Dive":
			rows = [["Hold W", "Cancel dive"]]
			title = "Dive attack"
		&"KnockedOut":
			rows = [["", "Getting up automatically"]]
			title = "Knocked out"
	var compact := size.y < 620.0 or size.x < 1180.0
	var font_size := 18 if compact else 24
	var key_size := 16 if compact else 22
	var row_height := 32.0 if compact else 44.0
	var width := minf(410.0 if compact else 540.0, size.x - 32.0)
	var height := (88.0 if compact else 104.0) + rows.size() * row_height
	# In narrow windows the health/status line also reaches the right side.
	var bottom_margin := 76.0 if compact else 24.0
	var panel := Rect2(Vector2(size.x - width - 20.0, size.y - height - bottom_margin), Vector2(width, height))
	_box(panel, BACKGROUND, Color(0.45, 0.55, 0.65))
	draw_rect(Rect2(panel.position + Vector2(0.0, 8.0), Vector2(3.0, height - 16.0)), ACCENT)
	draw_string(_font, panel.position + Vector2(16.0, 30.0 if compact else 36.0), "CONTROLS  ·  " + title,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18 if compact else 20, ACCENT)
	var key_width := 148.0 if compact else 190.0
	var at := panel.position + Vector2(16.0, 45.0 if compact else 55.0)
	for row in rows:
		var label_x := 0.0
		if row[0] != "":
			_key(at, row[0], key_width, row_height - 6.0, key_size)
			label_x = key_width + 12.0
		draw_string(_font, at + Vector2(label_x, row_height - 13.0), row[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)
		at.y += row_height
	draw_string(_font, Vector2(panel.position.x + 16.0, panel.end.y - 14.0),
		"H hide controls  ·  O options  ·  M co-op", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16 if compact else 18, Color(0.8, 0.86, 0.92))


func _key(at: Vector2, text: String, width: float, height: float, font_size: int) -> void:
	var key := Rect2(at, Vector2(width, height))
	_box(key, Color(0.94, 0.97, 1.0), Color(0.65, 0.72, 0.8))
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(_font, at + Vector2((width - text_size.x) * 0.5, (height - _font.get_height(font_size)) * 0.5 + _font.get_ascent(font_size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, KEY_INK)


func _box(rect: Rect2, fill: Color, border: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	draw_style_box(box, rect)
