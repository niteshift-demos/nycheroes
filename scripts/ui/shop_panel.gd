class_name ShopPanel
extends Control
## Entry-triggered services panel. Standard focusable buttons support mouse,
## keyboard/gamepad and touch; a scroll container keeps small screens usable.

signal toggled(open: bool)
var shops: CityShops
var _panel: PanelContainer
var _rows: VBoxContainer
var _title: Label
var _balance: Label
var _note: Label
var _buttons: Dictionary = {}
var _service: Button
var _return: Button
var _paused := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(_rows)
	_title = _label(24)
	_balance = _label(18)
	_note = _label(16)
	for id: String in HeroUpgrades.NAMES:
		var button := _button("")
		button.pressed.connect(func() -> void:
			_note.text = "Purchased %s." % HeroUpgrades.NAMES[id] if shops.purchase(id) else "Not enough cash or all tiers owned."
			_refresh())
		_buttons[id] = button
	_service = _button("")
	_service.pressed.connect(func() -> void:
		if shops.active.get("kind") == &"garage":
			_note.text = shops.respray()
		else:
			shops.sleep()
			_note.text = "Rested eight hours. Health restored."
		_refresh())
	_return = _button("Return to city")
	_return.pressed.connect(close)
	shops.entered.connect(open)
	shops.changed.connect(_refresh)
	shops.wallet.changed.connect(func(_cash: int) -> void: _refresh())
	Net.state_changed.connect(func() -> void:
		if _paused and Net.state != Net.State.OFFLINE:
			get_tree().paused = false
			_paused = false)
	resized.connect(_fit)
	visible = false


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(label)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 16)
	_rows.add_child(button)
	return button


func open(location: Dictionary) -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = location.label
	_note.text = "Each tier adds 25% of base. Prices: $2,000 / $8,000 / $25,000."
	if location.kind == &"garage":
		_note.text = "Drive in while wanted. Break police line of sight, then pay $500 per star for a respray."
	elif location.kind == &"safehouse":
		_note.text = "Health restored. This apartment is now your saved recovery point after BUSTED or knockout."
	_refresh()
	_fit()
	_paused = Net.state == Net.State.OFFLINE and not get_tree().paused
	if _paused:
		get_tree().paused = true
	toggled.emit(true)
	_return.grab_focus()
	if location.kind != &"shop":
		_service.grab_focus()
	else:
		for button: Button in _buttons.values():
			if not button.disabled:
				button.grab_focus()
				break


func close() -> void:
	if not visible:
		return
	visible = false
	shops.close()
	if _paused:
		get_tree().paused = false
	_paused = false
	get_viewport().gui_release_focus()
	toggled.emit(false)


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("options_menu")):
		close()
		get_viewport().set_input_as_handled()


func _fit() -> void:
	_panel.size = Vector2(minf(620.0, size.x - 32.0), minf(650.0, size.y - 32.0))
	_panel.position = (size - _panel.size) * 0.5


func _refresh() -> void:
	if not _balance or shops.active.is_empty():
		return
	_balance.text = "Available cash   " + Wallet.format_cash(shops.wallet.balance)
	var kind: StringName = shops.active.kind
	for id: String in _buttons:
		var button: Button = _buttons[id]
		button.visible = kind == &"shop"
		var tier := HeroUpgrades.tier(id)
		var price := HeroUpgrades.price(id)
		button.text = "%s   ·   %d/3   ·   %s" % [HeroUpgrades.NAMES[id], tier, Wallet.format_cash(price) if price >= 0 else "MAXED"]
		button.disabled = price < 0 or shops.wallet.balance < price
	_service.visible = kind != &"shop"
	_service.text = "Pay & respray  ·  %s" % Wallet.format_cash(500 * shops.wanted.stars) if kind == &"garage" and shops.wanted else "Sleep 8 hours"
