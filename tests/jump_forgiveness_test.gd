extends Node
## Checks forgiving jumps (OnFootMode's coyote time and jump buffering) in the
## real city: the hero runs up the TKTS steps in Times Square and off their
## 4.9 m top, with the jump button pressed the way a player late or early
## would, through HeroInput like PlayerInput does. One unbroken run, no
## teleports, so it also serves as the scripted gameplay for the feature's
## video (captions on screen say what each press was):
##   1. Jump 0.08 s after running off the top: a coyote jump. Jump 0.08 s
##      before touching down: jumps again on landing (buffered).
##   2. The edges: jump 0.25 s after running off (past coyote time) does
##      nothing, nor does a press 0.3 s before touchdown (past the buffer).
##   3. A press just after a jump is no second jump; a press just before
##      landing held on charges a super jump that launches on release.
## Exits non-zero if any check fails.
## Run: godot --headless --path . res://tests/jump_forgiveness_test.tscn
## (add `-- --tiles=DIR` or `-- --tiles_url=URL` where data/tiles is missing;
## see docs/ROADMAP.md for recording it with Movie Maker).

## Manhattan's avenues run about 29 degrees east of north; so do the steps.
const AVENUE := Vector3(0.485, 0.0, -0.875)
## In front of the TKTS steps in Father Duffy Square, a little west of their
## middle (world meters, x and z; the height is the ground's). Running up them
## along AVENUE leaves their top about 22 m on.
const START := Vector2(40.7, -116.5)
## Off the top, the hero bears this way, clear of the building north-east of
## the steps.
const AWAY := Vector3(-0.6, 0.0, -0.8)
## Back around the steps' west side after the first run, to START again.
const RETURN_PATH: Array[Vector2] = [Vector2(40.0, -150.0), Vector2(33.0, -135.0), Vector2(33.0, -119.0), START]
const TICK := 1.0 / 60.0
## The top of the steps is 4.9 m up: over this much above the square is on top.
const TOP_HEIGHT := 4.0

var _world: Game
var _hero: Hero
var _on_foot: OnFootMode
var _city: CityStreamer
var _caption: Label
var _failures: Array[String] = []

var _phase := &"load"
var _tick := 0  # ticks in this phase
var _base := 0.0  # the square's height (scene y)
var _lap := 0
var _laps: Array[Dictionary] = [
	{name = "late jump off the top", coyote_ticks = 5, coyote = true, lead = 0.08, bounce = true},
	{name = "too late, too early", coyote_ticks = 15, coyote = false, lead = 0.30, bounce = false},
]
var _left_tick := -1
var _press_until := -1
var _pressed_at := -1
var _land_press_tick := -1
var _landed_tick := -1
var _vy_before := 0.0
var _path_index := 0
var _jump := false
var _hold := false
var _launch_speed := 0.0
var _peak := 0.0
var _total_ticks := 0


func _ready() -> void:
	var world: Game = load("res://scenes/world.tscn").instantiate()
	world.ready.connect(func() -> void:
		# Like ?spawn=: the hero starts at the bottom of the steps, facing them.
		world.place_hero(Vector3(START.x, 40.0, START.y), atan2(-AVENUE.x, -AVENUE.z), true))
	add_child(world)
	_world = world
	world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	if DisplayServer.get_name() == "headless":
		# Nobody in the way: the checks are about the hero alone.
		world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = world.get_node("Hero")
	_on_foot = _hero.get_mode(&"OnFoot")
	_city = world.get_node("City")
	process_physics_priority = -20  # before the hero, like PlayerInput
	_add_caption()


func _physics_process(_delta: float) -> void:
	_tick += 1
	_total_ticks += 1
	_hero.input.clear()
	_jump = false
	call("_" + _phase)
	_hero.input.jump_held = _jump or _hold or _total_ticks <= _press_until
	if _total_ticks > 60 * 240:
		_fail("timed out in phase %s" % _phase)
		_finish()


func _load() -> void:
	if _hero.frozen or _city.pending_count() > 0:
		_say("Loading Times Square...")
		return
	if _hero.is_on_floor():
		_base = _hero.global_position.y
		_go(&"wait")


## A moment standing at the foot of the steps before each run.
func _wait() -> void:
	var lap: Dictionary = _laps[_lap]
	_say("Run %d: %s" % [_lap + 1, lap.name])
	if _tick >= 45:
		_left_tick = -1
		_pressed_at = -1
		_land_press_tick = -1
		_landed_tick = -1
		_go(&"climb")


