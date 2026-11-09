class_name RooftopCourse
extends Node3D
## Rooftop run: a short checkpoint course over real roofs in Hell's Kitchen
## (West 44th to 46th Streets, between Eighth and Ninth Avenues, about 450 m
## west of Times Square), crossed with charged super jumps.
##
## - Start: land on the START pad (a cyan ring and light beam on a 31 m
##   tenement roof). The clock starts when the hero jumps off it.
## - Progress: land on each roof's pad in order (the amber beam is the next
##   one; reached ones turn green). Each is a checkpoint. The HUD shows the
##   roof number, the clock and the falls, with a marker to the next pad.
## - Finish: land on the FINISH pad, on the roof of a 112 m tower: the last
##   jump needs nearly a full charge. The time is kept as the best
##   ("rooftop_best" in Settings) if it beats it.
## - Failing: touching down well below the last and the next roof (the street,
##   or a low roof), landing in water, being knocked out, or flying, web
##   swinging or diving. After RETURN_DELAY the hero is put back on the last
##   checkpoint reached and the clock runs on, so a fall costs time.
## - Restart: R (a gamepad's Back, or the HUD's RESTART button on touch
##   screens) puts the hero back on the START pad with the clock cleared.
##
## Flight is fair game for getting to the start (the beam shows from across
## Midtown), but not during a run: the course is about judging charged jumps,
## and flying, a web or a dive's speed would skip every one of them. Taking
## off, swinging or diving ends the attempt the same way a fall does (back to
## the last checkpoint, the clock running on).
##
## Pads are kept in world coordinates and drawn at scene positions each
## frame, so they survive floating origin shifts. Each pad's height is the
## roof's as measured when its tile's collision is in (the numbers below are
## what the tiles had when the course was laid out, used until then).
## The run is the local player's own: other players see the same pads (they
## are fixed in the world), and each runs it on their own. The hero itself is
## moved only by its plain HeroInput, so co-op sees the run as ordinary
## jumping; returning to a checkpoint is a move like Game.place_hero's on
## joining a game.
##
## ?course=0 leaves the course out; ?course=start starts the hero on the
## START pad.

## A pad was reached (index: 0 is the start), a run started or failed.
signal pad_reached(index: int)
signal run_started
signal run_failed(reason: String)
signal run_finished(seconds: float, best: bool)

enum State { IDLE, ARMED, RUNNING, FAILED, FINISHED }

## Pads, in order: world x and z of a flat spot on each roof (its middle,
## clear of the roof's edges), and the roof's height above sea level then.
const PADS: Array[Vector3] = [
	Vector3(-419.0, 31.2, -208.0),  # START: a tenement on West 45th Street
	Vector3(-386.0, 45.8, -184.0),  # 2: up a few floors, next door but one
	Vector3(-335.0, 43.9, -196.0),  # 3: along the block
	Vector3(-266.0, 30.7, -211.0),  # 4: across the backyards, down
	Vector3(-236.0, 32.7, -196.0),  # 5: a short hop
	Vector3(-251.0, 58.9, -166.0),  # 6: up onto a mid-rise
	Vector3(-239.0, 111.7, -244.0),  # FINISH: the tower, a near-full charge
]
## How close (horizontally, m) to a pad's middle the hero must touch down,
## and how far above or below its roof (m).
const PAD_RADIUS := 7.0
const PAD_HEIGHT_TOLERANCE := 3.0
## Touching down this far below both the last checkpoint's roof and the next
## pad's (m) is a fall.
const DROP_BELOW := 6.0
## How long a failed attempt shows before the hero goes back (s).
const RETURN_DELAY := 2.0
## Modes that end a run: the course is run on foot.
const BANNED_MODES: Array[StringName] = [&"Flight", &"Swing", &"Dive"]
## Past this distance from the course (m), the HUD marker to the start goes,
## the pads hide, and a run in progress is abandoned (e.g. by Go to).
const SHOW_DISTANCE := 3000.0
const ABANDON_DISTANCE := 800.0
## The pads' beams reach this high over their roofs (m).
const BEAM_HEIGHT := 140.0
const BEST_KEY := "rooftop_best"
## How long the banner (a roof reached, a failure, the finish) shows, in
## game time (s): it keeps step with the clock at any frame rate.
const BANNER_TIME := 3.0
const FINISH_BANNER_TIME := 7.0
const COLOR_FAIL := Color(1.0, 0.4, 0.3)
## A pad's beam and number hide when the hero is this close (m): standing in
## them would fill the screen.
const HIDE_NEAR := 16.0

const COLOR_START := Color(0.25, 0.85, 1.0)
const COLOR_NEXT := Color(1.0, 0.7, 0.15)
const COLOR_DONE := Color(0.3, 1.0, 0.4)
const COLOR_LATER := Color(0.85, 0.85, 0.9)
const COLOR_FINISH := Color(1.0, 0.35, 0.85)

@export var hero: Hero
@export var game: Game
@export var city: CityStreamer

