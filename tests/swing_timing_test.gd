extends Node3D
## Synthetic pendulum checks; no city downloads. Run with swing_timing_test.tscn.
var _failed := false

func _ready() -> void:
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = true
	var swing := hero.get_mode(&"Swing") as SwingMode
	swing.anchor = Vector3(0, 40, 0)
	swing.rope_length = 30.0
	hero.position = Vector3(3, 8.6, 0)
	hero.velocity = Vector3(30, 4, 0)
	swing.enter(&"OnFoot")
	swing._update_timing(0.016)
	_check(not swing.release_ready, "fresh attachment cannot farm boost")
	swing._age = 0.5
	hero.position.x = -3.0
	swing._update_timing(0.016)
	_check(not swing.release_ready, "rising before the bottom does not light the green cue")
	hero.position.x = 3.0
	swing._update_timing(0.016)
	_check(swing.release_ready, "rising near bottom is ready")
	swing._release()
	_check(swing.last_release_timed and is_equal_approx(hero.velocity.x, 43.0), "timed release adds nine to ordinary launch")
	hero.velocity = Vector3(30, -10, 0)
	swing._update_timing(0.2)
	swing._release()
	_check(not swing.last_release_timed and is_equal_approx(hero.velocity.x, 34.0), "descending release retains ordinary boost")
	hero.velocity = Vector3(30, 4, 0)
	swing._update_timing(0.016)
	hero.position.x = 18.0
	swing._update_timing(0.05)
	_check(swing.release_ready, "grace tolerates a late input tick")
	swing._update_timing(0.2)
	_check(not swing.release_ready, "grace expires")
	hero.position = Vector3(3, 8.6, 0)
	hero.velocity = Vector3(3, 4, 0)
	swing._update_timing(0.2)
	_check(not swing.release_ready, "slow release gives no bonus")
	hero.velocity = Vector3(60, 20, 0)
	swing._update_timing(0.016)
	swing._release()
	_check(hero.velocity.length() <= SwingMode.RELEASE_SPEED_LIMIT + 0.001, "release speed is bounded")
	hero.velocity = Vector3(30, 4, 0)
	swing._update_timing(0.016)
	var before := swing.arc_position
	hero.position -= Vector3(1000, 0, 500)
	swing.anchor -= Vector3(1000, 0, 500)
	swing._update_timing(0.016)
	_check(swing.release_ready and is_equal_approx(before, swing.arc_position), "origin shift preserves timing")
	swing._release(false)
	_check(not swing.last_release_timed, "automatic releases never get timing bonus")
	print("Swing timing checks complete")
	get_tree().quit(1 if _failed else 0)

func _check(ok: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", label])
	_failed = _failed or not ok