## Up the steps and off the top's back edge.
func _climb() -> void:
	_steer(AVENUE)
	if _tick % 20 == 0 and OS.has_environment("JUMP_TEST_TRACE"):
		print("climb ", _hero.world_position(), " v ", _hero.velocity, " floor ", _hero.is_on_floor(), " wall ", _hero.is_on_wall())
	if _height() > TOP_HEIGHT and not _hero.is_on_floor():
		_left_tick = 0
		_go(&"off_edge")
	elif _tick > 60 * 6:
		_fail("run %d: never got off the top of the steps (height %.1f m)" % [_lap + 1, _height()])
		_finish()


func _off_edge() -> void:
	var lap: Dictionary = _laps[_lap]
	_steer(AVENUE)
	if _tick == lap.coyote_ticks:
		_vy_before = _hero.velocity.y
		_press(5)
		_pressed_at = _tick
		_say("Run %d: jump pressed %.2f s after running off the edge" % [_lap + 1, _tick * TICK])
	elif _pressed_at >= 0 and _tick == _pressed_at + 1:
		var jumped := _hero.velocity.y > _on_foot.jump_speed - 1.0
		var what := "coyote jump" if jumped else "no jump: too late"
		print("run %d: pressed %.3f s after leaving the edge -> %s (vy %.1f)" % [
			_lap + 1, _pressed_at * TICK, what, _hero.velocity.y])
		_say("Run %d: jump %.2f s after leaving the edge -> %s" % [_lap + 1, _pressed_at * TICK, what.to_upper()])
		if jumped != lap.coyote:
			_fail("run %d: coyote jump %s, expected %s" % [_lap + 1, jumped, lap.coyote])
		_go(&"descend")


## Falling to the square: press jump `lead` seconds before touching down.
func _descend() -> void:
	var lap: Dictionary = _laps[_lap]
	if OS.has_environment("JUMP_TEST_TRACE"):
		print("fall ", _hero.world_position(), " v ", _hero.velocity, " wall ", _hero.is_on_wall())
	_steer(AWAY)
	if _land_press_tick < 0 and _hero.velocity.y < 0.0 and _time_to_land() <= lap.lead:
		_land_press_tick = _total_ticks
		_press(3)
	if _hero.is_on_floor():
		_landed_tick = _total_ticks
		var lead := (_landed_tick - _land_press_tick) * TICK if _land_press_tick >= 0 else NAN
		print("run %d: landed on the square (%.1f m); jump pressed %.3f s before touchdown" % [
			_lap + 1, _height(), lead])
		if absf(_height()) > 0.5:
			_fail("run %d: landed %.1f m off the square's height" % [_lap + 1, _height()])
		_go(&"landed")
	elif _tick > 60 * 4:
		_fail("run %d: never landed" % [_lap + 1])
		_finish()


## Watch the touchdown: a buffered press jumps at once.
func _landed() -> void:
	var lap: Dictionary = _laps[_lap]
	if lap.bounce:
		_steer(AWAY)
	if _tick == 4:
		var bounced := not _hero.is_on_floor() and _hero.velocity.y > 5.0
		var lead := (_landed_tick - _land_press_tick) * TICK
		var what := "jumped on landing (buffered)" if bounced else "no jump: too early"
		print("run %d: pressed %.3f s before touchdown -> %s" % [_lap + 1, lead, what])
		_say("Run %d: jump %.2f s before touchdown -> %s" % [_lap + 1, lead, what.to_upper()])
		if bounced != lap.bounce:
			_fail("run %d: buffered jump %s, expected %s" % [_lap + 1, bounced, lap.bounce])
	if _tick >= 75 and _hero.is_on_floor():
		_lap += 1
		if _lap < _laps.size():
			_path_index = 0
			_go(&"go_back")
		else:
			_go(&"hop")


## Run back around the steps to the start.
func _go_back() -> void:
	_say("Back to the steps")
	var target: Vector2 = RETURN_PATH[_path_index]
	var here := _hero.world_position()
	var to := Vector3(target.x - here.x, 0.0, target.y - here.z)
	if to.length() < 1.2:
		_path_index += 1
		if _path_index >= RETURN_PATH.size():
			_go(&"face_steps")
		return
	_steer(to.normalized())
	if _tick % 30 == 0 and OS.has_environment("JUMP_TEST_TRACE"):
		print("back ", here, " to ", target, " wall ", _hero.is_on_wall())
	if _tick > 60 * 20:
		_fail("couldn't get back to the steps")
		_finish()


func _face_steps() -> void:
	# A nudge up the avenue turns the hero to the steps; then stand still.
	if _tick < 4:
		_steer(AVENUE * 0.2)
	if _tick > 30:
		_go(&"wait")


