extends Node
## Synthetic checks: ordered gate bounds and high-speed crossing, medal boundaries,
## countdown/retry/exit, local best, and floating-origin handling without city data.
## Run: godot --headless --path . res://tests/rooftop_trial_test.tscn

var _failed := 0

func _ready() -> void:
	_check(RooftopTrial.crosses_gate(Vector3(-220, 364, 10), Vector3(-220, 364, -50), 0), "fast flight crosses first gate")
	_check(not RooftopTrial.crosses_gate(Vector3(-200, 364, 10), Vector3(-200, 364, -50), 0), "sideways shortcut misses gate")
	_check(not RooftopTrial.crosses_gate(Vector3(-220, 390, 10), Vector3(-220, 390, -50), 0), "flying above misses gate")
	_check(RooftopTrial.medal(5.0) == "GOLD" and RooftopTrial.medal(5.01) == "SILVER", "gold boundary")
	_check(RooftopTrial.medal(12.0) == "SILVER" and RooftopTrial.medal(25.0) == "BRONZE" and RooftopTrial.medal(25.01) == "FINISHER", "remaining medal boundaries")
	# A real hero and course, without city startup or network downloads.
	var game := Game.new()
	game.hero = preload("res://scenes/hero/hero.tscn").instantiate() as Hero
	add_child(game.hero)
	game.hero_camera = ThirdPersonCamera.new()
	game.player_input = PlayerInput.new()
	game.hud = CanvasLayer.new()
	add_child(game.hud)
	var trial := RooftopTrial.new()
	trial.game = game
	add_child(trial)
	trial.set_process(false)
	trial.set_physics_process(false)
	var original := game.hero.world_position()
	trial.start()
	_check(trial.phase == RooftopTrial.Phase.COUNTDOWN and game.hero.frozen, "start holds hero for countdown")
	trial._physics_process(3.1)
	_check(trial.phase == RooftopTrial.Phase.RUNNING and not game.hero.frozen, "countdown releases hero")
	# Going straight to the finish cannot skip the first five gates.
	game.hero.global_position = WorldOrigin.to_local(RooftopTrial.gate_world(5) + Vector3.RIGHT * 20.0)
	trial._physics_process(0.016)
	_check(trial.next_gate < 6, "out-of-order finish is rejected")
	trial.start()
	trial._physics_process(3.1)
	WorldOrigin.shift(Vector3(2000.0, 0.0, -1000.0))
	_check(trial.global_position.is_equal_approx(WorldOrigin.to_local(RooftopTrial.START)), "course survives origin shift")
	for i in 6:
		game.hero.global_position = WorldOrigin.to_local(RooftopTrial.gate_world(i))
		trial._physics_process(0.016)
	_check(trial.phase == RooftopTrial.Phase.FINISHED and trial.next_gate == 6, "six ordered gates finish after origin shift")
	_check(Settings.has_value(RooftopTrial.BEST_KEY), "finish records local best")
	trial.start()
	_check(trial.next_gate == 0 and trial.elapsed == 0.0, "retry resets gates and timer")
	trial._physics_process(3.1)
	game.hero.global_position.y = RooftopTrial.START.y - 25.0
	trial._physics_process(0.016)
	_check(trial.phase == RooftopTrial.Phase.FAILED, "fall ends run")
	trial.start()
	trial._physics_process(3.1)
	trial._started = Time.get_ticks_msec() - 91000
	trial._physics_process(0.016)
	_check(trial.phase == RooftopTrial.Phase.FAILED, "90 second limit ends run")
	trial.leave()
	_check(trial.phase == RooftopTrial.Phase.READY and game.hero.world_position().is_equal_approx(original), "leave restores world position")
	game.hero_camera.free()
	game.player_input.free()
	game.free()
	print("[rooftop_trial] %d failures" % _failed)
	get_tree().quit(1 if _failed else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed += 1
	print("[rooftop_trial] %s: %s" % ["PASS" if ok else "FAIL", label])
