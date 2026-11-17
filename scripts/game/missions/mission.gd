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

## Zero for replayable contracts; story chapters unlock in this order.
@export var chapter := 0
@export var calls: Array[Dictionary] = []


static func drive_to(position: Vector3, text: String, radius := 22.0) -> Dictionary:
	return {kind = "drive_to", position = position, text = text, radius = radius}


## A marked car is supplied at position; false accepts any occupied car.
static func steal_car(position: Vector3, text: String, marked := true) -> Dictionary:
	return {kind = "steal_car", position = position, text = text, marked = marked}


static func chase(position: Vector3, text: String) -> Dictionary:
	return {kind = "chase", position = position, text = text, seconds = 150.0}


static func escape_wanted(position: Vector3, stars: int, text: String) -> Dictionary:
	return {kind = "escape_wanted", position = position, stars = stars, text = text}


static func protect(position: Vector3, seconds: float, text: String) -> Dictionary:
	return {kind = "protect", position = position, duration = seconds, text = text}


static func destroy(position: Vector3, count: int, text: String) -> Dictionary:
	return {kind = "destroy", position = position, count = count, text = text}


static func fly_through(rings: Array[Vector3], text: String, radius := 22.0) -> Dictionary:
	return {kind = "fly_through", position = rings[0], items = rings, radius = radius, text = text, seconds = 120.0}


static func boss(position: Vector3, variant: int, text: String) -> Dictionary:
	var step := defeat_gang_at(position, 1, text)
	step.boss = variant
	return step
