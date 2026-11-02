extends Node
## Flight trial regression: swept openings, ordering, origin shifts, retries,
## medal thresholds and timeout. No city data needed.
## godot --headless --path . res://tests/flight_course_test.tscn

var _failures := 0

func _ready() -> void:
	var center := FlightCourse.START
	_check(FlightCourse.crosses_gate(center + Vector3(0, 0, 200), center - Vector3(0, 0, 200), center), "boost cannot tunnel through a ring")
	_check(not FlightCourse.crosses_gate(center + Vector3(23, 0, 1), center + Vector3(23, 0, -1), center), "outside the opening misses")
	_check(not FlightCourse.crosses_gate(center - Vector3(0, 0, 2), center + Vector3(0, 0, 2), center), "backward crossings do not count")
	_check(FlightCourse.medal(4.5) == "GOLD" and FlightCourse.medal(4.51) == "SILVER", "gold boundary")
	_check(FlightCourse.medal(8.0) == "SILVER" and FlightCourse.medal(8.01) == "BRONZE", "silver boundary")
	_check(FlightCourse.medal(17.0) == "BRONZE" and FlightCourse.medal(17.01) == "FINISHER", "bronze boundary")
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	world.set_physics_process(false)
	world.player_input.set_physics_process(false)
	world.hero.set_physics_process(false)
	world.city.set_process(false)
	var course := world.get_node("FlightCourse") as FlightCourse
	course.set_physics_process(false)
	course.start()
	_check(world.hero.mode.name == &"Flight" and course.state == FlightCourse.State.ARMED, "start places hero in flight")
	world.hero.global_position = WorldOrigin.to_local(FlightCourse.ring_position(1))
	course._physics_process(0.1)
	_check(course.next_ring == 1, "crossing future rings only scores current gate")
	course.start()
	WorldOrigin.shift(Vector3(-2000, 0, 0))
	course._physics_process(0.1)
	_check(course.next_ring == 0 and course.state == FlightCourse.State.ARMED, "origin shift cannot score or interrupt")
	for i in FlightCourse.OFFSETS.size():
		var point := FlightCourse.ring_position(i)
		world.hero.global_position = WorldOrigin.to_local(point + Vector3(0, 0, 1))
		course._physics_process(0.1)
		world.hero.global_position = WorldOrigin.to_local(point - Vector3(0, 0, 1))
		course._physics_process(0.1)
	_check(course.state == FlightCourse.State.FINISHED and course.next_ring == 6 and course.best > 0.0, "all six in order finish and save a best")
	course.start()
	_check(course.next_ring == 0 and course.elapsed == 0.0, "retry resets progress and timer")
	course.state = FlightCourse.State.RUNNING
	course.elapsed = 59.99
	course._physics_process(0.02)
	_check(course.state == FlightCourse.State.FINISHED, "one minute limit ends run")
	course.leave()
	_check(course.state == FlightCourse.State.IDLE, "leave returns to free play")
	print("Flight course: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)

func _check(ok: bool, message: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_failures += 1
