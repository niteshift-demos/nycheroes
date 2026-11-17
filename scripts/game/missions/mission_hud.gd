class_name MissionHud
extends Control
## Cash and local objectives, separate from the shared health/co-op HUD.
## Starts happen by walking into markers; all job actions also have touch buttons.

var director: MissionDirector
var wallet: Wallet
var _game_hud: GameHud
var _cash: Label
var _title: Label
var _objective: Label
var _intro: Label
var _result: Label
var _timer: Label
var _retry: Button
var _side_job: Button
var _abandon: Button
var _card: ColorRect
var _display_cash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_hud = get_parent().get_node_or_null("GameHud") as GameHud
	_card = ColorRect.new()
	_card.color = Color(0.015, 0.02, 0.035, 0.78)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	_cash = _label(30, Color(0.35, 0.95, 0.48))
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title = _label(21, Color(0.8, 0.66, 1.0))
	_objective = _label(18, Color.WHITE)
	_intro = _label(15, Color(0.8, 0.83, 0.88))
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result = _label(42, Color.GOLD)
	_timer = _label(19, Color.GOLD)
	_retry = _button("Retry job", func() -> void: director.retry())
	_side_job = _button("Side job · $1,200", func() -> void: director.side_job())
	_abandon = _button("Abandon", func() -> void: director.finish(false))
	_display_cash = wallet.balance


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(action)
	button.add_theme_font_size_override("font_size", 14)
	add_child(button)
	return button


func _process(delta: float) -> void:
	_display_cash = move_toward(_display_cash, float(wallet.balance), maxf(50.0, absf(wallet.balance - _display_cash) * 5.0) * delta)
	_cash.text = Wallet.format_cash(roundi(_display_cash))
	var touch := Device.wants_touch_controls()
	var card_width := minf(620.0, size.x - (32.0 if touch else 400.0))
	card_width = maxf(250.0, card_width)
	var left := (size.x - card_width) * 0.5
	var anchor := _game_hud.wanted_anchor() if _game_hud else Vector2(size.x - 28.0, 70.0)
	var top := anchor.y + 94.0 if touch else 120.0
	_cash.position = Vector2(anchor.x - 202.0, anchor.y + 38.0)
	_cash.size = Vector2(205.0, 42.0)
	var running := director.active != null
	_card.position = Vector2(left - 12.0, top)
	_card.size = Vector2(card_width + 24.0, 165.0 if running and director.intro_remaining > 0.0 else 106.0)
	_title.position = Vector2(left, top + 6.0)
	_title.size = Vector2(card_width, 28.0)
	_title.text = director.active.title.to_upper() if running else "CITY CONTRACTS"
	_objective.position = Vector2(left, top + 38.0)
	_objective.size = Vector2(card_width, 27.0)
	_objective.add_theme_font_size_override("font_size", 14 if card_width < 450.0 else 18)
	_objective.text = director.objective_text()
	_objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_intro.visible = running and director.intro_remaining > 0.0
	_intro.position = Vector2(left + 8.0, top + 70.0)
	_intro.size = Vector2(card_width - 16.0, 54.0)
	_intro.text = director.active.intro if running else ""
	var buttons_y := top + _card.size.y + 6.0
	_side_job.visible = not running
	_retry.visible = not running and director.last_mission != null
	_abandon.visible = running
	_side_job.position = Vector2(size.x * 0.5 + (-22.0 if _retry.visible else -78.0), buttons_y)
	_side_job.size = Vector2(156.0, 44.0)
	_retry.position = Vector2(size.x * 0.5 - 136.0, buttons_y)
	_retry.size = Vector2(108.0, 44.0)
	if size.x < 600.0:
		_side_job.position.x = size.x * 0.5 - 78.0
		_retry.position = Vector2(size.x * 0.5 - 54.0, buttons_y + 48.0)
	_abandon.position = Vector2(size.x * 0.5 - 50.0, buttons_y)
	_abandon.size = Vector2(100.0, 44.0)
	_timer.visible = running and director.remaining >= 0.0
	_timer.position = Vector2(left, top + (132.0 if _intro.visible else 72.0))
	_timer.size = Vector2(card_width, 28.0)
	_timer.text = "%02d:%02d" % [int(ceil(director.remaining)) / 60, int(ceil(director.remaining)) % 60]
	_timer.modulate = Color(1.0, 0.3, 0.3) if director.remaining < 15.0 else Color.WHITE
	_result.visible = director.banner_remaining > 0.0
	_result.text = director.banner
	_result.add_theme_font_size_override("font_size", 22 if size.x < 500.0 else (26 if size.x < 800.0 else 42))
	_result.position = Vector2(0.0, size.y * 0.4)
	_result.size = Vector2(size.x, 60.0)
