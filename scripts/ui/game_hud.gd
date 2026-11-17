class_name GameHud
extends Control
## Minimal gameplay HUD: radar health, police heat, short toasts and shared
## result banners. Menus and mission subtitles use the same HudStyle palette.

## The Options button was clicked.
signal options_requested

## Thugs closer than this and on screen don't need a marker.
const NEAR_ENOUGH := 35.0
## Other players have name tags; on screen and closer than this, that's enough.
const PLAYER_NEAR_ENOUGH := 120.0
## In a big public game, only the nearest few players get a marker.
const MAX_PLAYER_MARKERS := 8
const EDGE_MARGIN := 48.0
## On touch screens, markers keep this far from the right edge, off the buttons.
const TOUCH_BUTTONS_WIDTH := 100.0
const MARKER_COLOR := Color(1.0, 0.35, 0.25)
## Co-op notices show for this long (seconds).
const NOTICE_TIME := 6.0
## "Player joined" waits this long for their name (seconds).
const NAME_WAIT := 1.0
const NOTICE_COLOR := Color(1.0, 0.9, 0.45)
## The license (CC BY 4.0) asks for this whenever the photos are shown.
const AERIAL_CREDIT := "Aerial imagery: NYC OTI / NYS Orthoimagery Program 2024 (CC BY 4.0)"

@export var hero: Hero
@export var encounters: EncounterDirector
@export var players: PlayerSync
@export var city: CityStreamer

## Set on touch screens (by Game): the health bar moves to the top left, out
## of the thumbs' way, and the HUD keeps clear of the screen's notches and of
## the touch buttons in the top right.
var touch_controls: TouchControls:
	set(value):
		touch_controls = value
		if _options_button:
			_options_button.visible = value == null

## Set by Game; mission logic and text live in their own nodes.
var missions: MissionDirector
var shops: CityShops
## Navigation pin uses the same projection and edge treatment as combat markers.
var radar: Radar

## Result display is shared by missions, arrests and knockouts.
var banner_remaining := 0.0
var banner_title := ""
var banner_detail := ""
var _banner_color := HudStyle.GOLD
var _stinger: AudioStreamPlayer
var _last_mission_banner := ""
var _knocked_out := false
var _marker_labels: Array[Rect2] = []
var _health_area := Rect2()
var _font: Font
var _notices: Array = []  # [text, msec when it goes]
var _options_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	Net.player_joined.connect(func(id: int) -> void:
		if Net.is_public and Net.is_newcomer(id):  # (strangers: say who came)
			# Once their name has had a moment to arrive.
			get_tree().create_timer(NAME_WAIT).timeout.connect(func() -> void:
				if Net.peers().has(id):
					notify("%s joined" % Net.player_name(id))))
	Net.left_room.connect(func(id: int) -> void:
		if Net.is_online():
			notify("%s left" % Net.player_name(id)))
	Net.host_changed.connect(func(id: int) -> void:
		# The host left, or the server named another (not: we joined, or left);
		# nobody minds who hosts a public game.
		if Net.is_online() and not Net.is_public:
			notify("You're the host now" if id == Net.local_id() else "%s is now the host" % Net.player_name(id)))
	_add_options_button()


## Shows a line near the top of the screen for a few seconds.
func notify(text: String) -> void:
	_notices.append([text, Time.get_ticks_msec() + int(NOTICE_TIME * 1000.0)])


## The notices showing now.
func current_notices() -> PackedStringArray:
	var now := Time.get_ticks_msec()
	_notices = _notices.filter(func(notice: Array) -> bool: return notice[1] > now)
	return PackedStringArray(_notices.map(func(notice: Array) -> String: return notice[0]))


func _process(delta: float) -> void:
	banner_remaining = maxf(0.0, banner_remaining - delta)
	if hero and hero.mode:
		var knocked := hero.mode.name == &"KnockedOut"
		if knocked and not _knocked_out and (banner_title != "BUSTED" or banner_remaining <= 0.0):
			show_banner("KNOCKED OUT", "Back on your feet soon", HudStyle.RED)
		_knocked_out = knocked
	if missions:
		if missions.banner_remaining <= 0.0:
			_last_mission_banner = ""
		elif missions.banner != _last_mission_banner:
			_last_mission_banner = missions.banner
			if banner_title != "BUSTED" or banner_remaining <= 0.0:
				if missions.banner.begins_with("MISSION PASSED"):
					show_banner("MISSION PASSED", missions.banner.trim_prefix("MISSION PASSED").strip_edges())
				elif missions.banner.begins_with("BUSTED"):
					show_banner("BUSTED", missions.banner.trim_prefix("BUSTED").strip_edges(), HudStyle.RED)
				elif missions.banner == "MISSION FAILED" and not _knocked_out:
					show_banner("MISSION FAILED", "Retry from Pause → Missions", HudStyle.RED)
				else:
					notify(missions.banner)
	queue_redraw()


