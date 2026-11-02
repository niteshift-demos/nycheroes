class_name RescueDirector
extends Node3D
## Small, player-owned sidewalk rescues. Only their owner advances progress;
## helpers send intent and are checked against the existing synced hero state.
## Positions and messages use world meters so origin shifts need no RPC.

const CHARACTER := preload("res://assets/characters/mannequin/mannequin.glb")
const REACH := 4.0
const LIFT_SECONDS := 4.0
const SHARE_INTERVAL := 0.25
const GOLD := Color(1.0, 0.76, 0.22)
const GREEN := Color(0.3, 1.0, 0.65)
const PEOPLE := ["Alex · delivery rider", "Sam · night-shift nurse", "Jo · neighborhood cook"]
const THANKS := ["My next delivery can wait. Thank you!", "Thanks! Now I can get back to helping people.", "You saved me! Dinner is on me."]

var hero: Hero
var city: CityStreamer
var player_input: PlayerInput
## owner -> [serial, world position, civilian variant, progress seconds, saved].
var calls: Dictionary = {}
var saved_count := 0
var _serial := 0
var _cycle := 0
var _wait := 3.0
var _share := 0.0
var _helpers: Dictionary = {}  # peer -> [serial, expiry on our monotonic clock]
var _visuals: Dictionary = {}
var _panel: PanelContainer
var _title: Label
var _detail: Label
var _bar: ProgressBar
var _button: Button
var _touching := false:
	set(value):
		_touching = value
		if is_instance_valid(player_input):
			player_input.ui_interaction_held = value
var _rescue_finger := -1
var _selected := 0
var _notice := 0.0
var _last_saved_variant := 0
var _disabled := false


func _ready() -> void:
	_disabled = LaunchOptions.get_string("rescues", "1") == "0" or LaunchOptions.has("demo")
	if not InputMap.has_action("rescue"):
		InputMap.add_action("rescue")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		InputMap.action_add_event("rescue", key)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_DPAD_UP
		InputMap.action_add_event("rescue", pad)
	_build_panel()
	Net.player_left.connect(func(id: int) -> void:
		calls.erase(id)
		_helpers.erase(id))
	Net.state_changed.connect(func() -> void:
		# Session boundaries discard calls; nothing can be rescued twice by a
		# late packet from the previous room. Disconnecting owners clear calls.
		calls.clear()
		_helpers.clear()
		_wait = 3.0)


## TouchControls owns raw fingers (Godot mouse emulation is disabled). Route
## the rescue card first so its hold cannot move the stick, camera, or attack.
func touch_rescue(index: int, at: Vector2, pressed: bool) -> bool:
	if not pressed and index == _rescue_finger:
		release_touch()
		return true
	if pressed and _rescue_finger == -1 and _button.is_visible_in_tree() \
			and player_input.enabled and _button.get_global_rect().has_point(at):
		_rescue_finger = index
		_touching = true
		return true
	return false


func drag_rescue(index: int, at: Vector2) -> bool:
	if index != _rescue_finger:
		return false
	_touching = _button.is_visible_in_tree() and _button.get_global_rect().has_point(at)
	return true


func release_touch() -> void:
	_rescue_finger = -1
	_touching = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_touch()


func _process(delta: float) -> void:
	if _disabled:
		_panel.hide()
		return
	var own := Net.local_id()
	_notice = maxf(0.0, _notice - delta)
	if calls.has(own):
		var call: Array = calls[own]
		if call[4]:
			_wait -= delta
			if _wait <= 0.0:
				calls.erase(own)
		elif Combat.heroes.all(func(target: Hero) -> bool:
			return target.world_position().distance_to(call[1]) > 280.0):
			calls.erase(own)
			_wait = 3.0
	else:
		_wait -= delta
		if _wait <= 0.0 and not hero.frozen and hero.mode.name == &"OnFoot":
			_wait = 2.0
			_spawn_nearby()
	_selected = _nearest()
	var wants := _selected != 0 and player_input.enabled and not hero.frozen \
		and (Input.is_action_pressed("rescue") or _touching)
	if calls.has(own) and not calls[own][4]:
		var contributors := 1 if wants and _selected == own and can_help(hero, calls[own][1]) else 0
		for id: int in _helpers:
			var request: Array = _helpers[id]
			if request[0] != calls[own][0] or request[1] < Time.get_ticks_msec():
				continue
			for other in Combat.heroes:
				if other.remote_id == id and can_help(other, calls[own][1]):
					contributors += 1
		if contributors > 0:
			calls[own][3] = minf(LIFT_SECONDS, float(calls[own][3]) + delta * mini(contributors, 2))
			if calls[own][3] >= LIFT_SECONDS:
				calls[own][4] = true
				saved_count += 1
				_last_saved_variant = int(calls[own][2])
				_notice = 7.0
				_wait = 18.0
				print("[rescue] civilian safe; %d rescued" % saved_count)
	_share -= delta
	if _share <= 0.0:
		_share = SHARE_INTERVAL
		if Net.is_online():
			for id in Net.peers():
				_snapshot.rpc_id(id, calls.get(own, []))
			if wants and _selected != own and can_help(hero, calls[_selected][1]):
				_help.rpc_id(_selected, int(calls[_selected][0]))
	_update_visuals()
	_update_panel()


