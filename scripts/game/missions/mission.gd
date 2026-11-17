class_name Mission
extends Resource
## Data-only mission definition. Positions are absolute world meters, so
## progress and targets remain correct across floating-origin shifts.

@export var id: String
@export var title: String
@export var intro: String
@export var reward: int = 1000
@export var giver: Vector3
## Dictionaries made by the constructors below; never mutated during play.
@export var steps: Array[Dictionary] = []


static func go_to(position: Vector3, radius: float, text: String) -> Dictionary:
	return {kind = "go_to", position = position, radius = radius, text = text}


static func defeat_gang_at(position: Vector3, count: int, text: String) -> Dictionary:
	return {kind = "defeat_gang_at", position = position, count = count, radius = 70.0, text = text}


static func reach_in_time(position: Vector3, seconds: float, text: String, radius := 35.0) -> Dictionary:
	return {kind = "reach_in_time", position = position, seconds = seconds, radius = radius, text = text}


static func collect(items: Array[Vector3], text: String, radius := 9.0) -> Dictionary:
	return {kind = "collect", position = items[0], items = items, radius = radius, text = text}
