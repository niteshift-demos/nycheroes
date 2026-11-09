class_name RooftopTrialState
extends RefCounted
## Ordered world-space gates keep the local stopwatch independent of origin shifts.

const GATES: Array[Vector3] = [
	Vector3(12, 32.724, 76), Vector3(12, 32.724, 52),
	Vector3(28, 32.724, 52), Vector3(28, 32.724, 76), Vector3(12, 32.724, 76),
]
const RADIUS := 1.8
var next_gate := 0
var elapsed := 0.0
var running := false
var finished := false
var message := "Enter the green start gate"


func reset() -> void:
	next_gate = 0
	elapsed = 0.0
	running = false
	finished = false
	message = "Enter the green start gate"


func step(delta: float, world: Vector3, mode: StringName) -> void:
	if finished:
		return
	if running:
		elapsed += delta
		if mode in [&"Flight", &"Swing", &"Dive", &"KnockedOut"] or world.y < 30.0:
			running = false
			finished = true
			message = "Run ended — stay on the roof; no flight or webs"
			return
	if world.distance_to(GATES[next_gate] + Vector3.UP * 0.05) > RADIUS:
		return
	if mode != &"OnFoot":
		return
	running = true
	next_gate += 1
	if next_gate == GATES.size():
		running = false
		finished = true
		message = "Finished! Restart to race your best"
	else:
		message = "Checkpoint %d / %d — follow the gold gate" % [next_gate, GATES.size() - 1]
