class_name MissionHud
extends Control
## Shared cash anchor and a quiet subtitle objective. Contract management
## lives in PauseMenu; result banners belong to GameHud so arrests take priority.

var director: MissionDirector
var wallet: Wallet
var _game_hud: GameHud
var _cash: Label
var _title: Label
var _objective: Label
var _display_cash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = HudStyle.theme()
	_game_hud = get_parent().get_node_or_null("GameHud") as GameHud
	_cash = HudStyle.label("", 28, HudStyle.GREEN)
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_cash)
	_title = HudStyle.label("", 13, HudStyle.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_objective = HudStyle.label("", 20)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_objective)
	_display_cash = wallet.balance


func _process(delta: float) -> void:
	var stamp := GtaTiming.begin()
	_missionhud_timed_process(delta)
	GtaTiming.end(&"hud", stamp)


func _missionhud_timed_process(delta: float) -> void:
	_display_cash = move_toward(_display_cash, float(wallet.balance), maxf(50.0, absf(wallet.balance - _display_cash) * 5.0) * delta)
	_cash.text = Wallet.format_cash(roundi(_display_cash))
	var touch := Device.wants_touch_controls()
	var anchor := _game_hud.wanted_anchor() if _game_hud else Vector2(size.x - 28.0, 70.0)
	_cash.position = Vector2(anchor.x - 210.0, anchor.y + 32.0)
	_cash.size = Vector2(224.0, 40.0)
	var running := director.active != null
	_title.visible = running and (_game_hud == null or _game_hud.banner_remaining <= 0.0)
	_objective.visible = _title.visible
	var portrait := touch and size.y > size.x
	var width := size.x - 32.0 if portrait else minf(700.0, size.x * (0.38 if touch else 0.64))
	var bottom := size.y - (310.0 if portrait else 132.0 if touch else 144.0)
	_title.position = Vector2((size.x - width) * 0.5, bottom - 30.0)
	_title.size = Vector2(width, 22.0)
	_title.text = director.active.title.to_upper() if running else ""
	_objective.position = Vector2((size.x - width) * 0.5, bottom - 6.0)
	_objective.size = Vector2(width, 62.0)
	_objective.add_theme_font_size_override("font_size", 15 if touch else 20)
	_objective.text = director.objective_text() if running else ""
	if running and director.remaining >= 0.0:
		_objective.text += "  ·  %02d:%02d" % [int(ceil(director.remaining)) / 60, int(ceil(director.remaining)) % 60]
	_objective.add_theme_color_override("font_color", HudStyle.RED if running and director.remaining >= 0.0 and director.remaining < 15.0 else Color.WHITE)