func _draw() -> void:
	_marker_labels.clear()
	if not hero or size.x < 1.0 or size.y < 1.0:
		return
	var bar := Rect2(24.0, size.y - 68.0, 204.0, 7.0)
	if radar and radar.visible:
		bar = Rect2(radar.position + Vector2(0.0, -14.0 if touch_controls else radar.size.y + 12.0), Vector2(radar.size.x, 7.0))
	elif touch_controls:
		bar = Rect2(touch_controls.safe_insets.x + 16.0, touch_controls.safe_insets.y + 72.0, 136.0, 7.0)
	_health_area = bar.grow(8.0)
	draw_rect(bar.grow(3.0), Color(0.0, 0.0, 0.0, 0.7))
	var health := clampf(hero.health / hero.max_health, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * health, bar.size.y)), HudStyle.GREEN if health > 0.25 else HudStyle.RED)
	_text(bar.position + Vector2(0, -7 if touch_controls else 24), "HEALTH  %d" % ceili(health * 100.0), 11, HudStyle.MUTED)
	if banner_remaining > 0.0:
		_draw_banner()
		_draw_aerial_credit()
		return
	_draw_wanted()
	_draw_coop_status()
	if missions:
		for marker in missions.markers():
			var target := WorldOrigin.to_local(marker.position) + Vector3.UP * 2.0
			if missions.active:
				_draw_marker(target, marker.label, marker.color, 0.0)
			elif target.distance_to(hero.global_position) < 150.0:
				_draw_marker(target, marker.label, marker.color, 0.0, false)
	if shops:
		for marker in shops.markers():
			var target := WorldOrigin.to_local(marker.position) + Vector3.UP * 2.0
			if target.distance_to(hero.global_position) <= 150.0:
				_draw_marker(target, marker.label.to_upper(), marker.color, 0.0, false)
	_draw_aerial_credit()
	var mission_pin := missions != null and missions.active != null and radar != null \
		and radar.waypoint_position.distance_squared_to(missions.current_target()) < 1.0
	if radar and radar.waypoint_active and not mission_pin:
		_draw_marker(WorldOrigin.to_local(radar.waypoint_position) + Vector3.UP * 2.0, "WAYPOINT", Radar.WAYPOINT_COLOR, 0.0)
	var thug := encounters.nearest_thug(hero.world_position()) if encounters else null
	if thug and (missions == null or missions.active == null):
		_draw_marker(thug.global_position + Vector3.UP * 2.2, "HOSTILE", MARKER_COLOR, NEAR_ENOUGH)
	var ids: Array = players.remote_heroes.keys() if players else []
	if ids.size() > MAX_PLAYER_MARKERS:
		var at := hero.global_position
		ids.sort_custom(func(a: int, b: int) -> bool:
			return (players.remote_heroes[a] as Hero).global_position.distance_squared_to(at) \
				< (players.remote_heroes[b] as Hero).global_position.distance_squared_to(at))
		ids.resize(MAX_PLAYER_MARKERS)
	for id: int in ids:
		var other: Hero = players.remote_heroes[id]
		_draw_marker(other.global_position + Vector3.UP * 2.6, Net.player_name(id).to_upper() + ("  WANTED %d★" % other.wanted_stars if other.wanted_stars > 0 else ""),
			Net.player_color(id).lightened(0.35), PLAYER_NEAR_ENOUGH)


