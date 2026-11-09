class_name ThreatWarning
extends Control
## Warns the player of a punch about to land on their hero, while there's
## still time to react (Thug.PUNCH_HIT_TIME): hit the thug first (a hit cuts
## its swing short), or get out of reach or out from in front of it.
##
## Each thug winding up a punch at our hero gets two marks, drawn from its
## real windup (Thug.windup_progress), so they close exactly as the punch
## lands:
## - around the hero, an arc on the side the punch comes from, as seen from
##   the camera (top: in front of the camera's view, bottom: behind it). It
##   fattens and reddens as the swing comes in, and reads even when the thug
##   is behind the camera;
## - over the thug's head, when it's on screen, a ring closing in on a dot.
##
## Nothing else in the city gets a mark: only thugs swinging at our hero, at
## most Combat.MAX_ATTACKERS at once, and only while they swing. Copies of
## thugs another player's game runs (co-op) are judged by their punch
## animation and where they face (Thug.winding_up_at), and drawn as late as
## the copy itself is.

## Thugs further away than this can't be about to hit (Thug.ATTACK_RANGE plus
## how far a hero can be pushed between ticks), so they're never looked at.
const RANGE := 4.0
## The arc's distance from the hero on screen, as a share of the screen's
## shorter side.
const ARC_RADIUS := 0.13
## Half the arc's angle (radians).
const ARC_HALF_ANGLE := 0.42
const EARLY_COLOR := Color(1.0, 0.78, 0.2)
const LATE_COLOR := Color(1.0, 0.16, 0.1)

## The hero being warned: ours.
var hero: Hero


func _ready() -> void:
	# (Offsets too: made in code, it starts out 0 x 0.)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


## The thugs winding up a punch at the hero now, each as [thug, progress 0..1].
func incoming() -> Array:
	var threats: Array = []
	if hero == null or not hero.can_be_attacked():
		return threats
	for thug: Thug in Combat.thugs:
		if thug.global_position.distance_squared_to(hero.global_position) > RANGE * RANGE:
			continue
		if thug.winding_up_at(hero):
			threats.append([thug, thug.windup_progress()])
	return threats


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var threats := incoming()
	if threats.is_empty():
		return
	var chest := hero.global_position + Vector3.UP * 1.1
	var center := size * 0.5 if camera.is_position_behind(chest) else camera.unproject_position(chest)
	var radius := minf(size.x, size.y) * ARC_RADIUS
	var right := camera.global_basis.x
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length_squared() > 0.0001 else Vector3.FORWARD
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	for threat: Array in threats:
		var thug: Thug = threat[0]
		var progress: float = threat[1]
		var color := EARLY_COLOR.lerp(LATE_COLOR, progress)
		# Around the hero: which side, seen from above the camera's shoulder.
		var offset := thug.global_position - hero.global_position
		var angle := atan2(-offset.dot(ahead), offset.dot(right))
		var width := lerpf(4.0, 11.0, progress)
		color.a = lerpf(0.55, 0.95, progress)
		draw_arc(center, radius + 10.0, angle - ARC_HALF_ANGLE, angle + ARC_HALF_ANGLE, 20,
			Color(0.0, 0.0, 0.0, 0.45 * color.a), width + 4.0, true)
		draw_arc(center, radius + 10.0, angle - ARC_HALF_ANGLE, angle + ARC_HALF_ANGLE, 20, color, width, true)
		# A notch in the arc's middle, pointing in at the hero.
		var tip := center + Vector2.from_angle(angle) * (radius - 4.0)
		var base := center + Vector2.from_angle(angle) * (radius + 10.0)
		var side := Vector2.from_angle(angle + PI * 0.5) * (6.0 + 6.0 * progress)
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), color)
		# Over the thug: a ring closing in as the punch comes.
		var head := thug.global_position + Vector3.UP * 2.05
		if camera.is_position_behind(head):
			continue
		var at := camera.unproject_position(head)
		if not Rect2(Vector2.ZERO, size).has_point(at):
			continue
		draw_circle(at, 5.0, Color(0.0, 0.0, 0.0, 0.5))
		draw_circle(at, 3.5, color)
		var ring := lerpf(26.0, 7.0, progress)
		draw_arc(at, ring, 0.0, TAU, 28, Color(0.0, 0.0, 0.0, 0.5), 5.0, true)
		draw_arc(at, ring, 0.0, TAU, 28, color, 2.5, true)
