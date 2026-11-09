extends Node
## Headless check of CombatStreak's rules, no city needed: hits add up, the
## window runs out on game time, getting hurt breaks it, the best is kept, and
## Combat.strike only counts thugs actually hit (none here: no fake hits).
## Run: godot --headless --path . res://tests/streak_test.tscn

var _failures := 0


func _ready() -> void:
	var streak := CombatStreak.new()
	var ends: Array = []
	streak.ended.connect(func(count: int, reason: StringName) -> void: ends.append([count, reason]))
	streak.add_hits(0)
	_check(streak.count == 0, "zero hits start nothing")
	streak.add_hits(1)
	streak.update(CombatStreak.WINDOW * 0.9)
	streak.add_hits(2)
	_check(streak.count == 3, "hits within the window add up (%d)" % streak.count)
	streak.update(CombatStreak.WINDOW * 0.9)
	_check(streak.count == 3, "a fresh hit restarts the window")
	streak.update(CombatStreak.WINDOW * 0.2)
	_check(streak.count == 0 and ends == [[3, &"timeout"]], "times out after the window (%s)" % [ends])
	for k in 6:
		streak.add_hits(1)
	_check(CombatStreak.tier_name(streak.count) == "NICE", "a 6-hit streak is NICE")
	streak.break_streak(&"hurt")
	_check(streak.count == 0 and ends.back() == [6, &"hurt"], "getting hurt breaks it")
	_check(streak.best == 6, "the best is kept (%d)" % streak.best)
	streak.break_streak(&"hurt")
	_check(ends.size() == 2, "breaking no streak reports nothing")

	var before := Combat.streak.count
	Combat.strike(Vector3.ZERO, 100.0, 50.0, Vector3.ZERO, false)
	Combat.shockwave(Vector3.ZERO, 100.0, 100.0, 10.0)
	_check(Combat.streak.count == before, "a strike or slam hitting nobody counts nothing")
	print("streak_test: %s" % ("OK" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   " + what)
	else:
		_failures += 1
		printerr("  FAIL " + what)
