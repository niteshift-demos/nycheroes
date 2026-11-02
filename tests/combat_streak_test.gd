extends Node
## Synthetic fight: real strikes against standing thugs, fair accounting,
## payout, damage/timeout resets, origin shifts and PlayerSync round trip.
## Run: godot --headless --path . res://tests/combat_streak_test.tscn

var failures := 0

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func _ready() -> void:
	var hero: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	hero.set_physics_process(false)
	hero.health = 50.0
	hero.record_combat_hit(&"punch", 0)
	check(hero.rhythm == 0, "whiffs give no credit")
	hero.record_combat_hit(&"punch", 5)
	check(hero.rhythm == 1, "one award for an area hit")
	hero.record_combat_hit(&"ram", 1)
	check(hero.rhythm == 1, "continuous hits cannot farm in same tick")
	hero.tick_rhythm(0.4)
	hero.record_combat_hit(&"ram", 1)
	check(hero.rhythm == 3, "variety awards two points")
	hero.frozen = true
	var deadline := hero.rhythm_time
	hero._physics_process(2.0)
	check(hero.rhythm_time == deadline, "frozen hero pauses deadline")
	hero.frozen = false
	WorldOrigin.shift(Vector3(500, 0, 0))
	check(hero.rhythm == 3, "origin shifts preserve progress")
	hero.tick_rhythm(0.4)
	hero.record_combat_hit(&"slam", 1)
	hero.tick_rhythm(0.4)
	hero.record_combat_hit(&"slam", 1)
	check(hero.rhythm == 0 and hero.rallies == 1 and hero.health == 65.0, "six points cash out once and heal 15")
	hero.tick_rhythm(0.4)
	hero.record_combat_hit(&"punch", 1)
	hero.tick_rhythm(7.01)
	check(hero.rhythm == 0 and hero.rhythm_notice.contains("7 seconds"), "inactivity resets with explanation")
	hero.record_combat_hit(&"punch", 1)
	hero.take_hit(0.0, Vector3.ZERO)
	check(hero.rhythm == 1, "zero damage does not break streak")
	hero.take_hit(6.0, Vector3.ZERO)
	check(hero.rhythm == 0 and hero.rhythm_notice.contains("took a hit"), "actual damage resets")
	hero.tick_rhythm(0.4)
	hero.remote_id = 2
	hero.record_combat_hit(&"punch", 1)
	check(hero.rhythm == 0, "remote copies cannot earn local rewards")
	hero.remote_id = 0
	hero.health = 99.0
	for k in 6:
		hero.tick_rhythm(0.4)
		hero.record_combat_hit(&"punch", 1)
	check(hero.health == 100.0 and hero.rallies == 2, "sustained punches reward without overhealing")
	hero.tick_rhythm(0.4)
	hero.record_combat_hit(&"punch", 1)
	var sync := PlayerSync.new()
	var state := sync._encode(hero)
	var snapshots := SnapshotBuffer.new()
	snapshots.push(float(state[0]), state)
	var copy: Hero = load("res://scenes/hero/hero.tscn").instantiate()
	copy.remote_id = 2
	add_child(copy)
	sync._follow(copy, snapshots)
	check(copy.rhythm == hero.rhythm and copy.rallies == hero.rallies, "co-op snapshot preserves progress and rally count")
	var thug: Thug = load("res://scenes/npc/thug.tscn").instantiate()
	add_child(thug)
	thug.setup(hero, 0, 0.0)
	thug.global_position = hero.global_position
	var hp := thug.health
	Combat.shockwave(hero.global_position, 7.0, 0.0, 16.0)
	check(thug.health == hp and thug.velocity.length() > 0.0 and not thug.is_down(), "rally pulse repels without damage or knockout")
	check(Combat.strike(thug.body_center(), 2.0, 100.0, Vector3.UP, true) == 1, "standing target counts")
	check(Combat.strike(thug.body_center(), 2.0, 100.0, Vector3.UP, true) == 0, "downed target never counts")
	hero.take_hit(100.0, Vector3.ZERO)
	check(hero.rhythm == 0 and hero.mode.name == &"KnockedOut", "knockout clears progress")
	sync.free()
	Engine.time_scale = 1.0
	get_tree().quit(1 if failures else 0)
