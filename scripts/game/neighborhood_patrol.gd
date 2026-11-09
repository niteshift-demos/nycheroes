class_name NeighborhoodPatrol
extends RefCounted
## A personal, session-only goal. Encounter birth positions use world meters,
## so leaving the area or shifting the floating origin never moves the boundary.

const RADIUS := 300.0
const TARGET := 2

var active := false
var completed := false
var cleared := 0
var center := Vector3.ZERO
var _eligible: Dictionary[int, Vector3] = {}


func start(at: Vector3) -> void:
	center = at
	cleared = 0
	completed = false
	active = true
	_eligible.clear()


func encounter_started(id: int, at: Vector3) -> void:
	if active and _distance(at) <= RADIUS:
		_eligible[id] = at


func encounter_removed(id: int) -> void:
	_eligible.erase(id)


## Only a full encounter defeat event counts. Despawns and individual
## knockdowns never advance the goal; outside-area clears cannot be banked.
func encounter_cleared(id: int, hero_at: Vector3) -> void:
	var eligible := _eligible.has(id)
	_eligible.erase(id)
	if not active or not eligible or _distance(hero_at) > RADIUS:
		return
	cleared += 1
	if cleared >= TARGET:
		active = false
		completed = true


func distance_from(at: Vector3) -> float:
	return _distance(at)


func _distance(at: Vector3) -> float:
	return Vector2(at.x - center.x, at.z - center.z).length()