var state := State.IDLE
## The pad to land on next (while running), and the last one reached.
var next_index := 1
var last_index := 0
## Seconds since the run started (falls included), the falls so far, and
## the best finished time (0: none yet).
var elapsed := 0.0
var falls := 0
var best := 0.0
var last_time := 0.0
var fail_reason := ""
## The banner the HUD shows under the run's line while banner_time lasts.
var banner := ""
var banner_color := Color.WHITE
var banner_time := 0.0

var _heights: Array[float] = []
var _measured: Array[bool] = []
var _pads: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _beams: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _materials := {}  # Color -> [ring material, beam material]
var _fail_timer := 0.0


func _ready() -> void:
	# After the hero's own physics: this tick's landing is in.
	process_physics_priority = 5
	best = float(Settings.get_value(BEST_KEY, 0.0))
	for pad in PADS:
		_heights.append(pad.y)
		_measured.append(false)
	_build_pads()
	_add_action()


## R and a gamepad's Back restart the run (see the top).
static func _add_action() -> void:
	if InputMap.has_action(&"course_restart"):
		return
	InputMap.add_action(&"course_restart")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	InputMap.action_add_event(&"course_restart", key)
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_BACK
	InputMap.action_add_event(&"course_restart", back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"course_restart") and is_active():
		restart()
		get_viewport().set_input_as_handled()


## A run is armed, going or just failed (the HUD shows it).
func is_active() -> bool:
	return state == State.ARMED or state == State.RUNNING or state == State.FAILED


func pad_count() -> int:
	return PADS.size()


## A pad's world position: the middle of its roof.
func pad_world_position(index: int) -> Vector3:
	return Vector3(PADS[index].x, _heights[index], PADS[index].z)


## Puts the hero on the START pad, the clock cleared.
func restart() -> void:
	_place_on(0)
	state = State.ARMED
	next_index = 1
	last_index = 0
	elapsed = 0.0
	falls = 0
	fail_reason = ""
	banner_time = 0.0


## Horizontal distance from the hero to the nearest part of the course (m).
func distance_to_course() -> float:
	var at := hero.world_position()
	var nearest := INF
	for pad in PADS:
		nearest = minf(nearest, Vector2(pad.x - at.x, pad.z - at.z).length())
	return nearest


func _physics_process(delta: float) -> void:
	banner_time = maxf(banner_time - delta, 0.0)
	if hero == null or hero.frozen:
		return
	_measure_heights()
	match state:
		State.IDLE, State.FINISHED:
			if _on_pad(0):
				state = State.ARMED
				next_index = 1
				last_index = 0
				elapsed = 0.0
				falls = 0
		State.ARMED:
			if not _on_pad(0, true):
				if hero.mode.name in BANNED_MODES or distance_to_course() > ABANDON_DISTANCE:
					state = State.IDLE
				else:
					state = State.RUNNING
					_show("GO!", COLOR_NEXT, 1.2)
					run_started.emit()
		State.RUNNING:
			elapsed += delta
			_check_run()
		State.FAILED:
			elapsed += delta
			_fail_timer -= delta
			if _fail_timer <= 0.0:
				_place_on(last_index)
				state = State.RUNNING


func _check_run() -> void:
	if distance_to_course() > ABANDON_DISTANCE:
		state = State.IDLE  # gone elsewhere (Go to, joining a game)
		return
	if hero.mode.name in BANNED_MODES:
		_fail("No flying, webs or dives on the rooftop run")
		return
	if hero.mode.name == &"KnockedOut":
		_fail("Knocked out")
		return
	if hero.is_in_water():
		_fail("Splashed down")
		return
	if not hero.is_on_floor():
		return
	if _on_pad(next_index):
		last_index = next_index
		next_index += 1
		if next_index >= PADS.size():
			_finish()
		else:
			_show("ROOF %d OF %d  ·  %s" % [last_index + 1, PADS.size(), clock_text(elapsed)], COLOR_DONE)
		pad_reached.emit(last_index)
		return
	var floor_height := minf(_heights[last_index], _heights[next_index]) - DROP_BELOW
	if hero.world_position().y < floor_height:
		_fail("Fell to the street" if hero.world_position().y < _heights[last_index] - 12.0 else "Too low")


func _fail(reason: String) -> void:
	fail_reason = reason
	falls += 1
	state = State.FAILED
	_fail_timer = RETURN_DELAY
	_show("%s  ·  back to %s" % [reason.to_upper(), "the start" if last_index == 0 else "roof %d" % (last_index + 1)],
		COLOR_FAIL, RETURN_DELAY + 1.0)
	run_failed.emit(reason)


func _finish() -> void:
	state = State.FINISHED
	last_time = elapsed
	var is_best := best <= 0.0 or elapsed < best
	if is_best:
		best = elapsed
		Settings.set_value(BEST_KEY, best)
	_show("FINISHED IN %s  ·  %d fall%s%s" % [clock_text(elapsed), falls, "" if falls == 1 else "s",
		"  ·  BEST TIME!" if is_best else "  ·  best %s" % clock_text(best)], COLOR_FINISH, FINISH_BANNER_TIME)
	run_finished.emit(elapsed, is_best)


