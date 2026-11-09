extends Node
## Headless check of the time trial (TimeTrial), in the real city at Times
## Square, with the hero driven by HeroInput as a player would (TrialPilot):
## - The course's gates sit on the street once it has loaded, and the start
##   gate waits (no clock) until the hero runs through it.
## - A gate counts only near its middle and low over the street: 8 m to the
##   side or 40 m up (flying over the rooftops) doesn't clear it.
## - A run: through the start, every checkpoint in order and the finish, with
##   super speed on the straights; the time is plausible for the distance and
##   the hero's top speed, the splits go up, and it's the best time.
## - Passing a later gate before the next doesn't count.
## - Retry: the clock resets and the hero stands before the start gate facing
##   it, able to move; the time limit fails a run that takes too long.
## - The gates and the checks survive a floating-origin shift.
## Run: godot --headless --path . res://tests/time_trial_test.tscn -- --solo=1 [--tiles=DIR | --tiles_url=URL]
## (without either, the editor reads data/tiles; a sandbox without tiles can
## use --tiles_url=https://nycheroes.party/tiles/).

const MAX_LOAD_WAIT := 90.0
## Longest a scripted run may take (s of game time).
const MAX_RUN := 60.0

var _world: Game
var _city: CityStreamer
var _hero: Hero
var _trial: TimeTrial
var _pilot: TrialPilot
var _failed := 0


func _ready() -> void:
	_run()


func _run() -> void:
	Settings.set_value("player_name", "Tester")
	Settings.set_value(TimeTrial.BEST_SETTING, 0.0)
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	_city = _world.get_node("City")
	_hero = _world.get_node("Hero")
	_trial = _world.get_node_or_null("TimeTrial")
	_check(_trial != null, "the game has a time trial")
	if _trial == null:
		_finish()
		return
	_pilot = TrialPilot.new(_hero, _world.get_node("HeroCamera"))
	if not await _wait_for_city():
		_check(false, "the city loaded at Times Square")
		_finish()
		return
	await _ticks(10)
	_check_gates()
	await _check_run()
	await _check_order()
	await _check_retry_and_limit()
	_check_origin_shift()
	_finish()


func _check_gates() -> void:
	var worst := 0.0
	for n in TimeTrial.COURSE.size():
		var ground := _city.ground_height_at(_trial.gate_position(n), 1.0)
		worst = maxf(worst, absf(ground - _trial.gate_position(n).y) if not is_nan(ground) else INF)
	_check(worst < 0.5, "every gate stands on the street (worst %.2f m off)" % worst)
	_check(_trial.state == TimeTrial.State.READY and _trial.elapsed == 0.0, "the trial waits at its start gate")
	var gate := _trial.gate_position(1)
	_check(_trial.is_in_gate(1, gate + Vector3(0.0, 1.0, 0.0)) and _trial.is_in_gate(1, gate + Vector3(5.0, 15.0, 0.0)),
		"a gate counts near its middle, also jumping through it")
	_check(not _trial.is_in_gate(1, gate + Vector3(8.0, 1.0, 0.0)) and not _trial.is_in_gate(1, gate + Vector3(0.0, 40.0, 0.0)),
		"a gate doesn't count 8 m to its side or 40 m over it")


## Through the start, every checkpoint and the finish.
func _check_run() -> void:
	var cleared: Array[int] = []
	_trial.gate_cleared.connect(func(index: int, _s: float) -> void: cleared.append(index))
	await _drive_through(0)
	_check(_trial.state == TimeTrial.State.RUNNING, "running through the start gate starts the clock")
	for n in range(1, _trial.gate_count() + 1):
		await _drive_through(n)
	var length := 0.0
	for n in range(1, TimeTrial.COURSE.size()):
		length += Vector2(TimeTrial.COURSE[n].x - TimeTrial.COURSE[n - 1].x, TimeTrial.COURSE[n].z - TimeTrial.COURSE[n - 1].z).length()
	var fastest := (length - 2.0 * TimeTrial.GATE_RADIUS) / 60.0  # (super speed's top speed)
	_check(_trial.state == TimeTrial.State.FINISHED, "the run finishes at the last gate (%s)" % TimeTrial.State.keys()[_trial.state])
	_check(cleared == [0, 1, 2, 3, 4], "the gates were cleared in order (%s)" % [cleared])
	_check(_trial.elapsed > fastest and _trial.elapsed < TimeTrial.TIME_LIMIT,
		"the time is plausible: %s for %.0f m (no faster than %.1f s)" % [TimeTrial.format_time(_trial.elapsed), length, fastest])
	var rising := _trial.splits.size() == _trial.gate_count()
	for n in range(1, _trial.splits.size()):
		rising = rising and _trial.splits[n] > _trial.splits[n - 1]
	_check(rising, "the splits go up (%s)" % [_trial.splits])
	_check(_trial.new_best and is_equal_approx(float(Settings.get_value(TimeTrial.BEST_SETTING)), _trial.elapsed),
		"a first finish is the best time, and remembered")
	var finished_at := _trial.elapsed
	await _ticks(30)
	_check(_trial.elapsed == finished_at, "the clock stops at the finish")


