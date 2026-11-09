class_name FlightCoursePilot
extends RefCounted
## A simple flier for the flight ring course, for tests and capture: where to
## look and whether to push forward and boost, the way a player would steer
## (it only ever sets ordinary controls; see flight_course_test and
## flight_course_capture). It flies at each next ring's middle, boosting on
## straights and letting go to slow down before sharp turns. With
## `miss_ring` set it flies past that ring on purpose the first time (MISS_BY
## to one side of its middle), then turns back round to its approach side
## and flies through it.

## How far beside the ring's middle the deliberate miss aims (m): outside
## FlightCourse.RING_RADIUS, inside MISS_RADIUS.
const MISS_BY := 26.0
## After the miss, come back round to this far before the ring (m).
const COME_BACK := 70.0
## Boost when the ring is further than this (m) and nearly straight ahead.
const BOOST_DISTANCE := 90.0
const BOOST_ANGLE := deg_to_rad(22.0)
## Let go (slow down) when flying faster than this (m/s) more than BRAKE_ANGLE
## off the way to go.
const BRAKE_SPEED := 48.0
const BRAKE_ANGLE := deg_to_rad(35.0)

var miss_ring := -1
var missed := false

var _recovering := false


## Called when the course reports a miss.
func on_missed(index: int) -> void:
	if index == miss_ring:
		missed = true
		_recovering = true


## {aim: unit Vector3 to look along, forward: bool, sprint: bool, target: Vector3}
func plan(hero: Hero, course: FlightCourse) -> Dictionary:
	var index := course.next_ring
	var center := FlightCourse.RINGS[index]
	var normal := FlightCourse.ring_normal(index)
	var side := normal.cross(Vector3.UP).normalized()
	var target := center
	var at := hero.world_position()
	if index == miss_ring and not missed:
		target = center + side * MISS_BY
	elif _recovering:
		target = center - normal * COME_BACK
		if at.distance_to(target) < 45.0:
			_recovering = false
			target = center
	var to := target - at
	var desired := to.normalized()
	var velocity := hero.velocity
	var speed := velocity.length()
	# Steer to cancel the sideways drift too, not just point at the target.
	var drift := velocity - desired * velocity.dot(desired)
	var aim := (desired * maxf(speed, 30.0) - drift).normalized()
	var off := velocity.angle_to(desired) if speed > 5.0 else 0.0
	var forward := not (speed > BRAKE_SPEED and off > BRAKE_ANGLE)
	var sprint := forward and to.length() > BOOST_DISTANCE and off < BOOST_ANGLE
	return {"aim": aim, "forward": forward, "sprint": sprint, "target": target}
