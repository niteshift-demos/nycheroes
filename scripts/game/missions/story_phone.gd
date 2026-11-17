class_name StoryPhone
extends PanelContainer
## Non-modal phone conversation. Keyboard, controller and touch can advance
## or skip; objectives wait so a call never costs a chase's time budget.

var director: MissionDirector
var _portrait: Label
var _speaker: Label
var _line: Label


func _ready() -> void:
	theme = HudStyle.theme()
	var background := StyleBoxFlat.new()
	background.bg_color = HudStyle.INK
	background.border_color = HudStyle.GOLD
	background.border_width_left = 3
	add_theme_stylebox_override("panel", background)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8 if Device.wants_touch_controls() else 14)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_portrait = HudStyle.label("", 32, HudStyle.GOLD)
	_portrait.add_theme_font_size_override("font_size", 32)
	row.add_child(_portrait)
	_speaker = HudStyle.label("", 20, HudStyle.GOLD)
	_speaker.add_theme_font_size_override("font_size", 20)
	row.add_child(_speaker)
	_line = HudStyle.label("", 17)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_size_override("font_size", 17)
	column.add_child(_line)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for caption in ["Next · Enter", "Skip call"]:
		var button := Button.new()
		button.text = caption
		button.custom_minimum_size.y = 44
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(director.next_call if caption.begins_with("Next") else director.skip_calls)
		buttons.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_accept"):
		director.next_call()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var stamp := GtaTiming.begin()
	_storyphone_timed_process(_delta)
	GtaTiming.end(&"hud", stamp)


func _storyphone_timed_process(_delta: float) -> void:
	visible = not director.phone_lines.is_empty()
	if not visible:
		return
	var width := minf(440.0, get_viewport_rect().size.x - 32.0)
	var viewport := get_viewport_rect().size
	var touch := Device.wants_touch_controls()
	var portrait := viewport.y > viewport.x
	if touch and not portrait:
		width = minf(width, viewport.x * 0.38)
	_portrait.add_theme_font_size_override("font_size", 22 if touch else 32)
	_speaker.add_theme_font_size_override("font_size", 16 if touch else 20)
	_line.add_theme_font_size_override("font_size", 14 if touch else 17)
	custom_minimum_size.x = width
	size.x = width
	_line.custom_minimum_size.x = width - (16.0 if touch else 28.0)
	position = Vector2((viewport.x - width) * 0.5 if touch else viewport.x - width - 16.0,
		maxf(60.0 if touch else 18.0, viewport.y - size.y - (360.0 if portrait and touch else 170.0 if touch else 220.0)))
	if touch and not portrait:
		# Centre in the actual gap: radar ends at 152, while the full cash
		# label starts 338 px from the right (large balances use all of it).
		position.x = maxf(16.0, 168.0 + (viewport.x - 338.0 - 168.0 - size.x) * 0.5)
	var line: Dictionary = director.phone_lines[0]
	_speaker.text = "  PHONE · " + String(line.speaker)
	_speaker.modulate = line.color
	_portrait.text = String(line.speaker).left(1)
	_portrait.modulate = line.color
	_line.text = line.line
