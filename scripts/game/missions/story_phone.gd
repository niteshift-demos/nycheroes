class_name StoryPhone
extends PanelContainer
## Non-modal phone conversation. Keyboard, controller and touch can advance
## or skip; objectives wait so a call never costs a chase's time budget.

var director: MissionDirector
var _portrait: Label
var _speaker: Label
var _line: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_portrait = Label.new()
	_portrait.add_theme_font_size_override("font_size", 32)
	row.add_child(_portrait)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 20)
	row.add_child(_speaker)
	_line = Label.new()
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
	if visible and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		director.next_call()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	visible = not director.phone_lines.is_empty()
	if not visible:
		return
	var width := minf(440.0, get_viewport_rect().size.x - 32.0)
	custom_minimum_size.x = width
	size.x = width
	_line.custom_minimum_size.x = width - 28.0
	position = Vector2(get_viewport_rect().size.x - width - 16, get_viewport_rect().size.y - size.y - (150 if Device.wants_touch_controls() else 105))
	var line: Dictionary = director.phone_lines[0]
	_speaker.text = "  PHONE · " + String(line.speaker)
	_speaker.modulate = line.color
	_portrait.text = String(line.speaker).left(1)
	_portrait.modulate = line.color
	_line.text = line.line
