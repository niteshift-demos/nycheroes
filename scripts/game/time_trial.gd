class_name TimeTrial
extends Node3D
## An optional checkpoint time trial in the streamed city: a short course
## from Times Square north up Seventh Avenue and east along a cross street to
## Sixth Avenue (about 550 m, four gates after the start).
##
## Running through the green start gate starts the clock; the gates must then
## be cleared in order, each by passing through it with the hero's own
## movement (running, super speed, jumps, webs or low flight: no power is
## sped up or switched off for it). A gate only counts within GATE_RADIUS of
## its middle and below GATE_TOP over the street: flying over the rooftops
## past a gate doesn't clear it. The run fails when TIME_LIMIT runs out.
## The finish shows the time and the best one, which is remembered (the
## "time_trial_best" setting).
##
## retry() (R, the gamepad's Back button, or the HUD's Retry button) puts the
## hero back a little before the start gate, facing it, with the clock reset;
## running into the start gate again also starts over at any time but during
## a run.
##
## Gates are drawn with small unshaded materials of their own (no big shader
## is touched) and are placed by world position: the node floats with
## WorldOrigin, and the gates' heights are taken from the street under them
## once that has loaded (the course's own heights are only a first guess).
##
## Co-op: the trial is each player's own. Nothing about it is sent to the
## others, who neither see your gates nor your time (see ROADMAP.md).
## GameHud draws the clock, the markers and the result. The console gets a
## "[trial]" line at the start, each checkpoint, the end and a retry.

## A gate was run through: 0 is the start (the clock starts), then 1..gate_count().
signal gate_cleared(index: int, seconds: float)
## The run reached the finish gate. `best` says whether it beat the best time.
signal finished(seconds: float, best: bool)
## TIME_LIMIT ran out before the finish.
signal failed(seconds: float)

enum State { READY, RUNNING, FINISHED, FAILED }

## Manhattan's avenues run about 29 degrees east of north; streets cross them.
const AVENUE := Vector3(0.485, 0.0, -0.875)
const STREET := Vector3(0.875, 0.0, 0.485)
## The start gate, then the checkpoints, the last of them the finish (world
## meters: the street's height near each, refined once collision is in).
## Seventh Avenue just north of Times Square; two blocks on; the corner at
## West 50th Street; halfway along it; Sixth Avenue.
const COURSE: Array[Vector3] = [
	Vector3(19.4, 14.5, -35.0),
	Vector3(92.2, 15.3, -166.3),
	Vector3(156.2, 16.5, -281.8),
	Vector3(269.9, 17.0, -218.7),
	Vector3(385.4, 17.4, -154.7),
]
## A gate is cleared within this horizontal distance of its middle (m)...
const GATE_RADIUS := 7.0
## ...and between this far below its street and GATE_TOP above it.
const GATE_BOTTOM := 3.0
const GATE_TOP := 25.0
## The drawn hoop: its radius and the height of its middle over the street.
const HOOP_RADIUS := 6.0
const HOOP_HEIGHT := 5.0
## A beam over each gate shows it from afar (m tall).
const BEAM_HEIGHT := 140.0
## The run fails after this long (s). On foot without super speed, the
## course takes about a minute.
const TIME_LIMIT := 90.0
## retry() puts the hero this far before the start gate (m).
const RETRY_BACK := 25.0
## The HUD shows a finished or failed run's result this long (s).
const RESULT_TIME := 10.0
const BEST_SETTING := "time_trial_best"

const START_COLOR := Color(0.3, 1.0, 0.45)
const NEXT_COLOR := Color(1.0, 0.82, 0.2)
const LATER_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const FINISH_COLOR := Color(1.0, 0.4, 0.85)

@export var game: Game
@export var hero: Hero
@export var city: CityStreamer

var state := State.READY
## Seconds since the start gate (frozen at the finish or failure).
var elapsed := 0.0
## The gate to run through next: 1..gate_count() while running.
var next_gate := 1
## Seconds at each cleared checkpoint of the current (or last) run.
var splits := PackedFloat64Array()
## The best finish (s), or 0 if there's none yet.
var best := 0.0
## Whether the last finish beat the best before it.
var new_best := false
## Seconds since the last run finished or failed.
var since_end := INF

var _gates: Array[Node3D] = []
## Gate heights, refined from the city's collision (see the top).
var _heights := PackedFloat64Array()
var _height_known: Array[bool] = []
var _was_in_start := false
var _materials := {}


func _ready() -> void:
	add_to_group("floating")
	global_position = WorldOrigin.to_local(Vector3.ZERO)
	process_physics_priority = 10  # after the hero has moved
	best = float(Settings.get_value(BEST_SETTING, 0.0))
	for color: Color in [START_COLOR, NEXT_COLOR, LATER_COLOR, FINISH_COLOR]:
		_materials[color] = [_material(color, color.a), _material(color, color.a * 0.35)]
	for n in COURSE.size():
		_heights.append(COURSE[n].y)
		_height_known.append(false)
		_gates.append(_make_gate(n))
	_refresh_gates()


## How many gates follow the start (the last is the finish).
func gate_count() -> int:
	return COURSE.size() - 1


## A gate's world position, on the street (0 is the start).
func gate_position(index: int) -> Vector3:
	return Vector3(COURSE[index].x, _heights[index], COURSE[index].z)


