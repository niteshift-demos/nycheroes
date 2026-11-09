extends Node
## Plays the rooftop run (RooftopCourse) with ordinary input actions, the way
## a player with a gamepad would: the look stick (look_left/right/up/down)
## turns the camera toward the next pad, jump is held for as long as the
## charge needs, the move stick points at the pad when jump is let go and
## steers in the air. Everything goes through PlayerInput and the hero's
## usual HeroInput; nothing about the hero, the course or the clock is set
## directly. Used by tests/rooftop_course_test.gd and the video capture
## (tests/rooftop_course_capture.gd).
##
## `legs` lists the jumps in order: {"to": pad index, "charge": optional
## fixed charge (0..1) instead of the worked-out one, e.g. too little to
## show a failed jump}. A leg ends when the hero touches down; a failed one
## (the course puts the hero back) is not retried by itself: list it again.

signal leg_done(index: int)
signal finished

## Gravity, jump speeds and charge timing, as OnFootMode has them.
const GRAVITY := Hero.GRAVITY
const AIR_ACCELERATION := 18.0
const LOOK_RATE := 2.5  # rad/s of a full look stick (ThirdPersonCamera.stick_sensitivity)

var hero: Hero
var camera: ThirdPersonCamera
var course: RooftopCourse
var legs: Array[Dictionary] = []
## Seconds to stand still on a pad before each jump (looking at the next).
var settle_time := 0.45
## Camera pitch to hold (radians; negative looks down).
var pitch := -0.22

var leg := 0
var _phase := &"aim"
var _time := 0.0
var _hold_ticks := 0
var _held := 0
var _charge := 0.0
var _left_ground := false


func _ready() -> void:
	# Before PlayerInput (-10) reads the actions this tick.
	process_physics_priority = -20


func _exit_tree() -> void:
	_release_all()


func is_done() -> bool:
	return leg >= legs.size()


func _physics_process(delta: float) -> void:
	if is_done() or hero.frozen:
		_release_all()
		return
	var target := course.pad_world_position(int(legs[leg]["to"]))
	var at := hero.world_position()
	_look_toward(target, delta)
	match _phase:
		&"aim":
			_set_move(Vector3.ZERO)
			_time = _time + delta if hero.is_on_floor() and course.state != RooftopCourse.State.FAILED else 0.0
			if _time >= settle_time and absf(_yaw_error(target)) < 0.06:
				_charge = float(legs[leg]["charge"]) if legs[leg].has("charge") else _charge_for(at, target)
				var hold := OnFootMode.new()
				_hold_ticks = ceili((hold.tap_time + _charge * hold.charge_time) * Engine.physics_ticks_per_second) + 1
				hold.free()
				_held = 0
				_phase = &"charge"
		&"charge":
			_held += 1
			if _held <= _hold_ticks:
				Input.action_press(&"jump")
				_set_move(Vector3.ZERO)
			else:
				Input.action_release(&"jump")
				_set_move((target - at) * Vector3(1, 0, 1))
				_left_ground = false
				_phase = &"air"
		&"air":
			if not hero.is_on_floor():
				_left_ground = true
				_steer(at, target)
			elif _left_ground:
				_set_move(Vector3.ZERO)
				_phase = &"aim"
				_time = 0.0
				leg += 1
				leg_done.emit(leg - 1)
				if is_done():
					_release_all()
					finished.emit()


## The least charge (in steps of 0.02) whose jump clears the target's roof
## by a few meters and carries far enough to reach it, with some to spare
## for steering.
func _charge_for(from: Vector3, to: Vector3) -> float:
	var on_foot := hero.get_mode(&"OnFoot") as OnFootMode
	var rise := to.y - from.y
	var distance := Vector2(to.x - from.x, to.z - from.z).length()
	var charge := 0.0
	while charge < 1.0:
		var up := lerpf(on_foot.super_jump_min_speed, on_foot.super_jump_max_speed, charge)
		var ahead := maxf(on_foot.super_jump_leap * charge, on_foot.run_speed)
		var apex := up * up / (2.0 * GRAVITY)
		if apex > rise + 6.0:
			var t := (up + sqrt(up * up - 2.0 * GRAVITY * rise)) / GRAVITY
			if ahead * t > distance * 1.15:
				return charge
		charge += 0.02
	return 1.0


## In the air: push the stick toward the speed that comes down on the pad.
func _steer(at: Vector3, target: Vector3) -> void:
	var up := hero.velocity.y
	var drop := at.y - target.y
	var under := up * up + 2.0 * GRAVITY * drop
	var t := (up + sqrt(under)) / GRAVITY if under > 0.0 else up / GRAVITY
	var flat := Vector3(target.x - at.x, 0.0, target.z - at.z)
	var wanted := flat / maxf(t, 0.25)
	var now := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	_set_move((wanted - now) / (AIR_ACCELERATION * 0.3))


## The move stick, as a world direction (its length up to 1).
func _set_move(world: Vector3) -> void:
	var stick := Basis(Vector3.UP, -camera.yaw) * world.limit_length(1.0)
	_axis(&"move_left", &"move_right", stick.x)
	_axis(&"move_forward", &"move_back", stick.z)


func _look_toward(target: Vector3, delta: float) -> void:
	var yaw_error := _yaw_error(target)
	var pitch_error := pitch - camera.pitch
	var rate := LOOK_RATE * delta
	_axis(&"look_right", &"look_left", clampf(yaw_error / rate * 0.25, -1.0, 1.0))
	_axis(&"look_down", &"look_up", clampf(pitch_error / rate * 0.25, -1.0, 1.0))


func _yaw_error(target: Vector3) -> float:
	var flat := target - hero.world_position()
	if Vector2(flat.x, flat.z).length() < 0.5:
		return 0.0
	return angle_difference(camera.yaw, atan2(-flat.x, -flat.z))


## Presses one of a pair of actions as far as `value` goes (negative: the first).
func _axis(negative: StringName, positive: StringName, value: float) -> void:
	if value < -0.01:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	elif value > 0.01:
		Input.action_press(positive, value)
		Input.action_release(negative)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _release_all() -> void:
	for action: StringName in [&"jump", &"move_left", &"move_right", &"move_forward", &"move_back",
			&"look_left", &"look_right", &"look_up", &"look_down"]:
		Input.action_release(action)
