extends Node
## Headless check of reeling the web while swinging, in the real city: holding
## JUMP shortens the web (down to SwingMode.MIN_ROPE) and pulls the hero toward
## the pivot, holding DOWN lets it out (never past the swing's max_rope, so the
## hero never reaches the street), both together do nothing, the anchor and
## web length survive a floating origin shift mid-reel, the reel state stops
## when the web is let go, and it goes to other players: a copy of the hero,
## moved by PlayerSync from our own encoded states (as another game would be),
## swings from the same anchor and reels when we do. Prints each step and exits
## non-zero if a check fails.
## Run: godot --headless --path . res://tests/swing_reel_test.tscn
## (add `-- --tiles_url=https://nycheroes.party/tiles/` without local tiles)

const AVENUE := Vector3(0.485, 0.0, -0.875)
## Start of a 700 m stretch of 6th Avenue with nothing in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)

var _world: Game
var _hero: Hero
var _swing: SwingMode
var _city: CityStreamer
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _failures: Array[String] = []
var _start_rope := 0.0
var _min_rope := INF
var _max_rope_seen := 0.0
var _reels: Array[int] = []
var _anchor_world := Vector3.ZERO
var _hand_distance := 0.0
var _low_clearance := INF
## Another player's view of our hero (see _mirror).
var _sync := PlayerSync.new()
var _copy: Hero
var _copy_snapshots := SnapshotBuffer.new()
var _copy_reels: Array[int] = []


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_swing = _hero.get_mode(&"Swing") as SwingMode
	_city = _world.get_node("City")
	process_physics_priority = -20  # before the hero, so its input is this tick's
	_copy = PlayerSync.HERO_SCENE.instantiate()
	_copy.remote_id = 2
	_copy.frozen = true
	add_child(_copy)
	_steps = [
		_step("wait for the city to load", 60.0, Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0, func() -> void:
				_check(not _hero.frozen, "the city loaded")),
		_step("go to an open avenue", 0.5, func(_i: HeroInput, t: float) -> void:
			if t < 0.02:
				_teleport(OPEN_AVENUE)),
		_step("web swing from the ground", 0.7, _swing_input, Callable(), func() -> void:
			_check(_hero.mode.name == &"Swing", "swinging")
			_start_rope = _swing.rope_length
			_check(_swing.max_rope >= _swing.rope_length, "max_rope (%.1f) >= rope (%.1f)" % [_swing.max_rope, _start_rope])),
		_step("reel in (hold JUMP)", 0.8, func(i: HeroInput, t: float) -> void:
			_swing_input(i, t)
			i.jump_held = true
			i.vertical = 1.0, Callable(), func() -> void:
				_check(_reels.has(-1), "reel state -1 while reeling in")
				_check(_min_rope < _start_rope - 5.0, "web shortened: %.1f -> %.1f m" % [_start_rope, _min_rope])
				_check(_min_rope >= SwingMode.MIN_ROPE, "never shorter than MIN_ROPE (%.1f)" % _min_rope)
				var state := _sync._encode(_hero)
				_check(state.size() == 14 and state[13] == _swing.reel, "reel state sent to other players")
				_check(_copy_reels.has(-1), "the other player's copy reels in too")
				_check(_copy.mode.name == &"Swing", "the copy swings")
				_check(_copy_anchor_matches(), "the copy swings from the same anchor")),
		_step("origin shift mid-swing", 0.05, func(i: HeroInput, t: float) -> void:
			_swing_input(i, t)
			if t < 0.02:
				_anchor_world = WorldOrigin.to_world(_swing.anchor)
				_hand_distance = _hero.global_position.distance_to(_swing.anchor)
				WorldOrigin.shift(Vector3(256.0, 0.0, -256.0)), Callable(), func() -> void:
				_check(WorldOrigin.to_world(_swing.anchor).distance_to(_anchor_world) < 0.01, "anchor kept its world position")
				_check(absf(_hero.global_position.distance_to(_swing.anchor) - _hand_distance) < 3.0, "hero still on the web")
				_check(_copy_anchor_matches(), "the copy's anchor too")),
		_step("let the web out (hold DOWN)", 4.0, func(i: HeroInput, t: float) -> void:
			_swing_input(i, t)
			i.vertical = -1.0, Callable(), func() -> void:
				_check(_reels.has(1), "reel state +1 while letting out")
				_check(_copy_reels.has(1), "the other player's copy lets out too")
				_check(_max_rope_seen > _min_rope + 5.0, "web lengthened to %.1f m" % _max_rope_seen)
				_check(_max_rope_seen <= _swing.max_rope + 0.001, "never past max_rope (%.1f)" % _swing.max_rope)
				_check(_hero.mode.name == &"Swing", "still swinging (didn't reach the street)")
				_check(_low_clearance > 1.0, "feet stayed clear of the street (lowest %.1f m)" % _low_clearance)),
		_step("hold both: the web holds", 0.5, func(i: HeroInput, t: float) -> void:
			_swing_input(i, t)
			i.jump_held = true
			i.vertical = 0.0, Callable(), func() -> void:
				_check(_reels.size() == 1 and _reels[0] == 0, "no reel with both held: %s" % [_reels])),
		_step("reel all the way in", 3.0, func(i: HeroInput, t: float) -> void:
			_swing_input(i, t)
			i.jump_held = true
			i.vertical = 1.0, Callable(), func() -> void:
				_check(is_equal_approx(_min_rope, SwingMode.MIN_ROPE), "stopped at MIN_ROPE (%.1f m)" % _min_rope)
				_check(_reels.has(0), "reel state back to 0 at the limit")),
		_step("let go of the web", 1.0, func(i: HeroInput, _t: float) -> void: _move(i, AVENUE), Callable(), func() -> void:
			_check(_hero.mode.name != &"Swing", "let go")
			_check(_swing.reel == 0, "reel state cleared on letting go")
			_check(_copy.mode.name != &"Swing" and (_copy.get_mode(&"Swing") as SwingMode).reel == 0,
				"the copy lets go and stops reeling")),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_begin(0)
	elif not _observe():
		return
	_time += delta
	_hero.input.clear()
	var step := _steps[_index]
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)


