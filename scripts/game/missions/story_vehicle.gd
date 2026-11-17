class_name StoryVehicle
extends DriveVehicle
## Mission-owned physical car. AI follows loaded traffic polylines using
## plain HeroInput; punches/slams and relative-speed impacts damage its relay.

## Separate from chassis damage so the crash system can own vehicle health.
var relay_health := 160.0
var fleeing := false
var city: CityStreamer
var _path := PackedVector3Array()
var _point := 1
var recovery := AiRecovery.new()
var _label: Label3D


func _ready() -> void:
	ai_controlled = fleeing
	super._ready()
	_label = Label3D.new()
	_label.text = "LEDGER VAN" if fleeing else "RELAY"
	_label.font_size = 40
	_label.modulate = Color.GOLD
	_label.position.y = 3.4
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _physics_process(delta: float) -> void:
	if relay_health <= 0.0 or driver:
		super._physics_process(delta)
		return
	if fleeing and city:
		if not city.has_collision_at(WorldOrigin.to_world(global_position)):
			return
		_follow_lane(delta)
	else:
		super._physics_process(delta)
	_label.text = ("LEDGER VAN" if fleeing else "RELAY") + "  %d%%" % maxi(0, ceili(relay_health / 160.0 * 100.0))


## The shared crash/punch/blast path owns all damage. A reinforced chassis
## converts the normal 100 health into 160 mission relay health.
func take_hit(amount: float, push: Vector3, blame_hero := true) -> void:
	super.take_hit(amount * 0.625, push, blame_hero)
	relay_health = maxf(0.0, relay_health - maxf(0.0, amount))
	if health <= 0.0 or exploded:
		relay_health = 0.0
	if relay_health <= 0.0:
		fleeing = false
		ai_controlled = false
		velocity *= 0.15
		_label.text = "RELAY DISABLED"
		_label.modulate = Color.GRAY


## Explicit relay damage also goes through the shared chassis path.
func damage(amount: float) -> void:
	take_hit(amount, Vector3.ZERO, false)


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
	if recovery.advance(WorldOrigin.to_world(global_position), delta, true, angle):
		_choose_lane(true)
	if recovery.reverse_time > 0.0:
		input.stick = Vector2(recovery.turn, 0.8)
	drive(input, delta)


func _choose_lane(recovering := false) -> void:
	var at := WorldOrigin.to_world(global_position)
	var best := INF
	var chosen := PackedVector3Array()
	var start := 1
	var forward := Vector3(sin(heading), 0, cos(heading))
	for tile: Array in city.traffic_lanes().values():
		for lane: PackedVector3Array in tile[0]:
			for i in lane.size() - 1:
				var point := Geometry3D.get_closest_point_to_segment(at, lane[i], lane[i + 1])
				if point.distance_squared_to(at) > 100.0 * 100.0:
					continue
				var direction := (lane[i + 1] - lane[i]).normalized()
				var score := point.distance_to(at) + (1.0 - forward.dot(direction)) * 18.0
				if recovering and lane == _path:
					score += 60.0
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