## Vertical reach matters: flying over the marker cannot free the civilian.
static func can_help(target: Hero, spot: Vector3) -> bool:
	return (target.remote_grounded if target.is_remote() else target.is_on_floor()) \
		and target.health > 0.0 and not target.frozen and target.mode.name == &"OnFoot" \
		and target.world_position().distance_to(spot) <= REACH and target.velocity.length() < 2.5


func _spawn_nearby() -> void:
	var at := hero.world_position()
	for data: Array in calls.values():
		if not data[4] and at.distance_to(data[1]) < 100.0:
			return
	var ahead := hero.forward()
	var camera := get_viewport().get_camera_3d()
	if camera:
		ahead = -camera.global_basis.z
	ahead.y = 0.0
	var desired := at + ahead.normalized() * (20.0 if _cycle == 0 else 42.0)
	var candidates: Array[Vector3] = []
	var spot := Vector3.INF
	for lane in city.lanes_near(at, 85.0):
		for n in lane.size() - 1:
			var point := Geometry3D.get_closest_point_to_segment(desired, lane[n], lane[n + 1])
			var distance := at.distance_to(point)
			if distance < 12.0 or distance > 80.0 or not city.has_collision_at(point):
				continue
			candidates.append(point)
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(desired) < b.distance_squared_to(desired))
	# Bound physics queries even in dense tiles, and try alternatives when
	# the closest sidewalk point is obstructed by a wall or street furniture.
	for index in mini(candidates.size(), 24):
		var candidate := candidates[index]
		var ground := city.ground_height_at(candidate, 2.0)
		if is_nan(ground) or absf(ground - candidate.y) > 1.5:
			continue
		candidate.y = ground + 0.04
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.8, 2.2, 2.8)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = WorldOrigin.to_local(candidate) + Vector3.UP * 1.2
		query.collision_mask = 1
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			spot = candidate
			break
	if spot == Vector3.INF:
		return
	_serial += 1
	calls[Net.local_id()] = [_serial, spot, _cycle % PEOPLE.size(), 0.0, false]
	_cycle += 1
	print("[rescue] %s needs help at %s" % [PEOPLE[int(calls[Net.local_id()][2])], spot])


func _nearest() -> int:
	var best := 350.0
	var owner := 0
	for id: int in calls:
		var call: Array = calls[id]
		if call[4]:
			continue
		var distance := hero.world_position().distance_to(call[1])
		if distance < best:
			best = distance
			owner = id
	return owner


@rpc("any_peer", "call_remote", "reliable")
func _snapshot(data: Array) -> void:
	if _disabled:
		return
	var sender := multiplayer.get_remote_sender_id()
	if data.is_empty():
		calls.erase(sender)
	elif data.size() == 5 and data[0] is int and data[1] is Vector3 and data[1].is_finite() and data[2] is int \
			and data[2] >= 0 and data[2] < PEOPLE.size() and data[3] is float and data[4] is bool:
		var old: Array = calls.get(sender, [])
		if data[4] and hero.world_position().distance_to(data[1]) < 100.0 and not old.is_empty() and old[0] == data[0] and not old[4]:
			saved_count += 1
			_last_saved_variant = int(data[2])
			_notice = 7.0
		calls[sender] = data