## Looks at what the last tick's input did, and moves on to the next step when
## this one is over. Returns false once the test is done.
func _observe() -> bool:
	_mirror()
	if not _hero.frozen and _hero.mode.name == &"Swing":
		_min_rope = minf(_min_rope, _swing.rope_length)
		_max_rope_seen = maxf(_max_rope_seen, _swing.rope_length)
		if not _reels.has(_swing.reel):
			_reels.append(_swing.reel)
		var ground := _city.ground_height_at(_hero.world_position())
		if not is_nan(ground):
			_low_clearance = minf(_low_clearance, _hero.world_position().y - ground)
	var step := _steps[_index]
	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return true
	if step.check.is_valid():
		step.check.call()
	print("%-30s %5.1fs  mode %-7s rope %5.1f (max %5.1f) reel %2d  speed %5.1f  at %s" % [
		step.name, _time, _hero.mode.name, _swing.rope_length, _swing.max_rope, _swing.reel,
		_hero.velocity.length(), _hero.world_position().round()])
	if _index + 1 >= _steps.size():
		for failure in _failures:
			printerr("FAIL: " + failure)
		print("swing_reel_test: %s" % ("FAILED" if _failures else "passed"))
		_sync.free()
		get_tree().quit(1 if _failures else 0)
		set_physics_process(false)
		return false
	_begin(_index + 1)
	return true


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	_reels.clear()
	_copy_reels.clear()
	_low_clearance = INF


func _step(step_name: String, seconds: float, apply := Callable(), until := Callable(), check := Callable()) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until, check = check}


## Sends our hero's state to its copy, as PlayerSync does to other games.
func _mirror() -> void:
	if _hero.frozen:
		return
	_copy_snapshots.push(Time.get_ticks_msec(), _sync._encode(_hero))
	_sync._follow(_copy, _copy_snapshots)
	var reel := (_copy.get_mode(&"Swing") as SwingMode).reel
	if _copy.mode.name == &"Swing" and not _copy_reels.has(reel):
		_copy_reels.append(reel)


func _copy_anchor_matches() -> bool:
	var copy_anchor := (_copy.get_mode(&"Swing") as SwingMode).anchor
	return WorldOrigin.to_world(copy_anchor).distance_to(WorldOrigin.to_world(_swing.anchor)) < 0.01


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _swing_input(input: HeroInput, _t: float) -> void:
	_move(input, AVENUE)
	input.aim = AVENUE
	input.web_held = true


## Moves the hero to a world position, standing on the ground there if there is any.
func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _move(input: HeroInput, direction: Vector3) -> void:
	input.move = direction
	input.stick = Vector2(0.0, -1.0)
