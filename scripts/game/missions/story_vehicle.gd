class_name StoryVehicle
extends DriveVehicle
## Mission-owned physical car. AI follows loaded traffic polylines using
## plain HeroInput; punches/slams and relative-speed impacts damage its relay.

var health := 160.0
var fleeing := false
var city: CityStreamer
var _path := PackedVector3Array()
var _point := 1
var _impact_wait := 0.0
var _stuck := 0.0
var _label: Label3D


func _ready() -> void:
	super._ready()
	Combat.area_hit.connect(_on_area_hit)
	_label = Label3D.new()
	_label.text = "LEDGER VAN" if fleeing else "RELAY"
	_label.font_size = 40
	_label.modulate = Color.GOLD
	_label.position.y = 3.4
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)
	if fleeing:
		remove_from_group("drive_cars")  # Disable takeover until the relay is stopped.


func _physics_process(delta: float) -> void:
	if health <= 0.0 or driver:
		super._physics_process(delta)
		return
	_impact_wait = maxf(0.0, _impact_wait - delta)
	for car: DriveVehicle in get_tree().get_nodes_in_group("drive_cars"):
		if car == self or car.global_position.distance_to(global_position) > 4.5:
			continue
		var impact := (car.velocity - velocity).length()
		if impact > 4.0 and _impact_wait <= 0.0:
			damage(impact * 7.0)
			_impact_wait = 0.8
	if fleeing and city:
		if not city.has_collision_at(WorldOrigin.to_world(global_position)):
			return
		_follow_lane(delta)
	else:
		super._physics_process(delta)
	_label.text = ("LEDGER VAN" if fleeing else "RELAY") + "  %d%%" % maxi(0, ceili(health / 160.0 * 100.0))


func damage(amount: float) -> void:
	health = maxf(0.0, health - maxf(0.0, amount))
	if health <= 0.0:
		fleeing = false
		velocity *= 0.15
		_label.text = "RELAY DISABLED"
		_label.modulate = Color.GRAY
		if not is_in_group("drive_cars"):
			add_to_group("drive_cars")


func _on_area_hit(center: Vector3, radius: float, amount: float) -> void:
	if WorldOrigin.to_world(global_position + Vector3.UP).distance_to(center) < radius + 2.0:
		damage(amount)


func _follow_lane(delta: float) -> void:
	if _path.size() < 2 or _point >= _path.size():
		_choose_lane()
	if _path.size() < 2:
		return
	var target := WorldOrigin.to_local(_path[_point])
	if global_position.distance_to(target) < 7.0:
		_point += 1
		if _point >= _path.size():
			_choose_lane()
		return
	var toward := target - global_position
	var angle := wrapf(atan2(toward.x, toward.z) - heading, -PI, PI)
	var input := HeroInput.new()
	input.stick = Vector2(clampf(-angle * 2.5, -1.0, 1.0), -0.58 if absf(angle) < 0.7 else -0.25)
	_stuck = _stuck + delta if Vector2(velocity.x, velocity.z).length() < 1.0 else 0.0
	if _stuck > 2.0:
		input.stick = Vector2(signf(angle), 0.65)
	if _stuck > 4.0:
		_stuck = 0.0
		_path.clear()
	drive(input, delta)


func _choose_lane() -> void:
	var at := WorldOrigin.to_world(global_position)
	var best := INF
	var chosen := PackedVector3Array()
	var start := 1
	var forward := Vector3(sin(heading), 0, cos(heading))
	for tile: Array in city.traffic_lanes().values():
		for lane: PackedVector3Array in tile[0]:
			for i in lane.size() - 1:
				var point := Geometry3D.get_closest_point_to_segment(at, lane[i], lane[i + 1])
				var direction := (lane[i + 1] - lane[i]).normalized()
				var score := point.distance_to(at) + (1.0 - forward.dot(direction)) * 18.0
				if at.distance_to(lane[-1]) < 9.0:
					score += 100.0  # Prefer a successor over the lane just completed.
				if score < best:
					best = score
					chosen = lane
					start = i + 1
	_path = chosen
	_point = start


## The criminal driver never reports its collisions as the local hero's crimes.
func _hit_people(before: Vector3) -> void:
	if driver:
		super._hit_people(before)