## Run 3: a tap jump, then a second press just after takeoff.
func _hop() -> void:
	_say("Run 3: jump, then jump again in the air")
	if _tick == 30:
		_press(3)
	if _tick > 30 and not _hero.is_on_floor():
		_go(&"double")
	elif _tick > 90:
		_fail("run 3: the tap jump didn't leave the ground")
		_finish()


func _double() -> void:
	if _tick == 4:
		_vy_before = _hero.velocity.y
		_press(4)
	elif _tick == 5:
		var jumped := _hero.velocity.y > _vy_before + 1.0
		print("run 3: second press %.3f s after takeoff -> %s (vy %.1f -> %.1f)" % [
			4 * TICK, "double jump" if jumped else "no double jump", _vy_before, _hero.velocity.y])
		_say("Run 3: 2nd press in the air -> %s" % ("DOUBLE JUMP" if jumped else "NO DOUBLE JUMP"))
		if jumped:
			_fail("run 3: a press just after a jump jumped again")
	elif _tick > 10 and _hero.velocity.y < 0.0 and _time_to_land() <= 0.1:
		_land_press_tick = _total_ticks
		_hold = true
		_go(&"charge")


## Pressed just before landing and held: a super jump charges on touchdown.
func _charge() -> void:
	if _hero.is_on_floor() and _landed_tick < _land_press_tick:
		_landed_tick = _total_ticks
		print("run 3: pressed %.3f s before touchdown and held" % ((_landed_tick - _land_press_tick) * TICK))
	if _landed_tick >= _land_press_tick:
		var held := (_total_ticks - _landed_tick) * TICK
		_say("Run 3: pressed before touchdown, held: charging %d%%" % roundi(_on_foot.charge * 100.0))
		if held >= 1.4:
			if not (_on_foot.charging and _on_foot.charge >= 1.0 and _hero.is_on_floor()):
				_fail("run 3: holding a buffered press didn't charge a super jump (charge %.2f)" % _on_foot.charge)
			_hold = false
			_go(&"launch")
	elif _tick > 60 * 2:
		_fail("run 3: never landed")
		_finish()


func _launch() -> void:
	if _tick == 2:
		_launch_speed = _hero.velocity.y
		print("run 3: released -> super jump at %.1f m/s" % _launch_speed)
		_say("Run 3: released -> SUPER JUMP (%d m/s)" % roundi(_launch_speed))
		if _launch_speed < _on_foot.super_jump_min_speed:
			_fail("run 3: no super jump on release (vy %.1f)" % _launch_speed)
	_peak = maxf(_peak, _height())
	if _tick > 30 and _hero.is_on_floor() or _tick > 60 * 9:
		print("run 3: super jump peaked %.0f m up" % _peak)
		_say("Run 3: super jump peaked %d m up" % roundi(_peak))
		_go(&"done")


func _done() -> void:
	if _tick > 60:
		_finish()


func _finish() -> void:
	set_physics_process(false)
	if _failures.is_empty():
		print("PASS: forgiving jumps")
	else:
		printerr("FAILED: %d check(s), see above" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _go(phase: StringName) -> void:
	_phase = phase
	_tick = 0


func _press(ticks: int) -> void:
	_jump = true
	_press_until = _total_ticks + ticks - 1


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("FAIL: " + message)


## Stick toward a world direction, the way PlayerInput turns the stick with the
## camera's yaw into `move`.
func _steer(direction: Vector3) -> void:
	var yaw: float = _world.hero_camera.yaw
	var stick3 := Basis(Vector3.UP, -yaw) * direction
	_hero.input.stick = Vector2(stick3.x, stick3.z)
	_hero.input.move = direction
	_hero.input.aim = _world.hero_camera.aim_direction()


## Height of the hero's feet above the square.
func _height() -> float:
	return _hero.global_position.y - _base


## Seconds until the hero's feet reach the ground below, falling as it is.
func _time_to_land() -> float:
	var ground := _city.ground_height_at(_hero.world_position(), 0.0)
	if is_nan(ground):
		return INF
	var drop := _hero.global_position.y - ground
	var down := -_hero.velocity.y
	return (-down + sqrt(down * down + 2.0 * Hero.GRAVITY * maxf(drop, 0.0))) / Hero.GRAVITY


func _say(text: String) -> void:
	if _caption.text != text:
		_caption.text = text


func _add_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_caption = Label.new()
	_caption.add_theme_font_size_override(&"font_size", 30)
	_caption.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override(&"outline_size", 8)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.position.y = 24.0
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_caption)
