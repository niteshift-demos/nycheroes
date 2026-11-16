class_name Wanted
extends Node
## Per-player police heat. Only local crimes are reported here; plain hero
## state and the encounter director carry the pursuit to nearby co-op players.

signal stars_changed(stars: int)
signal busted

const MAX_STARS := 5
const WITNESS_RANGE := 45.0
const SIGHT_RANGE := 65.0
const SEARCH_DELAY := 5.0
const DECAY_TIME := 18.0
const MAX_POLICE := 10

@export var hero: Hero
@export var city: CityStreamer
@export var encounters: EncounterDirector
@export var hud: GameHud
var stars := 0
var searching := false
var enabled := true
var heat := 0.0
var _unseen := 0.0
var _tick := 0.0
var _spawn_wait := 0.0
var _bust_wait := 0.0
var _respawn := Vector3.ZERO


func _ready() -> void:
	enabled = LaunchOptions.get_string("police", "1") != "0"
	Combat.crime.connect(_on_crime)
	hero.mode_changed.connect(_on_mode_changed)
	if enabled and LaunchOptions.has("wanted"):
		set_stars(int(LaunchOptions.get_string("wanted")))


## Used by launch options and tests; ordinary play adds witnessed heat.
func set_stars(value: int) -> void:
	heat = float(clampi(value, 0, MAX_STARS))
	_update_stars()
	_unseen = 0.0


func _update_stars() -> void:
	var next := clampi(ceili(heat), 0, MAX_STARS) if enabled else 0
	if next != stars:
		var raised := next > stars
		stars = next
		hero.wanted_stars = stars
		stars_changed.emit(stars)
		if hud and raised:
			hud.notify("WANTED  —  %d STAR%s" % [stars, "S" if stars != 1 else ""])
	if stars == 0:
		searching = false
		hero.wanted_searching = false


func _on_crime(_kind: StringName, world_position: Vector3, severity: float) -> void:
	if not enabled or _bust_wait > 0.0 or severity <= 0.0 or not is_finite(severity):
		return
	if not witnessed(world_position):
		return
	heat = minf(MAX_STARS, heat + severity)
	_unseen = 0.0
	searching = false
	hero.wanted_searching = false
	_update_stars()


## The victim can report their own assault. Walls block all witnesses.
func witnessed(at: Vector3) -> bool:
	for ped: Pedestrian in get_tree().get_nodes_in_group("pedestrians"):
		if ped.world_position.distance_to(at) < WITNESS_RANGE and _clear_sight(ped.world_position, at):
			return true
	for thug in Combat.thugs:
		if thug is PoliceOfficer and not thug.is_down() \
				and WorldOrigin.to_world(thug.global_position).distance_to(at) < WITNESS_RANGE \
				and _clear_sight(WorldOrigin.to_world(thug.global_position), at):
			return true
	return false


func _clear_sight(from_world: Vector3, to_world: Vector3) -> bool:
	var from := WorldOrigin.to_local(from_world) + Vector3.UP * 1.4
	var to := WorldOrigin.to_local(to_world) + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, Combat.WORLD_LAYER)
	return hero.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func police_see_hero() -> bool:
	for thug in Combat.thugs:
		if thug is PoliceOfficer and not thug.is_down() \
				and thug.global_position.distance_to(hero.global_position) < SIGHT_RANGE \
				and _clear_sight(WorldOrigin.to_world(thug.global_position), hero.world_position()):
			return true
	return false


## Time advances only after the city has loaded. Sight or another crime
## restarts the escape clock; each uninterrupted search sheds one star.
func advance_heat(delta: float, seen: bool) -> void:
	if stars == 0:
		return
	_unseen = 0.0 if seen else _unseen + delta
	searching = _unseen >= SEARCH_DELAY
	hero.wanted_searching = searching
	if _unseen >= SEARCH_DELAY + DECAY_TIME:
		heat = maxf(0.0, float(stars - 1))
		_unseen = SEARCH_DELAY
		_update_stars()


func _physics_process(delta: float) -> void:
	# A slow browser can have ground before its loading overlay lifts.
	# Never let the launch-option pursuit arrest a player under that overlay.
	if not enabled or hero.frozen or (hud and hud.get_parent().has_node("LoadingScreen")):
		return
	if _bust_wait > 0.0:
		_bust_wait -= delta
		if _bust_wait <= 0.0:
			hero.global_position = WorldOrigin.to_local(_respawn) + Vector3.UP * 0.3
			hero.velocity = Vector3.ZERO
			hero.health = Hero.MAX_HEALTH
			hero.hurt_time = 0.0
			hero.slam_pending = false
			hero.set_mode(&"OnFoot")
		return
	_tick += delta
	if _tick < 0.5:
		return
	advance_heat(_tick, police_see_hero() if stars > 0 else false)
	_spawn_wait -= _tick
	_tick = 0.0
	_clear_response()
	if stars > 0 and not searching and _spawn_wait <= 0.0:
		_spawn_wait = 3.0
		_spawn_response()


func _clear_response() -> void:
	for thug in Combat.thugs.duplicate():
		if thug is PoliceOfficer and not thug.puppet and thug.suspect_id == Net.local_id():
			if stars == 0 or thug.is_down() or thug.global_position.distance_to(hero.global_position) > 180.0:
				Combat.unregister(thug)
				thug.queue_free()


func _spawn_response() -> void:
	if not city or not encounters:
		return
	var count := 0
	for thug in Combat.thugs:
		if thug is PoliceOfficer and not thug.puppet:
			count += 1
	if count >= mini(stars * 2, MAX_POLICE):
		return
	var lanes := city.lanes_near(hero.world_position(), 65.0)
	var camera := get_viewport().get_camera_3d()
	for attempt in 40:
		if lanes.is_empty():
			return
		var lane: PackedVector3Array = lanes.pick_random()
		if lane.size() < 2:
			continue
		var i := randi_range(0, lane.size() - 2)
		var at := lane[i].lerp(lane[i + 1], randf())
		var distance := at.distance_to(hero.world_position())
		if distance < 22.0 or distance > 65.0 or not city.has_collision_at(at):
			continue
		var local := WorldOrigin.to_local(at) + Vector3.UP
		if camera and camera.is_position_in_frustum(local) and _clear_sight(WorldOrigin.to_world(camera.global_position), at):
			continue
		at.y = city.ground_height_at(at, EncounterDirector.GROUND_SEARCH)
		if not is_finite(at.y):
			continue
		encounters.spawn_police(at, hero, stars)
		return


func _on_mode_changed(mode_name: StringName) -> void:
	if stars == 0 or mode_name != &"KnockedOut" or _bust_wait > 0.0:
		return
	_respawn = hero.world_position()
	if city:
		var lanes := city.lanes_near(_respawn, 80.0)
		var closest := INF
		for lane: PackedVector3Array in lanes:
			for at in lane:
				var distance := at.distance_squared_to(hero.world_position())
				if distance < closest and city.has_collision_at(at):
					closest = distance
					_respawn = at
		var ground := city.ground_height_at(_respawn, EncounterDirector.GROUND_SEARCH)
		if is_finite(ground):
			_respawn.y = ground
	_bust_wait = 2.0
	set_stars(0)
	_clear_response()
	if hud:
		hud.notify("BUSTED")
	busted.emit()
