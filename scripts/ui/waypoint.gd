class_name Waypoint
extends Node
## The player's own destination: one spot in the city they're heading for,
## which the HUD (GameHud) points to with a cyan diamond and a beam, and names
## in a compass line at the top of the screen (distance, compass point, and an
## arrow turning with the camera), until the hero gets there or it's cleared.
## Set three ways, none of which need anything from the internet:
##   G         marks the spot the camera looks at (a building, the street, or
##             the ground plane out to MAX_RANGE); G again on it clears it.
##   Go to box the options menu's Mark button marks the address (or typed
##             latitude and longitude) instead of going there.
##   Clear     the options menu's Clear button.
## An address mostly lies inside its building: its waypoint moves onto the
## sidewalk nearest it (CityStreamer.sidewalk_near, as the Go to box's
## travel does) once the streets there have loaded, so it can be reached.
## Reaching it (within ARRIVE_RADIUS across, ARRIVE_HEIGHT up or down) says
## so and clears it.
## Kept in world coordinates (WorldOrigin), so it stays put through origin
## shifts. It's personal: other players don't see it (nothing about it is in
## HeroInput or PlayerSync; it doesn't change what anyone's hero does).

## Set, moved, cleared or reached (`changed`), with what to tell the player.
signal changed(message: String)

## Close enough to count as there (m, across the ground).
const ARRIVE_RADIUS := 20.0
## ...and this close in height (a rooftop's waypoint counts from the street).
const ARRIVE_HEIGHT := 80.0
## G marks the city's surface out to this far (beyond, the collision isn't
## loaded: the ground plane at sea level, out to MAX_RANGE).
const RAY_RANGE := 1500.0
const MAX_RANGE := 8000.0
## G marking within this of the current waypoint clears it instead (m).
const CLEAR_RADIUS := 30.0
## ...or looking within this angle of it (radians, about 3 degrees).
const CLEAR_ANGLE := 0.055
const COLLISION_LAYER := 1
## An address's sidewalk is looked for this far around it (m; Game's too).
const STREET_SEARCH := 80.0

## The hero it measures from.
var hero: Hero
## For moving an address's waypoint onto its sidewalk (none: it stays put).
var city: CityStreamer
## The world position (WorldOrigin.to_world), or Vector3.INF without one.
var target := Vector3.INF
## What it is: an address's name, or "Marked spot".
var label := ""
var _arrive_armed := false
## An address's waypoint, still to be moved onto its sidewalk.
var _to_sidewalk := false


## Adds the "waypoint" action: G, and a gamepad's D-pad up.
static func add_action() -> void:
	if InputMap.has_action(&"waypoint"):
		return
	InputMap.add_action(&"waypoint")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	InputMap.action_add_event(&"waypoint", key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_UP
	InputMap.action_add_event(&"waypoint", pad)


func is_set() -> bool:
	return target != Vector3.INF


## Sets the waypoint at a world position; `address`: onto the sidewalk
## nearest it once that has loaded (see the top).
func set_target(world_position: Vector3, what := "Marked spot", address := false) -> void:
	target = world_position
	label = what
	_to_sidewalk = address
	# (Set where the hero stands, it waits for them to leave and come back.)
	_arrive_armed = not _is_near()
	changed.emit("Waypoint set: %s, %s" % [what, format_distance(distance())])


func clear(message := "Waypoint cleared") -> void:
	if not is_set():
		return
	target = Vector3.INF
	label = ""
	changed.emit(message)


## G: marks where `camera` looks, or clears the waypoint when it's looking at it.
func mark_where_looking(camera: Camera3D) -> void:
	var from := camera.global_position
	var forward := -camera.global_basis.z
	if is_set():
		var toward := WorldOrigin.to_local(target) - from
		if toward.length() > 1.0 and forward.angle_to(toward) < CLEAR_ANGLE:
			clear()
			return
	var spot := look_spot(camera)
	if spot == Vector3.INF:
		changed.emit("Look at the city to mark a waypoint")
		return
	if is_set() and Vector2(spot.x - target.x, spot.z - target.z).length() < CLEAR_RADIUS:
		clear()
		return
	set_target(spot)


## The world position `camera` looks at: the city it sees within RAY_RANGE,
## else the ground plane (sea level) within MAX_RANGE; Vector3.INF if neither.
func look_spot(camera: Camera3D) -> Vector3:
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * RAY_RANGE, COLLISION_LAYER)
	if hero:
		query.exclude = [hero.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return WorldOrigin.to_world(hit.position)
	var world_from := WorldOrigin.to_world(from)
	if forward.y > -0.001:
		return Vector3.INF
	var along := -world_from.y / forward.y
	if along > MAX_RANGE:
		return Vector3.INF
	var spot := world_from + forward * along
	spot.y = 0.0
	return spot


## Meters from the hero to the waypoint, across the ground (0 without one).
func distance() -> float:
	if not is_set() or hero == null:
		return 0.0
	var at := hero.world_position()
	return Vector2(target.x - at.x, target.z - at.z).length()


## Compass bearing from the hero to it, degrees clockwise from north.
func bearing() -> float:
	if not is_set() or hero == null:
		return 0.0
	var at := hero.world_position()
	return fposmod(rad_to_deg(atan2(target.x - at.x, -(target.z - at.z))), 360.0)


## "N", "NE", ... for a bearing in degrees.
static func compass_point(degrees: float) -> String:
	const POINTS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return POINTS[int(round(fposmod(degrees, 360.0) / 45.0)) % 8]


## "85 m", "1.24 km".
static func format_distance(meters: float) -> String:
	if meters < 1000.0:
		return "%d m" % int(round(meters))
	return "%.2f km" % (meters / 1000.0) if meters < 10000.0 else "%.1f km" % (meters / 1000.0)


func _physics_process(_delta: float) -> void:
	if not is_set() or hero == null:
		return
	if _to_sidewalk and city and city.has_collision_at(target):
		_to_sidewalk = false
		var street := city.sidewalk_near(target, STREET_SEARCH)
		if street != Vector3.INF:
			var ground := city.ground_height_at(street, 1.5)  # (under any scaffolding)
			target = Vector3(street.x, street.y if is_nan(ground) else ground, street.z)
	if not _is_near():
		_arrive_armed = true
	elif _arrive_armed:
		clear("You reached your waypoint: %s" % label)


func _is_near() -> bool:
	if hero == null:
		return false
	return distance() < ARRIVE_RADIUS and absf(hero.world_position().y - target.y) < ARRIVE_HEIGHT
