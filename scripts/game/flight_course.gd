class_name FlightCourse
extends Node3D
## The flight ring time trial: seven rings in a slalom up Central Park, from
## a start gate over the south end of the park (by 59th Street) to a finish
## ring by the Reservoir, between the Billionaires' Row towers behind and the
## park's trees below (60-90 m up, clear of everything by 30 m or more; the
## course test checks that against the city's collision).
##
## R (the "flight_course" action), the options menu's Ring course button, or
## ?course=1 at launch starts it: the hero is put in the air a short way
## before the green START ring, facing it, flying, and held there until the
## city around has loaded (like Game.travel_to). R again restarts it at any
## time; the menu's button or travelling elsewhere leaves it.
##
## Honest checkpoints: each physics tick, the hero's path since the last tick
## (in world coordinates, so origin shifts don't matter) is tested against
## the plane of the one ring it must fly through next. Crossing that plane
## forwards within RING_RADIUS of the ring's middle passes it; crossing it
## forwards further off but within MISS_RADIUS is a miss: the HUD says so and
## that ring stays the one to fly through (turn back and take it). Rings out
## of order, and crossings backwards, count for nothing. The clock starts the
## moment the hero crosses the start ring and stops the moment it crosses the
## finish, to the fraction of a physics tick (the crossing point along that
## tick's path), and only runs on physics time: it can't be paused or sped up
## by frame rate. The best time is remembered (Settings
## "flight_course_best").
##
## Co-op: the course is the local player's own; the hero still moves only by
## HeroInput and PlayerSync shows it as usual (a restart moves it like the Go
## to box does). Rings are drawn with a plain unshaded material (no new
## shader to compile), and each is in the "floating" group.

signal started
signal ring_passed(index: int, seconds: float)
signal ring_missed(index: int)
signal finished(seconds: float, best: bool)
signal stopped

enum State { OFF, READY, RUNNING, FINISHED }

## The rings' middles, in world meters (x east, z south of Times Square; y up).
## Along the park's long axis (29 degrees east of north) from (650, -1150),
## swinging 60-120 m either side of it.
const RINGS: Array[Vector3] = [
	Vector3(698.0, 72.0, -1237.0),  # START, over the park's south end
	Vector3(715.0, 64.0, -1514.0),
	Vector3(1020.0, 82.0, -1631.0),
	Vector3(975.0, 68.0, -1942.0),
	Vector3(1288.0, 88.0, -2054.0),
	Vector3(1252.0, 74.0, -2360.0),
	Vector3(1461.0, 80.0, -2530.0),  # FINISH, by the Reservoir
]
## Fly through within this distance of a ring's middle (m): the inside of the
## drawn ring.
const RING_RADIUS := 12.0
## The drawn tube's thickness (m).
const TUBE := 1.6
## Crossing a ring's plane further off than RING_RADIUS but within this is a
## miss (further off, the hero was nowhere near it).
const MISS_RADIUS := 50.0
## A start or restart puts the hero this far before the start ring (m).
const APPROACH := 70.0
## How long the HUD shows a miss, a split or the finish (s).
const MESSAGE_TIME := 2.5
const SETTING_BEST := "flight_course_best"
const START_COLOR := Color(0.25, 1.0, 0.45)
const NEXT_COLOR := Color(1.0, 0.78, 0.15)
const LATER_COLOR := Color(1.0, 1.0, 1.0, 0.35)
const FINISH_COLOR := Color(1.0, 0.3, 0.75)
const MISS_COLOR := Color(1.0, 0.2, 0.15)

## Our hero, and the game that places it.
var hero: Hero
var game: Game

var state := State.OFF
## The ring to fly through next (0 is the start ring).
var next_ring := 0
## Physics seconds since the hero crossed the start ring.
var elapsed := 0.0
## Elapsed time at each ring passed (index 0 is the start: 0).
var splits := PackedFloat64Array()
var best_time := INF
## The last thing that happened, for the HUD: text, color and when it goes
## (on `_clock`).
var message := ""
var message_color := Color.WHITE
var message_until := 0.0

var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _prev_world := Vector3.INF
var _flash_ring := -1
var _flash_until := 0.0
## Seconds of game time (frames' deltas, not the wall clock: messages and the
## pulse keep their pace however slowly frames are drawn, e.g. in a movie).
var _clock := 0.0


func _ready() -> void:
	# After the hero has moved this tick (it runs at 0).
	process_physics_priority = 5
	best_time = float(Settings.get_value(SETTING_BEST, INF))
	if best_time <= 0.0:
		best_time = INF
	for n in RINGS.size():
		_rings.append(_make_ring(n))
	_show_rings(false)


## Adds the "flight_course" action: R (and a gamepad's Back/Select).
static func add_action() -> void:
	if InputMap.has_action(&"flight_course"):
		return
	InputMap.add_action(&"flight_course")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	InputMap.action_add_event(&"flight_course", key)
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_BACK
	InputMap.action_add_event(&"flight_course", back)


## Each ring's plane faces along the course there: from the ring before it
## to the one after (world space, unit length).
static func ring_normal(index: int) -> Vector3:
	var before := RINGS[maxi(index - 1, 0)]
	var after := RINGS[mini(index + 1, RINGS.size() - 1)]
	return (after - before).normalized()


## Where a start puts the hero: before the start ring, facing it.
static func start_position() -> Vector3:
	return RINGS[0] - ring_normal(0) * APPROACH


func is_active() -> bool:
	return state != State.OFF