func _draw_coop_status() -> void:
	var y := 34.0
	if touch_controls:
		y += touch_controls.safe_insets.y
	var debug := get_parent().get_node_or_null("DebugLabel") as Control
	if debug and debug.visible:
		y += 100.0
	if Net.is_reconnecting():
		_text(Vector2(24.0, y), "CO-OP · RECONNECTING", 14, HudStyle.MUTED)
		y += 30.0
	var notices := current_notices()
	var count := mini(1 if touch_controls else 3, notices.size())
	for i in count:
		var text := notices[notices.size() - count + i]
		var width := minf(size.x * (0.48 if touch_controls else 0.55), 620.0)
		var measured := _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 14)
		var height := maxf(34.0, measured.y + 12.0)
		draw_rect(Rect2(20.0, y - 19.0, width, height), HudStyle.INK)
		draw_rect(Rect2(20.0, y - 19.0, 3.0, height), HudStyle.GOLD)
		draw_multiline_string(_font, Vector2(32.0, y + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 14)
		y += height + 6.0


## A marker pointing at a scene position, labeled with the distance to it.
## Skipped when the spot is on screen and closer than `near_enough`.
func _draw_marker(target: Vector3, label: String, color: Color, near_enough: float, allow_edge := true) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or size.x < EDGE_MARGIN * 3.0 or size.y < EDGE_MARGIN * 3.0:
		return
	# A target on the camera plane has no finite screen projection.
	if absf(camera.to_local(target).z) < 0.01:
		return
	var distance := target.distance_to(hero.global_position)
	var behind := camera.is_position_behind(target)
	var point := camera.unproject_position(target)
	var area := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	if touch_controls:
		# Clear of notches, and left of the column of touch buttons.
		var insets := touch_controls.safe_insets + Vector4(0.0, 0.0, TOUCH_BUTTONS_WIDTH, 0.0)
		area = Rect2(area.position + Vector2(insets.x, insets.y), area.size - Vector2(insets.x + insets.z, insets.y + insets.w))
	var on_screen := not behind and area.has_point(point)
	if not allow_edge and not on_screen:
		return  # Nearby givers never become edge arrows; the radar carries direction.
	if on_screen and distance < near_enough:
		return

	var center := area.get_center()  # the screen's middle, less any notches
	var direction := (point - center).normalized()
	if behind:
		direction = -direction
	if not on_screen:
		# Slide out from the middle of the screen to its edge.
		var reach := minf(
			absf((area.size.x * 0.5) / direction.x) if absf(direction.x) > 0.001 else INF,
			absf((area.size.y * 0.5) / direction.y) if absf(direction.y) > 0.001 else INF)
		point = center + direction * reach
	if _options_button and _options_button.visible:
		var button := _options_button.get_rect().grow(24.0)  # (kept clear of it)
		if button.has_point(point):
			point.y = button.end.y
	var text := "%s %d m" % [label, distance]
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
	var at := point + Vector2(-34.0, 30.0) - direction * 10.0
	at.x = clampf(at.x, 16.0, maxf(16.0, size.x - width - 16.0))
	at.y = clampf(at.y, 32.0, size.y - 24.0)
	var label_area := Rect2(at - Vector2(2.0, 17.0), Vector2(width + 4.0, 24.0))
	var reserved: Array[Rect2] = [_health_area, Rect2(size.x * 0.22, size.y - 110.0, size.x * 0.56, 110.0),
		Rect2(wanted_anchor() - Vector2(155.0, 20.0), Vector2(185.0, 102.0))]
	if radar and radar.visible:
		reserved.append(Rect2(radar.position, radar.size + Vector2(0.0, 44.0)).grow(8.0))
	reserved.append_array(_marker_labels)
	var clear := false
	for attempt in 5:
		clear = true
		for occupied in reserved:
			if label_area.intersects(occupied):
				clear = false
				break
		if clear:
			break
		if not allow_edge:
			return
		at.y -= 27.0
		label_area.position.y -= 27.0
	var side := Vector2(-direction.y, direction.x)
	var tip := point + direction * 14.0
	draw_colored_polygon(PackedVector2Array([tip, point - direction * 6.0 + side * 10.0, point - direction * 6.0 - side * 10.0]), color)
	if clear:
		_marker_labels.append(label_area)
		_text(at, text, 15, color)


## A small button in the top right corner: "OPTIONS  O". It never takes the
## keyboard's focus (Space would press it), and works as the mouse button
## goes down: the menu is open by the time the hero would read it as a punch.
func _add_options_button() -> void:
	_options_button = Button.new()
	_options_button.name = "OptionsButton"
	_options_button.text = "PAUSE  ·  P"
	_options_button.theme = HudStyle.theme()
	_options_button.focus_mode = Control.FOCUS_NONE
	_options_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_options_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_options_button.add_theme_font_size_override("font_size", 14)
	# Pinned 16 px from the right edge, growing leftwards to fit its text.
	_options_button.anchor_left = 1.0
	_options_button.anchor_right = 1.0
	_options_button.offset_left = -16.0
	_options_button.offset_right = -16.0
	_options_button.offset_top = 14.0
	_options_button.offset_bottom = 14.0
	_options_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_options_button.pressed.connect(options_requested.emit)
	_options_button.visible = touch_controls == null
	add_child(_options_button)


func _text(at: Vector2, text: String, font_size: int, color := Color.WHITE) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color.BLACK)
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


