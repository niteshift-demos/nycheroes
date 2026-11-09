class_name ThreatAwareness
extends Control
## Local fight cues use authoritative intent, a short range and hero line of sight.
## They do not reveal idle gangs, enemies behind walls or pedestrian positions.

const RANGE := 24.0
const MAX_CUES := 3
const AMBER := Color(1.0, 0.77, 0.25)
const RED := Color(1.0, 0.28, 0.22)

var shown_count := 0
var incoming_count := 0
var _box: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.02, 0.02, 0.02, 0.85)
	_box.set_corner_radius_all(4)


## Kept separate from projection so combat eligibility is identical on every screen.
static func eligible(thug: Thug, hero: Hero) -> bool:
	return is_instance_valid(thug) and not thug.is_down() and not thug.frozen \
		and hero.can_be_attacked() and thug.threat_target() == Net.local_id() \
		and thug.threat_state() in [Thug.State.CHASE, Thug.State.PUNCH, Thug.State.RECOVER] \
		and absf(thug.global_position.y - hero.global_position.y) <= Thug.REACH_HEIGHT \
		and thug.global_position.distance_squared_to(hero.global_position) <= RANGE * RANGE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	shown_count = 0
	incoming_count = 0
	var hud := get_parent() as GameHud
	var camera := get_viewport().get_camera_3d()
	if hud == null or not is_instance_valid(hud.hero) or camera == null:
		return
	var hero := hud.hero
	var candidates: Array[Thug] = []
	for thug in Combat.thugs:
		if eligible(thug, hero):
			candidates.append(thug)
	candidates.sort_custom(func(a: Thug, b: Thug) -> bool:
		var a_in := a.incoming_seconds() > 0.0
		var b_in := b.incoming_seconds() > 0.0
		if a_in != b_in:
			return a_in
		return a.global_position.distance_squared_to(hero.global_position) < b.global_position.distance_squared_to(hero.global_position))
	var area := Rect2(Vector2(78.0, 110.0), size - Vector2(156.0, 220.0))
	if hud.touch_controls:
		var insets := hud.touch_controls.safe_insets
		area.position += Vector2(insets.x + 30.0, insets.y)
		area.size -= Vector2(insets.x + insets.z + 130.0, insets.y + insets.w + 60.0)
	if area.size.x < 80.0 or area.size.y < 80.0:
		return
	for thug in candidates:
		if shown_count >= MAX_CUES:
			break
		var ray := PhysicsRayQueryParameters3D.create(hero.global_position + Vector3.UP * 1.2, thug.body_center(), Combat.WORLD_LAYER)
		if not hero.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var target := thug.global_position + Vector3.UP * 2.5
		var point := camera.unproject_position(target)
		var behind := camera.is_position_behind(target)
		var offscreen := behind or not area.has_point(point)
		var seconds := thug.incoming_seconds()
		var incoming := seconds > 0.0
		if not offscreen and not incoming:
			continue
		var direction := point - area.get_center()
		if behind:
			direction = -direction
		if direction.length_squared() < 0.01:
			direction = Vector2.DOWN
		direction = direction.normalized()
		if offscreen:
			var reach := minf(area.size.x * 0.5 / maxf(absf(direction.x), 0.001), area.size.y * 0.5 / maxf(absf(direction.y), 0.001))
			point = area.get_center() + direction * reach
			var side := direction.orthogonal()
			var arrow := point + direction * 30.0 if incoming else point
			draw_colored_polygon(PackedVector2Array([arrow + direction * 15.0, arrow - direction * 9.0 + side * 9.0, arrow - direction * 9.0 - side * 9.0]), RED if incoming else AMBER)
		var color := RED if incoming else AMBER
		var label := "THREAT"
		if incoming:
			incoming_count += 1
			label = "PUNCH %.1fs" % seconds
			# The ring empties toward contact, using the unchanged 0.45 s windup.
			draw_circle(point, 21.0, Color(0.02, 0.02, 0.02, 0.8))
			draw_arc(point, 19.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(seconds / Thug.PUNCH_HIT_TIME, 0.0, 1.0), 24, color, 4.0, true)
			_label(point + Vector2(-5.0, 7.0), "!", color, 21)
		var width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var at := point + Vector2(-width * 0.5, 41.0)
		draw_style_box(_box, Rect2(at + Vector2(-6.0, -18.0), Vector2(width + 12.0, 25.0)))
		_label(at, label, color, 16)
		shown_count += 1


func _label(at: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
