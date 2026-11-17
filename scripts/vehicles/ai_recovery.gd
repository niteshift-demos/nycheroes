class_name AiRecovery
extends RefCounted
## Detects lack of world-space progress, including cars spinning their wheels.
## A whole reverse manoeuvre finishes before another attempt can start. Only
## real travel clears failed attempts, so a corner cannot trap an AI forever.

var reverse_time := 0.0
var attempts := 0
var turn := 1.0
var _anchor := Vector3.INF
var _window := 0.0
var _progress := Vector3.INF


## True once per failed two-second window; callers use it to choose a new road.
func advance(at: Vector3, delta: float, moving: bool, angle: float) -> bool:
	if not _anchor.is_finite():
		_anchor = at
		_progress = at
	if at.distance_squared_to(_progress) > 64.0:
		attempts = 0
		_progress = at
	if reverse_time > 0.0:
		reverse_time = maxf(0.0, reverse_time - delta)
		_anchor = at
		_window = 0.0
		return false
	if not moving:
		_anchor = at
		_window = 0.0
		return false
	_window += delta
	if _window < 2.0:
		return false
	var stuck := at.distance_squared_to(_anchor) < 2.25
	_anchor = at
	_window = 0.0
	if stuck:
		attempts += 1
		reverse_time = 1.5
		# Alternate on repeated failure; zero steering cannot escape a head-on wall.
		turn = (1.0 if angle >= 0.0 else -1.0) * (-1.0 if attempts % 2 == 0 else 1.0)
	return stuck