## Five polygon stars avoid relying on a font's star glyph on web/phones.
func _draw_wanted() -> void:
	if hero.wanted_stars <= 0:
		return
	var anchor := wanted_anchor()
	var right := anchor.x
	var y := anchor.y
	var flashing := hero.wanted_searching and fmod(Time.get_ticks_msec() / 1000.0, 0.8) > 0.4
	for i in 5:
		var center := Vector2(right - (4 - i) * 29.0, y)
		var points := PackedVector2Array()
		for k in 10:
			var angle := -PI / 2.0 + k * PI / 5.0
			points.append(center + Vector2(cos(angle), sin(angle)) * (12.0 if k % 2 == 0 else 5.5))
		var color := Color(1.0, 0.85, 0.25) if i < hero.wanted_stars else Color(0.25, 0.28, 0.34)
		if flashing:
			color.a = 0.35
		draw_colored_polygon(points, color)
		points.append(points[0])
		draw_polyline(points, Color.BLACK, 1.5, true)
	_text(Vector2(right - 128.0, y + 30.0), "SEARCHING" if hero.wanted_searching else "WANTED", 14, NOTICE_COLOR)


## Shared anchor for the cash readout below the wanted stars and label.
func wanted_anchor() -> Vector2:
	var right := size.x - 28.0
	var y := 76.0
	var debug := get_parent().get_node_or_null("DebugLabel") as Control
	if debug and debug.visible:
		y = 132.0  # Below the four desktop stats/control lines.
	if touch_controls:
		right -= touch_controls.safe_insets.z + TOUCH_BUTTONS_WIDTH
		y = touch_controls.safe_insets.y + 84.0
	return Vector2(right, y)


## A cheap neutral overlay avoids another screen-reading shader on WebGL2.
func show_banner(title: String, detail := "", color := HudStyle.GOLD) -> void:
	banner_title = title
	banner_detail = detail
	_banner_color = color
	banner_remaining = 6.0
	if not _stinger:
		_stinger = AudioStreamPlayer.new()
		_stinger.volume_db = -15.0
		add_child(_stinger)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(11025 * 2)
	for i in 11025:
		var t := float(i) / 22050.0
		var frequency := 440.0 if color == HudStyle.GOLD else 146.83
		var wave := sin(TAU * frequency * t) + 0.4 * sin(TAU * frequency * 1.5 * t)
		samples.encode_s16(i * 2, int(wave * exp(-8.0 * t) * 12000.0))
	stream.data = samples
	_stinger.stream = stream
	_stinger.play()


func _draw_banner() -> void:
	var fade := minf(1.0, banner_remaining)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.16, 0.42 * fade))
	draw_rect(Rect2(0.0, size.y * 0.36, size.x, size.y * 0.27), Color(0.01, 0.015, 0.02, 0.74 * fade))
	var font_size := clampi(int(size.x / maxf(banner_title.length() * 0.68, 1.0)), 12, 64)
	var width := _font.get_string_size(banner_title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_text(Vector2((size.x - width) * 0.5, size.y * 0.49), banner_title, font_size, Color(_banner_color, fade))
	width = _font.get_string_size(banner_detail, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
	_text(Vector2((size.x - width) * 0.5, size.y * 0.56), banner_detail, 17, Color(1, 1, 1, fade))


func _draw_aerial_credit() -> void:
	if city and city.photo_count > 0:
		var width := _font.get_string_size(AERIAL_CREDIT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		var at := Vector2(size.x - width - 16.0, size.y - 12.0)
		if touch_controls:  # bottom middle, between the thumbs
			at = Vector2((size.x - width) * 0.5, size.y - touch_controls.safe_insets.w - 8.0)
		_text(at, AERIAL_CREDIT, 12, Color(1.0, 1.0, 1.0, 0.8))