## Starts the course from the beginning (a restart while on it).
func start() -> void:
	state = State.READY
	next_ring = 0
	elapsed = 0.0
	splits = PackedFloat64Array()
	_prev_world = Vector3.INF
	_flash_ring = -1
	var toward := ring_normal(0)
	game.place_hero_flying(start_position(), atan2(-toward.x, -toward.z))
	_show_rings(true)
	_say("Fly through the green START ring", START_COLOR)
	started.emit()


## Leaves the course: the rings go and the clock stops.
func stop() -> void:
	if state == State.OFF:
		return
	state = State.OFF
	_prev_world = Vector3.INF
	_show_rings(false)
	message = ""
	stopped.emit()


## Rings left to fly through, counting the start ring.
func rings_left() -> int:
	return RINGS.size() - next_ring


## World position of the ring to fly through next (INF when there's none).
func next_ring_position() -> Vector3:
	return RINGS[next_ring] if state == State.READY or state == State.RUNNING else Vector3.INF


func current_message() -> String:
	return message if _clock < message_until else ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"flight_course") and not event.is_echo():
		start()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if state == State.RUNNING:
		elapsed += delta
	if state != State.READY and state != State.RUNNING:
		return
	if hero.frozen:
		_prev_world = Vector3.INF  # (held while the city loads: no path to test)
		return
	var now := hero.world_position()
	if _prev_world != Vector3.INF:
		_check_crossing(_prev_world, now, delta)
	_prev_world = now


func _process(delta: float) -> void:
	_clock += delta
	if state == State.OFF:
		return
	var pulse := 0.5 + 0.5 * sin(_clock * 6.0)
	for n in _rings.size():
		var material := _materials[n]
		var ring := _rings[n]
		ring.visible = n >= next_ring and state != State.FINISHED
		if not ring.visible:
			continue
		var color := LATER_COLOR
		if n == _flash_ring and _clock < _flash_until:
			color = MISS_COLOR
		elif n == next_ring:
			color = START_COLOR if n == 0 else (FINISH_COLOR if n == RINGS.size() - 1 else NEXT_COLOR)
			color = color.lerp(Color.WHITE, 0.25 * pulse)
		elif n == RINGS.size() - 1:
			color = Color(FINISH_COLOR, 0.45)
		material.albedo_color = color


## Tests one tick's path (world positions) against the next ring's plane.
func _check_crossing(from: Vector3, to: Vector3, delta: float) -> void:
	var center := RINGS[next_ring]
	var normal := ring_normal(next_ring)
	var before := (from - center).dot(normal)
	var after := (to - center).dot(normal)
	if not (before < 0.0 and after >= 0.0):
		return  # not through its plane, or backwards
	var t := before / (before - after)
	var through := from.lerp(to, t)
	var off := through.distance_to(center)
	if off <= RING_RADIUS:
		_pass_ring(delta * (1.0 - t))
	elif off <= MISS_RADIUS:
		_flash_ring = next_ring
		_flash_until = _clock + MESSAGE_TIME
		_say("MISSED %s by %.0f m: turn back and fly through it" % [_ring_name(next_ring), off - RING_RADIUS], MISS_COLOR)
		ring_missed.emit(next_ring)


## `since` is how long ago in this tick the hero went through (s).
func _pass_ring(since: float) -> void:
	if next_ring == 0:
		state = State.RUNNING
		elapsed = since
		splits.append(0.0)
		_say("GO!", START_COLOR)
		ring_passed.emit(0, 0.0)
		next_ring = 1
		return
	var at := elapsed - since
	splits.append(at)
	ring_passed.emit(next_ring, at)
	if next_ring == RINGS.size() - 1:
		elapsed = at
		state = State.FINISHED
		var best := at < best_time
		if best:
			best_time = at
			Settings.set_value(SETTING_BEST, at)
		_say("FINISHED in %s%s  ·  R to race again" % [format_time(at), "  ·  NEW BEST!" if best else ""], FINISH_COLOR, 8.0)
		finished.emit(at, best)
		return
	_say("Ring %d of %d  ·  %s" % [next_ring, RINGS.size() - 1, format_time(at)], NEXT_COLOR)
	next_ring += 1


static func format_time(seconds: float) -> String:
	if seconds == INF:
		return "--:--.--"
	var whole := int(seconds)
	return "%d:%02d.%02d" % [whole / 60, whole % 60, int((seconds - whole) * 100.0)]


func _ring_name(index: int) -> String:
	if index == 0:
		return "the START ring"
	if index == RINGS.size() - 1:
		return "the FINISH ring"
	return "ring %d" % index


func _say(text: String, color: Color, seconds := MESSAGE_TIME) -> void:
	message = text
	message_color = color
	message_until = _clock + seconds


func _show_rings(on: bool) -> void:
	for ring in _rings:
		ring.visible = on


func _make_ring(index: int) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = RING_RADIUS
	mesh.outer_radius = RING_RADIUS + TUBE
	mesh.rings = 48
	mesh.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = LATER_COLOR
	_materials.append(material)
	var ring := MeshInstance3D.new()
	ring.name = "Ring%d" % index
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.add_to_group("floating")
	# A torus lies flat around its Y axis: turn that axis along the course.
	var normal := ring_normal(index)
	var side := normal.cross(Vector3.UP).normalized()
	ring.global_transform = Transform3D(Basis(side, normal, side.cross(normal)), WorldOrigin.to_local(RINGS[index]))
	return ring