## Out of order: a later gate doesn't count before the next.
func _check_order() -> void:
	_trial.retry()
	await _wait_until_moving()
	await _drive_through(0)
	# Straight past checkpoint 1 to checkpoint 2 is fine (it's on the way);
	# instead go to checkpoint 2's spot by way of the side street, skipping 1.
	var skip := _trial.gate_position(2)
	_check(_trial.next_gate == 1, "after the start, checkpoint 1 is next")
	_hero.global_position = WorldOrigin.to_local(skip + Vector3(0.0, 0.5, 0.0))  # (test only: set down in gate 2)
	await _ticks(4)
	_check(_trial.next_gate == 1 and _trial.splits.is_empty(), "standing in checkpoint 2 first doesn't count")


func _check_retry_and_limit() -> void:
	_trial.retry()
	_check(_trial.state == TimeTrial.State.READY and _trial.elapsed == 0.0 and _trial.splits.is_empty(),
		"retry resets the clock")
	await _wait_until_moving()
	var start := _trial.gate_position(0)
	var at := _hero.world_position()
	var back := Vector2(start.x - at.x, start.z - at.z)
	_check(absf(back.length() - TimeTrial.RETRY_BACK) < 2.0 and absf(angle_difference(_hero.facing, atan2(-back.x, -back.y))) < 0.05,
		"retry stands the hero %.1f m before the start gate, facing it" % back.length())
	await _drive_through(0)
	_check(_trial.state == TimeTrial.State.RUNNING, "and running through it starts again")
	_trial.elapsed = TimeTrial.TIME_LIMIT - 0.05  # (test only: skip ahead to the limit)
	await _ticks(6)
	_check(_trial.state == TimeTrial.State.FAILED and _trial.elapsed == TimeTrial.TIME_LIMIT,
		"the run fails when the time limit runs out")


func _check_origin_shift() -> void:
	var before := _trial.gate_position(1)
	WorldOrigin.shift(Vector3(500.0, 0.0, -500.0))
	var gate := _trial.get_node("Gate1") as Node3D
	_check(WorldOrigin.to_world(gate.global_position).distance_to(before) < 0.01,
		"the gates stay put in the city through an origin shift")
	_check(_trial.is_in_gate(1, before + Vector3.UP), "and still count where they stand")


## Drives the hero through a gate (and a little past it).
func _drive_through(index: int) -> void:
	var target := _trial.gate_position(index)
	var waited := 0.0
	while waited < MAX_RUN:
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		waited += delta
		var through := _trial.state == TimeTrial.State.RUNNING and (index == 0 or _trial.next_gate > index) \
			or index == _trial.gate_count() and _trial.state == TimeTrial.State.FINISHED
		if through:
			_hero.input.clear()
			return
		_pilot.steer(target, delta)
	_check(false, "the hero reached gate %d in time" % index)


func _wait_until_moving() -> void:
	var waited := 0
	while _hero.frozen and waited < 600:
		await get_tree().physics_frame
		waited += 1
	await _ticks(20)


func _wait_for_city() -> bool:
	var started := Time.get_ticks_msec()
	while _city.loaded_counts[0] == 0 or _city.pending_count() > 0 or _hero.frozen:
		await get_tree().create_timer(0.5).timeout
		if Time.get_ticks_msec() - started > MAX_LOAD_WAIT * 1000.0:
			return false
	return true


func _ticks(count: int) -> void:
	for n in count:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failed += 1


func _finish() -> void:
	print("time_trial_test: %s" % ("all passed" if _failed == 0 else "%d failed" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)
