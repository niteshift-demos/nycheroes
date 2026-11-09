extends Node
## Event contract: fresh full encounters, radius, deduplication and replay.
## Run: godot --headless --path . res://tests/patrol_test.tscn

func _ready() -> void:
	var p := NeighborhoodPatrol.new()
	p.encounter_started(0, Vector3.ZERO)
	p.start(Vector3(1000, 5, 1000))
	p.encounter_cleared(0, p.center)
	assert(p.cleared == 0, "pre-start encounters do not count")
	p.encounter_started(1, p.center + Vector3(301, 0, 0))
	p.encounter_cleared(1, p.center)
	assert(p.cleared == 0, "outside spawn does not count")
	p.encounter_started(2, p.center)
	p.encounter_removed(2)
	p.encounter_cleared(2, p.center)
	assert(p.cleared == 0, "despawning does not count")
	p.encounter_started(3, p.center)
	p.encounter_cleared(3, p.center + Vector3(301, 0, 0))
	p.encounter_cleared(3, p.center)
	assert(p.cleared == 0, "outside clears cannot be banked")
	p.encounter_started(4, p.center + Vector3(300, 100, 0))
	p.encounter_cleared(4, p.center)
	p.encounter_cleared(4, p.center)
	assert(p.cleared == 1 and p.active, "inclusive horizontal boundary; deduplicated")
	p.encounter_started(5, p.center)
	p.encounter_cleared(5, p.center)
	assert(p.completed and not p.active and p.cleared == 2)
	p.encounter_started(6, p.center)
	p.start(Vector3(-500, 0, 0))
	p.encounter_cleared(6, p.center)
	assert(p.active and not p.completed and p.cleared == 0, "replay resets eligibility")
	var director := EncounterDirector.new()
	var a := Thug.new()
	var b := Thug.new()
	a.gang = 99
	b.gang = 99
	var full_clears: Array[int] = []
	director.encounter_cleared.connect(func(id: int) -> void: full_clears.append(id))
	director._encounter_living[99] = [a, b]
	director._encounter_initial[99] = {"center": Vector3.ZERO, "count": 2}
	assert(director.patrol_candidates().has(99), "complete standing roster eligible at start")
	director._on_thug_defeated(a)
	assert(director.patrol_candidates().is_empty(), "partly cleared roster ineligible on replay")
	director._on_thug_defeated(a)
	assert(full_clears.is_empty(), "individual or duplicate defeats cannot clear a gang")
	director._on_thug_defeated(b)
	director._on_thug_defeated(b)
	assert(full_clears == [99], "full gang emits once")
	a.free()
	b.free()
	director.free()
	print("Patrol event contract passed: eligibility, radius, despawn, duplicate, completion, replay")
	get_tree().quit()
