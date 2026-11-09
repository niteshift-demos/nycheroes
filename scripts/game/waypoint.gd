class_name Waypoint
extends Node
## The player's own waypoint: one spot in the city to head for, shown by the
## HUD (GameHud) as a marker over it and a compass line at the top of the
## screen with the direction and distance.
##
## Set it with G (a gamepad's D-pad up): it goes on the first street, roof or
## wall the camera looks at within MARK_RANGE. Looking at the sky, at water,
## at buildings so far off their collision hasn't loaded, or closer than
## ARRIVE_RADIUS, nothing is marked and the HUD says why. G again clears it
## (Game passes G on only while the hero is being played: no menu open, no
## free camera). The options menu's Go to box sets one on an address too
## (its Mark button, beside Go: no travelling), and has a Clear button. It
## clears itself once the hero gets within ARRIVE_RADIUS of it (on the
## ground, or anywhere in the air above it), with a notice.
##
## Kept in world meters (WorldOrigin), so it survives the floating origin's
## shifts, and in Settings ("waypoint"), so it's still there after a reload.
## It's personal: other players in co-op don't see it, and it isn't hero state
## (it changes nothing the hero does), so PlayerSync doesn't carry it.

## The waypoint was set, moved or cleared.
signal changed
## The waypoint went: the player cleared it, or the hero got there
## (`arrived`; reached follows).
signal cleared(arrived: bool)
## The hero got there; the waypoint has cleared itself.
signal reached(label: String)
## G found nothing to mark (the HUD shows `reason`).
signal mark_failed(reason: String)

## G marks what the camera looks at up to this far (m). The city has
## collision only within about a kilometer of the hero, so further than that
## a ray finds nothing anyway; the limit keeps the answer the same everywhere.
const MARK_RANGE := 1200.0
## Within this distance (m, across the ground) the hero has got there.
const ARRIVE_RADIUS := 25.0
## Settings key: [x, y, z, label], or [] for none.
const SETTING := "waypoint"
const DEFAULT_LABEL := "Waypoint"
## Water is a separate layer (CityStreamer.WATER_LAYER): a waypoint on the
## river would be somewhere nobody can stand, so the ray stops at it.
const RAY_MASK := CityStreamer.COLLISION_LAYER | CityStreamer.WATER_LAYER

@export var hero: Hero
@export var camera_rig: ThirdPersonCamera

## World position (WorldOrigin) of the waypoint; Vector3.INF when there's none.
var world_position := Vector3.INF
## What it marks: an address from the Go to box, or DEFAULT_LABEL.
var label := ""


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


func _ready() -> void:
	add_action()
	var saved: Variant = Settings.get_value(SETTING, [])
	if saved is Array and (saved as Array).size() == 4:
		var at := Vector3(float(saved[0]), float(saved[1]), float(saved[2]))
		if at.is_finite():
			world_position = at
			label = str(saved[3])


func is_set() -> bool:
	return world_position != Vector3.INF


## Puts the waypoint at a world position (WorldOrigin), labeled.
func set_at(at: Vector3, what := DEFAULT_LABEL) -> void:
	world_position = at
	label = what if not what.is_empty() else DEFAULT_LABEL
	Settings.set_value(SETTING, [at.x, at.y, at.z, label])
	changed.emit()


func clear(arrived := false) -> void:
	if not is_set():
		return
	world_position = Vector3.INF
	label = ""
	Settings.set_value(SETTING, [])
	cleared.emit(arrived)
	changed.emit()


## G: clears the waypoint, or marks what the camera looks at (see the top).
func toggle_from_view() -> void:
	if is_set():
		clear()
	else:
		mark_from_view()


## Marks the first surface along the camera's view within MARK_RANGE.
## Returns whether it found one; when not, mark_failed says why.
func mark_from_view() -> bool:
	var camera := camera_rig.camera
	var from := camera.global_position
	var hit := find_surface(from, -camera.global_basis.z)
	if hit.is_empty():
		mark_failed.emit("Nothing to mark there: look at a street or a building within %.1f km" % (MARK_RANGE / 1000.0))
		return false
	if int(hit.collider_layer) & CityStreamer.WATER_LAYER:
		mark_failed.emit("Can't mark the water: look at a street or a building")
		return false
	var at := WorldOrigin.to_world(hit.position)
	var hero_at := hero.world_position()
	if Vector2(at.x - hero_at.x, at.z - hero_at.z).length() < ARRIVE_RADIUS:
		mark_failed.emit("That's right here: look further off to mark somewhere")
		return false
	set_at(at)
	return true


## The first city surface along a ray from a scene position (not the hero:
## the camera sits behind it); empty if none within MARK_RANGE. The result's
## collider_layer is the layer it hit.
func find_surface(from: Vector3, direction: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * MARK_RANGE, RAY_MASK)
	query.exclude = [hero.get_rid()]
	query.hit_back_faces = false
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return hit
	var layer := 0
	var collider := hit.collider as CollisionObject3D
	if collider:
		layer = collider.collision_layer
	hit.collider_layer = layer
	return hit


## Ground distance from the hero to the waypoint (m), INF without one.
func ground_distance() -> float:
	if not is_set():
		return INF
	var at := hero.world_position()
	return Vector2(world_position.x - at.x, world_position.z - at.z).length()


## How far the waypoint is above the hero (m; negative: below).
func height_above_hero() -> float:
	return world_position.y - hero.world_position().y if is_set() else 0.0


## Compass bearing of the waypoint from the hero relative to where the camera
## faces, in radians: 0 straight ahead, positive to the right.
func bearing_from_view() -> float:
	if not is_set():
		return 0.0
	var at := hero.world_position()
	var toward := Vector2(world_position.x - at.x, world_position.z - at.z)
	if toward.length() < 0.01:
		return 0.0
	var forward := camera_rig.aim_direction()
	var ahead := Vector2(forward.x, forward.z)
	if ahead.length() < 0.01:
		ahead = Vector2(-sin(camera_rig.yaw), -cos(camera_rig.yaw))
	return ahead.angle_to(toward)


func _physics_process(_delta: float) -> void:
	if is_set() and not hero.frozen and ground_distance() < ARRIVE_RADIUS:
		var what := label
		clear(true)
		reached.emit(what)

