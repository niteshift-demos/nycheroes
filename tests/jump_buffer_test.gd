extends Node
## Headless check of the landing jump buffer (OnFootMode.jump_buffer_time) on
## a flat stretch of avenue in the real city: a jump pressed just before
## landing jumps again on touching down; one pressed well before landing is
## dropped; a buffered press still held on landing charges a super jump; and
## a plain tap on the ground is still a normal jump. Exits non-zero on failure.
## Run: godot --headless --path . res://tests/jump_buffer_test.tscn
## (without data/tiles, add `-- --tiles_url=https://nycheroes.party/tiles/`)

## Start of a 700 m stretch of avenue with no buildings in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
## How long before the expected landing the "just before" press comes (s):
## inside the buffer.
const EARLY_INSIDE := 0.08
## And the "too early" press: well outside the buffer.
const EARLY_OUTSIDE := 0.35

var _world: Game
var _hero: Hero
var _on_foot: OnFootMode
var _city: CityStreamer
var _phase := &"load"
var _time := 0.0
var _air_time := 0.0  # measured air time of a tap jump on flat ground
var _jump_time := 0.0  # time the current jump left the ground
var _landed_at := -1.0
var _rejumped_at := -1.0
var _max_height := 0.0
var _ground_y := 0.0
var _was_on_floor := true
var _failures: Array[String] = []


func _ready() -> void:
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	_world = world
	world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = world.get_node("Hero")
	_on_foot = _hero.get_mode(&"OnFoot")
	_city = world.get_node("City")
	# Run before the hero each tick so the scripted input is used right away.
	process_physics_priority = -20


func _physics_process(delta: float) -> void:
	_time += delta
	_hero.input.clear()
	var on_floor := _hero.is_on_floor()
	var height := _hero.world_position().y - _ground_y
	_max_height = maxf(_max_height, height)
	match _phase:
		&"load":
			if not _hero.frozen and _city.pending_count() == 0:
				_teleport(OPEN_AVENUE)
				_next(&"settle")
			elif _time > 60.0:
				_fail("the city didn't load")
				_finish()
		&"settle":
			if _time > 1.0:
				_ground_y = _hero.world_position().y
				_next(&"measure")
		&"measure":  # a plain tap on the ground: a normal jump, timed
			_hero.input.jump_held = _time < 0.05
			if not on_floor and _was_on_floor:
				_jump_time = _time
			if on_floor and not _was_on_floor:
				_air_time = _time - _jump_time
				print("tap jump: %.2f s in the air, %.2f m high" % [_air_time, _max_height])
				_check(_max_height > 1.5 and _max_height < 4.0, "a tap is a normal jump (height %.2f)" % _max_height)
				_check(_air_time > 0.5 and _air_time < 1.2, "normal jump air time (%.2f s)" % _air_time)
				_next(&"inside_jump")
		&"inside_jump", &"outside_jump", &"hold_jump":
			# Tap jump, then press again shortly before the expected landing.
			var early: float = EARLY_OUTSIDE if _phase == &"outside_jump" else EARLY_INSIDE
			if not on_floor and _was_on_floor and _landed_at < 0.0:
				_jump_time = _time
			var press_at := _jump_time + _air_time - early if _jump_time > 0.0 else INF
			if _time < 0.05:
				_hero.input.jump_held = true
			elif _time >= press_at:
				_hero.input.jump_held = _phase == &"hold_jump" or _time < press_at + 0.05
			if on_floor and not _was_on_floor and _time > 0.2:
				_landed_at = _time
			if _landed_at >= 0.0 and not on_floor and _rejumped_at < 0.0:
				_rejumped_at = _time
			if _phase == &"hold_jump" and _landed_at >= 0.0 and _time > _landed_at + 1.3:
				_check(_on_foot.charging and _on_foot.charge > 0.9,
					"a buffered press held through landing charges a super jump (charge %.2f)" % _on_foot.charge)
				_check(_rejumped_at < 0.0, "no jump while still charging")
				_next(&"release")
			elif _phase != &"hold_jump" and _landed_at >= 0.0 and (_rejumped_at >= 0.0 or _time > _landed_at + 0.6):
				var delay := _rejumped_at - _landed_at if _rejumped_at >= 0.0 else INF
				print("%s: pressed %.2f s before landing, jumped again %s after landing" % [
					_phase, early, "%.3f s" % delay if delay < INF else "never"])
				if _phase == &"inside_jump":
					_check(delay <= 0.05, "a press %.2f s before landing jumps on touching down" % early)
					_next(&"inside_air")
				else:
					_check(delay == INF, "a press %.2f s before landing is dropped" % early)
					_next(&"hold_jump")
		&"inside_air":  # the buffered jump: a normal one
			if on_floor and _time > 0.2:
				print("buffered jump: %.2f m high" % _max_height)
				_check(_max_height > 1.5 and _max_height < 4.0, "the buffered jump is a normal jump (%.2f m)" % _max_height)
				_next(&"rest")
		&"rest":
			if _time > 0.6:
				_next(&"outside_jump")
		&"release":  # let go: the charged super jump
			if on_floor and _time > 0.5:
				print("buffered super jump: %.1f m high" % _max_height)
				_check(_max_height > 20.0, "releasing the buffered charge super jumps (%.1f m)" % _max_height)
				_finish()
			elif _time > 15.0:
				_fail("the super jump never came down")
				_finish()
	_was_on_floor = on_floor


func _next(phase: StringName) -> void:
	_phase = phase
	_time = 0.0
	_max_height = 0.0
	_landed_at = -1.0
	_rejumped_at = -1.0
	_jump_time = 0.0


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _fail(what: String) -> void:
	_check(false, what)


func _finish() -> void:
	print("jump buffer test: %s" % ("OK" if _failures.is_empty() else "%d FAILED" % _failures.size()))
	get_tree().quit(0 if _failures.is_empty() else 1)


## Moves the hero to a world position, standing on the ground there.
func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO
