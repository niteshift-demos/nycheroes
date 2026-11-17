class_name PlayerStats
extends Node
## Local lifetime totals. World positions survive origin shifts; travel jumps
## and loading never count as movement. Distance saves are batched for web storage.

var hero: Hero
var missions: MissionDirector
var totals: Dictionary = {}
var _last := Vector3.INF
var _save_in := 10.0
var _driving := false
var _taken_cars: Array[int] = []


func _ready() -> void:
	totals = (Settings.get_value("player_stats", {}) as Dictionary).duplicate(true)
	if missions:
		missions.mission_finished.connect(record_mission)


func _physics_process(delta: float) -> void:
	var stamp := GtaTiming.begin()
	_playerstats_timed_physics_process(delta)
	GtaTiming.end(&"stats", stamp)


func _playerstats_timed_physics_process(delta: float) -> void:
	if not hero or not hero.mode:
		return
	var mode := hero.mode.name
	var driving := mode == &"Drive"
	if driving and not _driving:
		var car := (hero.mode as DriveMode).car
		if is_instance_valid(car) and not _taken_cars.has(car.get_instance_id()):
			_taken_cars.append(car.get_instance_id())
			increment("cars_stolen")
	_driving = driving
	if hero.wanted_stars > int(totals.get("max_wanted", 0)):
		totals.max_wanted = hero.wanted_stars
		save()
	var here := hero.world_position()
	if not hero.frozen and _last != Vector3.INF:
		var distance := here.distance_to(_last)
		if distance < maxf(25.0, hero.velocity.length() * delta * 3.0):
			if driving:
				totals.driven_m = float(totals.get("driven_m", 0.0)) + distance
			elif mode == &"Flight":
				totals.flown_m = float(totals.get("flown_m", 0.0)) + distance
	_last = here
	_save_in -= delta
	if _save_in <= 0.0:
		_save_in = 10.0
		save()


## Each successful finish emits once, including repeatable jobs.
func record_mission(id: String, success: bool) -> void:
	if not success:
		return
	var completed: Dictionary = totals.get("completed", {})
	completed[id] = int(completed.get(id, 0)) + 1
	totals.completed = completed
	increment("missions_passed")


func increment(key: String) -> void:
	totals[key] = int(totals.get(key, 0)) + 1
	save()


func save() -> void:
	Settings.set_value("player_stats", totals.duplicate(true))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
