class_name SafeReturnPanel
extends CanvasLayer
## Mouse and touch equivalents of K / R, routed through the same HeroInput.

var source: PlayerInput
var _panel: VBoxContainer
var _status: Label


func _ready() -> void:
	layer = 0
	_panel = VBoxContainer.new()
	_panel.position = Vector2(20, 100)
	add_child(_panel)
	var buttons := HBoxContainer.new()
	_panel.add_child(buttons)
	for entry: Array in [["Save point [K]", true], ["Return [R]", false]]:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = 42
		var save: bool = entry[1]
		button.pressed.connect(func() -> void:
			if source.enabled:
				if save:
					source.hero.input.checkpoint_pressed = true
				else:
					source.hero.input.return_pressed = true)
		buttons.add_child(button)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.add_theme_constant_override("shadow_outline_size", 5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 300
	_panel.add_child(_status)


func _process(_delta: float) -> void:
	_panel.visible = source.enabled and not source.hero.frozen
	var recovery := source.hero.safe_return
	_status.text = recovery.message
	if recovery.cooldown > 0.0:
		_status.text += "\nReturn ready in %ds" % ceili(recovery.cooldown)
	elif recovery.checkpoint != Vector3.INF:
		_status.text += "\nSafe point: %dm / 250m" % roundi(source.hero.world_position().distance_to(recovery.checkpoint))
