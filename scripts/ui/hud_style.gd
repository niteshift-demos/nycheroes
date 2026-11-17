class_name HudStyle
extends RefCounted
## Shared quiet panels, warm objective gold and readable type for gameplay UI.

const INK := Color(0.025, 0.035, 0.045, 0.94)
const GOLD := Color(1.0, 0.8, 0.35)
const MUTED := Color(0.64, 0.7, 0.73)
const GREEN := Color(0.45, 0.9, 0.63)
const RED := Color(1.0, 0.3, 0.28)


static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = ThemeDB.fallback_font
	result.default_font_size = 17
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.14, 0.18, 0.2) if state != "normal" else Color(0.07, 0.095, 0.11)
		box.content_margin_left = 16.0
		box.content_margin_right = 16.0
		box.content_margin_top = 10.0
		box.content_margin_bottom = 10.0
		if state == "focus":
			box.bg_color = Color.TRANSPARENT
			box.border_color = GOLD
			box.set_border_width_all(2)
		result.set_stylebox(state, "Button", box)
	result.set_color("font_color", "Label", Color.WHITE)
	result.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	result.set_constant("shadow_offset_x", "Label", 1)
	result.set_constant("shadow_offset_y", "Label", 2)
	return result


static func label(text: String, font_size := 17, color := Color.WHITE) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