func _show(text: String, color: Color, seconds := BANNER_TIME) -> void:
	banner = text
	banner_color = color
	banner_time = seconds


## Minutes, seconds and tenths: 0:41.7.
static func clock_text(seconds: float) -> String:
	return "%d:%04.1f" % [floori(seconds / 60.0), fmod(seconds, 60.0)]


## Standing on a pad (or, with `or_rising`, still within its circle on the
## way up from it).
func _on_pad(index: int, or_rising := false) -> bool:
	if hero.mode.name != &"OnFoot" and hero.mode.name != &"Melee":
		return false
	var at := hero.world_position()
	var pad := pad_world_position(index)
	if Vector2(at.x - pad.x, at.z - pad.z).length() > PAD_RADIUS:
		return false
	if hero.is_on_floor():
		return absf(at.y - pad.y) <= PAD_HEIGHT_TOLERANCE
	return or_rising and at.y - pad.y < 1.0 and at.y > pad.y - PAD_HEIGHT_TOLERANCE


func _place_on(index: int) -> void:
	var pad := pad_world_position(index)
	var toward := pad_world_position(mini(index + 1, PADS.size() - 1)) - pad
	var facing := atan2(-toward.x, -toward.z) if index + 1 < PADS.size() else hero.facing
	game.place_hero(pad + Vector3.UP * 0.3, facing)


## Each pad's roof height, once the collision there is in.
func _measure_heights() -> void:
	for n in PADS.size():
		if _measured[n]:
			continue
		var pad := PADS[n]
		if not city.has_collision_at(pad):
			continue
		var height := city.ground_height_at(pad, 12.0)
		if not is_nan(height) and absf(height - pad.y) < 12.0:
			_heights[n] = height
		_measured[n] = true


func _process(_delta: float) -> void:
	var shown := hero != null and distance_to_course() < SHOW_DISTANCE
	visible = shown
	if not shown:
		return
	var at := hero.world_position()
	for n in _pads.size():
		var pad := pad_world_position(n)
		_pads[n].global_position = WorldOrigin.to_local(pad)
		var color := _pad_color(n)
		var pair: Array = _materials[color]
		_rings[n].material_override = pair[0]
		_beams[n].material_override = pair[1]
		var far := Vector2(at.x - pad.x, at.z - pad.z).length() > HIDE_NEAR
		# Beams: the next pad's, the start's and the finish's.
		_beams[n].visible = far and (n == _focus_index() or n == 0 or n == PADS.size() - 1)
		_labels[n].visible = far


## The pad the player should head for now.
func _focus_index() -> int:
	if state == State.ARMED:
		return 1
	return next_index if state == State.RUNNING or state == State.FAILED else 0


func _pad_color(n: int) -> Color:
	if state == State.RUNNING or state == State.FAILED:
		if n < next_index:
			return COLOR_DONE
		if n == next_index:
			return COLOR_NEXT
		return COLOR_FINISH if n == PADS.size() - 1 else COLOR_LATER
	if n == 0:
		return COLOR_START
	if n == 1 and state == State.ARMED:
		return COLOR_NEXT
	return COLOR_FINISH if n == PADS.size() - 1 else COLOR_LATER


func _build_pads() -> void:
	for color: Color in [COLOR_START, COLOR_NEXT, COLOR_DONE, COLOR_LATER, COLOR_FINISH]:
		_materials[color] = [_material(color, 0.9), _material(color, 0.28)]
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = PAD_RADIUS - 0.7
	ring_mesh.outer_radius = PAD_RADIUS
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 6
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.5
	beam_mesh.bottom_radius = 1.2
	beam_mesh.height = BEAM_HEIGHT
	beam_mesh.radial_segments = 12
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	for n in PADS.size():
		var pad := Node3D.new()
		pad.name = "Pad%d" % n
		add_child(pad)
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.position.y = 0.25
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.add_child(ring)
		var beam := MeshInstance3D.new()
		beam.mesh = beam_mesh
		beam.position.y = BEAM_HEIGHT * 0.5
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.add_child(beam)
		var label := Label3D.new()
		label.text = "START" if n == 0 else ("FINISH" if n == PADS.size() - 1 else str(n + 1))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# The same size on screen at any distance, like the HUD's markers.
		label.fixed_size = true
		label.font_size = 64
		label.outline_size = 16
		label.pixel_size = 0.0006
		label.position.y = 6.0
		label.modulate = Color(1.0, 1.0, 1.0, 0.95)
		pad.add_child(label)
		_pads.append(pad)
		_rings.append(ring)
		_beams.append(beam)
		_labels.append(label)


## One unshaded, see-through material: every pad material differs only in
## its color, so they share one small shader.
static func _material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = Color(color, alpha)
	return material
