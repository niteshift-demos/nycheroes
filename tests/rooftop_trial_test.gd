extends Node
## Run: godot --headless --path . res://tests/rooftop_trial_test.tscn
func _ready() -> void:
	var trial := RooftopTrialState.new()
	trial.step(0.1, RooftopTrialState.GATES[2], &"OnFoot")
	assert(trial.next_gate == 0, "Out-of-order gates must not start a run")
	for gate in RooftopTrialState.GATES:
		trial.step(1.0, gate, &"OnFoot")
	assert(trial.finished and not trial.running and trial.elapsed == 4.0)
	trial.reset()
	trial.step(0.1, RooftopTrialState.GATES[0], &"OnFoot")
	trial.step(0.1, RooftopTrialState.GATES[1], &"Flight")
	assert(trial.finished and trial.next_gate == 1, "Flight invalidates the run")
	trial.reset()
	trial.step(0.1, RooftopTrialState.GATES[0], &"OnFoot")
	trial.step(0.1, Vector3(12, 29, 76), &"OnFoot")
	assert(trial.finished, "Falling off invalidates the run")
	trial.reset()
	assert(not trial.finished and not trial.running and trial.elapsed == 0)
	print("rooftop_trial_test: PASS (order, timing, finish, flight, fall, restart)")
	get_tree().quit()
