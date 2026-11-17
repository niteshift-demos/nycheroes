class_name GtaTiming
extends RefCounted
## Opt-in ?stats CPU parts. Nested car/mission calls subtract measured children
## so totals count work once. No timing reads or dictionaries in ordinary play.

static var enabled := false
static var total_usec := 0
static var parts: Dictionary[StringName, int] = {}
static var _last_tick := 0
static var _last_frame := 0


static func begin() -> Vector2i:
	# Vector2i has 32-bit components; wrap so long play sessions stay accurate.
	return Vector2i(Time.get_ticks_usec() % 1000000000, total_usec % 1000000000) if enabled else Vector2i.ZERO


static func end(part: StringName, stamp: Vector2i) -> void:
	if stamp == Vector2i.ZERO:
		return
	var elapsed := maxi(0, posmod(Time.get_ticks_usec() - stamp.x, 1000000000) - posmod(total_usec - stamp.y, 1000000000))
	parts[part] = parts.get(part, 0) + elapsed
	total_usec += elapsed


## Physics-normalized parts are comparable even when software rendering draws
## several physics ticks at once; also report the cost per actual drawn frame.
static func read() -> String:
	var ticks := Engine.get_physics_frames()
	var frames := Engine.get_process_frames()
	var physics_count := maxi(1, ticks - _last_tick)
	var frame_count := maxi(1, frames - _last_frame)
	var labels: PackedStringArray = []
	var sum := 0
	for part: StringName in parts:
		labels.append("%s %.3f" % [part, parts[part] / 1000.0 / physics_count])
		sum += parts[part]
	var text := "GTA CPU %.3f ms/tick; %.3f ms/drawn frame [%s]" % [sum / 1000.0 / physics_count, sum / 1000.0 / frame_count, ", ".join(labels)]
	parts.clear()
	_last_tick = ticks
	_last_frame = frames
	return text
