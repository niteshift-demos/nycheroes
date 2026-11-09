extends Node
## Synthetic eligibility and authoritative countdown checks; no city data required.
## godot --headless --path . res://tests/threat_awareness_test.tscn

var _failed := false


func _ready() -> void:
	var hero := load("res://scenes/hero/hero.tscn").instantiate() as Hero
	add_child(hero)
	hero.set_physics_process(false)
	hero.frozen = false
	var thug := load("res://scenes/npc/thug.tscn").instantiate() as Thug
	add_child(thug)
	thug.set_physics_process(false)
	thug.setup(hero, 0, 0.0)
	thug.position = Vector3(2.0, 0.0, 0.0)
	_check(not ThreatAwareness.eligible(thug, hero), "idle gangs are not threats")
	thug.state = Thug.State.CHASE
	_check(ThreatAwareness.eligible(thug, hero), "nearby pursuer is a threat")
	thug.state = Thug.State.PUNCH
	thug._timer = 0.31
	_check(is_equal_approx(thug.incoming_seconds(), 0.31), "countdown reads contact timer")
	thug.state = Thug.State.STAGGER
	_check(thug.incoming_seconds() < 0.0, "interrupt removes incoming warning")
	thug.state = Thug.State.CHASE
	thug.position.x = 25.0
	_check(not ThreatAwareness.eligible(thug, hero), "distant enemies are excluded")
	thug.position = Vector3(2.0, 5.0, 0.0)
	_check(not ThreatAwareness.eligible(thug, hero), "another floor is excluded")
	thug.position = Vector3(2.0, 0.0, 0.0)
	thug.puppet = true
	thug._snapshots = SnapshotBuffer.new()
	thug.push_snapshot(0, Vector3.ZERO, 0, 100, 3, 1.3, 1, Thug.State.PUNCH, 0.25, Net.local_id())
	_check(ThreatAwareness.eligible(thug, hero), "copy uses authoritative target")
	_check(is_equal_approx(thug.incoming_seconds(), 0.25), "copy uses authoritative timer")
	thug._threat_target = Net.local_id() + 1
	_check(not ThreatAwareness.eligible(thug, hero), "another player's attacker is excluded")
	thug.puppet = false
	thug.state = Thug.State.DOWN
	_check(not ThreatAwareness.eligible(thug, hero), "defeated enemies are excluded")
	if _failed:
		get_tree().quit(1)
		return
	print("Threat awareness: 10 checks passed")
	get_tree().quit()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failed = true
		push_error(label)
		get_tree().quit(1)