@rpc("any_peer", "call_remote", "unreliable")
func _help(serial: int) -> void:
	_helpers[multiplayer.get_remote_sender_id()] = [serial, Time.get_ticks_msec() + 450]


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = PanelContainer.new()
	_panel.name = "RescuePanel"
	layer.add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.07, 0.93)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", GOLD)
	box.add_child(_title)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Keep the hold button under the same finger when instructions shorten.
	_detail.custom_minimum_size.y = 44.0
	_detail.add_theme_font_size_override("font_size", 15)
	box.add_child(_detail)
	_bar = ProgressBar.new()
	_bar.max_value = LIFT_SECONDS
	_bar.custom_minimum_size.y = 10.0
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	_button = Button.new()
	_button.text = "HOLD TO RESCUE  ·  V / D-pad Up"
	_button.custom_minimum_size.y = 44.0
	_button.focus_mode = Control.FOCUS_NONE
	_button.button_down.connect(func() -> void: _touching = true)
	_button.button_up.connect(func() -> void: _touching = false)
	box.add_child(_button)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _update_panel() -> void:
	var width := minf(400.0, get_viewport().get_visible_rect().size.x - 32.0)
	_panel.position = Vector2((get_viewport().get_visible_rect().size.x - width) * 0.5, 125.0 if get_viewport().get_visible_rect().size.x >= 1000.0 else 90.0)
	_panel.size.x = width
	_panel.visible = player_input.enabled and (_selected != 0 or _notice > 0.0)
	if not _panel.visible:
		return
	_title.add_theme_color_override("font_color", GREEN if _notice > 0.0 else GOLD)
	if _notice > 0.0 or _selected == 0:
		_title.text = "CIVILIAN SAFE  ·  %d rescued" % saved_count
		_detail.text = THANKS[_last_saved_variant] + " Next call soon."
		_bar.hide()
		_button.hide()
		return
	var call: Array = calls[_selected]
	var distance := hero.world_position().distance_to(call[1])
	var near := distance <= REACH
	_title.text = "RESCUE CALL  ·  %d m" % int(distance)
	_detail.text = "%s is pinned under debris. Follow the gold beacon." % PEOPLE[call[2]]
	if near:
		_detail.text = "Stand still and hold Rescue to lift. Release to pause."
		if not can_help(hero, call[1]):
			_detail.text = "Land on foot and stand still beside the civilian."
		elif float(call[3]) > 0.0:
			var percent := int(float(call[3]) / LIFT_SECONDS * 100.0)
			_detail.text = ("Lifting debris… %d%%" if Input.is_action_pressed("rescue") or _touching \
				else "Lift paused at %d%%. Hold Rescue to continue.") % percent
	_bar.show()
	_bar.value = call[3]
	_button.visible = near
	if not near:
		_touching = false
	_panel.reset_size()
	_panel.size.x = width


func _update_visuals() -> void:
	for id: int in _visuals.keys():
		if not calls.has(id) or _visuals[id].get_meta("serial") != calls[id][0]:
			_visuals[id].queue_free()
			_visuals.erase(id)
	for id: int in calls:
		var call: Array = calls[id]
		if hero.world_position().distance_to(call[1]) > 350.0:
			if _visuals.has(id):
				_visuals[id].queue_free()
				_visuals.erase(id)
			continue
		if not _visuals.has(id):
			_visuals[id] = _make_visual(call)
		var root: Node3D = _visuals[id]
		root.position = WorldOrigin.to_local(call[1])
		root.visible = hero.world_position().distance_to(call[1]) < 350.0
		var saved: bool = call[4]
		var debris := root.get_node("Debris") as Node3D
		debris.position.y = 0.65 + 1.6 * float(call[3]) / LIFT_SECONDS
		debris.visible = not saved
		var person := root.get_node("Civilian") as Node3D
		person.rotation.z = 0.0 if saved else -PI / 2.0
		person.position.y = 0.0 if saved else 0.35
		var tag := root.get_node("Beacon") as Label3D
		tag.modulate = GREEN if saved else GOLD
		tag.text = "SAFE!\n" + THANKS[call[2]] if saved else "!\nRESCUE"


func _make_visual(call: Array) -> Node3D:
	var root := Node3D.new()
	root.set_meta("serial", call[0])
	add_child(root)
	var person := CHARACTER.instantiate() as Node3D
	person.name = "Civilian"
	root.add_child(person)
	NpcLook.paint_pedestrian(person)
	var animation := person.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation:
		animation.play("Idle")
		animation.advance(0.1)
		animation.pause()
	var debris := Node3D.new()
	debris.name = "Debris"
	root.add_child(debris)
	for n in 3:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.6, 0.24, 0.36)
		mesh.mesh = box
		mesh.position = Vector3(0.0, n * 0.18, (n - 1) * 0.5)
		mesh.rotation.y = (n - 1) * 0.4
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.65, 0.39, 0.13) if n != 1 else GOLD
		mesh.material_override = material
		debris.add_child(mesh)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 2.14
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.08
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = GOLD
	ring.material_override = glow
	root.add_child(ring)
	var tag := Label3D.new()
	tag.name = "Beacon"
	tag.position.y = 4.8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 48
	tag.pixel_size = 0.012
	root.add_child(tag)
	return root