## Whether the hero at a world position is inside a gate (see the top).
func is_in_gate(index: int, world_position: Vector3) -> bool:
	var gate := gate_position(index)
	var rise := world_position.y - gate.y
	return Vector2(world_position.x - gate.x, world_position.z - gate.z).length() <= GATE_RADIUS \
		and rise >= -GATE_BOTTOM and rise <= GATE_TOP


## Seconds left before the run fails.
func time_left() -> float:
	return maxf(TIME_LIMIT - elapsed, 0.0)


## Back to a little before the start gate, facing it, the clock reset.
func retry() -> void:
	state = State.READY
	elapsed = 0.0
	next_gate = 1
	splits.clear()
	since_end = INF
	_was_in_start = false
	var start := gate_position(0)
	var spot := start - AVENUE * RETRY_BACK
	print("[trial] retry")
	if game:
		game.place_hero(Vector3(spot.x, start.y + 3.0, spot.z), atan2(-AVENUE.x, -AVENUE.z), true)
	_refresh_gates()


## "1:05.32"
static func format_time(seconds: float) -> String:
	var hundredths := roundi(seconds * 100.0)
	return "%d:%02d.%02d" % [hundredths / 6000, (hundredths / 100) % 60, hundredths % 100]


func _physics_process(delta: float) -> void:
	_settle_heights()
	if hero == null or hero.frozen:
		return
	var at := hero.world_position()
	var in_start := is_in_gate(0, at)
	if state == State.RUNNING:
		elapsed += delta
		if is_in_gate(next_gate, at):
			splits.append(elapsed)
			print("[trial] checkpoint %d of %d at %s" % [next_gate, gate_count(), format_time(elapsed)])
			gate_cleared.emit(next_gate, elapsed)
			if next_gate == gate_count():
				_finish()
			else:
				next_gate += 1
				_refresh_gates()
		elif elapsed >= TIME_LIMIT:
			elapsed = TIME_LIMIT
			state = State.FAILED
			since_end = 0.0
			_refresh_gates()
			print("[trial] time's up after %d of %d checkpoints" % [next_gate - 1, gate_count()])
			failed.emit(elapsed)
	else:
		since_end += delta
		if in_start and not _was_in_start:
			_start()
	_was_in_start = in_start


func _start() -> void:
	state = State.RUNNING
	elapsed = 0.0
	next_gate = 1
	splits.clear()
	new_best = false
	since_end = INF
	_refresh_gates()
	print("[trial] started")
	gate_cleared.emit(0, 0.0)


func _finish() -> void:
	state = State.FINISHED
	since_end = 0.0
	new_best = best <= 0.0 or elapsed < best
	if new_best:
		best = elapsed
		Settings.set_value(BEST_SETTING, best)
	_refresh_gates()
	print("[trial] finished in %s%s" % [format_time(elapsed), " (new best)" if new_best else ""])
	finished.emit(elapsed, new_best)


## Puts each gate on the street under it once that has collision: searching
## down from a little above the course's height finds the street, not a roof.
func _settle_heights() -> void:
	if city == null:
		return
	for n in COURSE.size():
		if _height_known[n] or not city.has_collision_at(COURSE[n]):
			continue
		var ground := city.ground_height_at(COURSE[n], 6.0)
		_height_known[n] = true
		if not is_nan(ground) and absf(ground - COURSE[n].y) < 6.0:
			_heights[n] = ground
			_gates[n].position = gate_position(n)


func _refresh_gates() -> void:
	for n in _gates.size():
		var color := LATER_COLOR
		var shown := true
		if n == 0:
			color = START_COLOR
			shown = state != State.RUNNING
		elif state == State.RUNNING:
			shown = n >= next_gate
			if n == next_gate:
				color = FINISH_COLOR if n == gate_count() else NEXT_COLOR
		elif n == gate_count():
			color = FINISH_COLOR
		_gates[n].visible = shown
		var hoop := _gates[n].get_child(0) as MeshInstance3D
		var beam := _gates[n].get_child(1) as MeshInstance3D
		hoop.material_override = _materials[color][0]
		beam.material_override = _materials[color][1]


## A hoop standing across the course, facing the way it goes, and a beam over it.
func _make_gate(index: int) -> Node3D:
	var gate := Node3D.new()
	gate.name = "Start" if index == 0 else ("Finish" if index == gate_count() else "Gate%d" % index)
	gate.position = gate_position(index)
	var along := AVENUE
	if index > 0:
		along = (COURSE[index] - COURSE[index - 1]).normalized()
	if index < gate_count():
		along = (along + (COURSE[index + 1] - COURSE[index]).normalized()).normalized()
	gate.rotation.y = atan2(-along.x, -along.z)
	var torus := TorusMesh.new()
	torus.inner_radius = HOOP_RADIUS - 0.35
	torus.outer_radius = HOOP_RADIUS + 0.35
	torus.rings = 48
	torus.ring_segments = 8
	var hoop := MeshInstance3D.new()
	hoop.mesh = torus
	hoop.rotation.x = PI * 0.5  # (a torus lies flat; stood up across the way)
	hoop.position.y = HOOP_HEIGHT
	hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(hoop)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.6
	cylinder.bottom_radius = 0.6
	cylinder.height = BEAM_HEIGHT
	cylinder.radial_segments = 8
	cylinder.rings = 1
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = cylinder
	beam.position.y = HOOP_HEIGHT + HOOP_RADIUS + BEAM_HEIGHT * 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(beam)
	add_child(gate)
	return gate


func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.disable_fog = alpha < 1.0
	return material
