extends Node3D
## Confirmed-hit feedback regression; synthetic bodies, no city downloads.
## godot --headless --path . res://tests/combo_test.tscn
var _failures := 0


func _ready() -> void:
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.set_physics_process(false)
	hero.frozen = false
	var thug: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	add_child(thug)
	thug.set_physics_process(false)
	var health := thug.health
	Combat.strike(thug.body_center(), 2.0, 10.0, Vector3.ZERO, false)
	_check(Combat.combo.count == 1, "one real hit earns one count")
	_check(is_equal_approx(thug.health, health - 10.0), "damage remains unchanged")
	Combat.strike(Vector3(100, 100, 100), 1.0, 10.0, Vector3.ZERO, false)
	_check(Combat.combo.count == 1, "misses do not count")
	Combat.shockwave(thug.global_position, 3.0, 0.0, 1.0)
	_check(Combat.combo.count == 1, "zero damage does not count")
	Combat.combo.advance(3.9)
	Combat.strike(thug.body_center(), 2.0, 10.0, Vector3.ZERO, false)
	_check(Combat.combo.count == 2 and Combat.combo.remaining == 4.0, "confirmed hit refreshes window")
	Combat.combo.advance(4.0)
	_check(Combat.combo.count == 0 and Combat.combo.notice.contains("TIME UP"), "timeout ends streak")
	Combat.combo.confirm(5)
	_check(Combat.combo.tier() == "ON FIRE", "five hits earn named feedback")
	Combat._combo_pending[100] = [0, 100.0]
	hero.take_hit(5.0, Vector3.ZERO)
	Combat._confirm_combo(100, 2)
	_check(Combat.combo.count == 0 and Combat.combo.notice.contains("HIT TAKEN"), "damage resets and rejects late acknowledgement")
	_check(Combat.combo.best == 5, "session best survives reset")
	thug.go_down(Vector3.ZERO)
	Combat.strike(thug.body_center(), 2.0, 10.0, Vector3.ZERO, false)
	_check(Combat.combo.count == 0, "downed thugs do not count")
	Combat._combo_pending[101] = [5, 100.0]
	Combat._confirm_combo(101, 3)
	_check(Combat.combo.count == 0, "wrong owner cannot confirm")
	Combat._combo_pending[102] = [0, 100.0]
	Combat._confirm_combo(102, 3)
	Combat._confirm_combo(102, 3)
	_check(Combat.combo.count == 3, "owner acknowledgement counts once")
	Combat.combo.reset("TEST")
	var puppet: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	puppet.puppet = true
	puppet.run_by = 7
	puppet.net_id = 7
	add_child(puppet)
	puppet.set_physics_process(false)
	Combat.strike(puppet.body_center(), 2.0, 10.0, Vector3.ZERO, false)
	_check(Combat.combo.count == 0, "predicted remote hits wait for owner confirmation")
	Combat._combo_pending[103] = [0, -1.0]
	Combat._confirm_combo(103, 4)
	_check(Combat.combo.count == 0, "expired acknowledgement does not start a streak")
	print("COMBO: %d failures" % _failures)
	Engine.time_scale = 1.0
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, description: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", description])
	if not ok:
		_failures += 1
