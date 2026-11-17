class_name PoliceCar
extends DriveVehicle
## Patrol physics uses DriveVehicle unchanged; the pursuit supplies plain
## HeroInput at 5 Hz. Copies interpolate world state and never simulate AI.

var net_id := 0
var suspect_id := 0
var run_by := 0
var roadblock := false
var deployed := false
var controls := HeroInput.new()
var lane: TrafficLanes.Lane
var lane_distance := 0.0
var last_known := Vector3.ZERO
var stuck_time := 0.0
var reverse_time := 0.0
var _snapshot_at := Vector3.ZERO
var _snapshot_heading := 0.0
var _siren: LoopVoice
var _radar_wait := 0.0


func _ready() -> void:
	paint = PoliceLivery.PAINT
	ai_controlled = not deployed and not roadblock
	super._ready()
	if puppet:
		add_to_group("floating")
	add_to_group("police_cars")


func _physics_process(delta: float) -> void:
	if puppet:
		global_position = global_position.lerp(WorldOrigin.to_local(_snapshot_at), 1.0 - exp(-delta * 16.0))
		heading = lerp_angle(heading, _snapshot_heading, 1.0 - exp(-delta * 16.0))
		rotation.y = heading
		_draw()
	elif ai_controlled:
		drive(controls, delta)
	else:
		super._physics_process(delta)
	_radar_wait -= delta
	if _radar_wait <= 0.0 and is_in_group("police_cars"):
		_radar_wait = 0.4
		var radar := get_tree().get_first_node_in_group("radar") as Radar
		if radar:
			var color := Color("57a5ff") if (Time.get_ticks_msec() / 400) % 2 == 0 else Color("ff5967")
			radar.add_node_blip(StringName("patrol/%d/%d" % [run_by, net_id]), self, &"police", color)
	_update_siren(delta)


func _update_siren(delta: float) -> void:
	if _siren == null:
		var files := SoundBank.streams(&"siren")
		if files.is_empty() or GameAudio.off():
			return
		var player := AudioStreamPlayer3D.new()
		# Duplicate only loop metadata: never change the ambient one-shot sirens.
		var stream := files[net_id % files.size()].duplicate() as AudioStreamOggVorbis
		stream.loop = true
		player.stream = stream
		player.bus = &"Ambience"
		player.unit_size = 25.0
		player.max_distance = 350.0
		player.max_db = -19.0
		player.attenuation_filter_db = 0.0
		add_child(player)
		_siren = LoopVoice.new(player, -19.0, 1.0)
	_siren.target = 1.0 if driver == null and not deployed and visible and GameAudio.can_play() \
		and global_position.distance_squared_to(GameAudio.listener()) < 350.0 * 350.0 else 0.0
	_siren.update(delta, 5.0)


## A complete description also acts as a snapshot, bounded to six cars per
## suspect. Repeated full fleets recover from packet loss and late joins.
func description() -> Array:
	return [net_id, WorldOrigin.to_world(global_position), heading, velocity,
		suspect_id, roadblock, deployed, ai_controlled, driver != null]


func follow(data: Array) -> void:
	_snapshot_at = data[1]
	_snapshot_heading = float(data[2])
	velocity = data[3]
	suspect_id = int(data[4])
	roadblock = bool(data[5])
	deployed = bool(data[6])
	ai_controlled = bool(data[7])
	# Occupied cars already draw from the driver's PlayerSync state.
	visible = not bool(data[8])


## Driver snapshots take over a stolen car. Its abandoned body then follows
## ordinary driving lifetime rules, so theft cannot fill the police fleet.
func abandon_pursuit() -> void:
	ai_controlled = false
	deployed = true
	remove_from_group("police_cars")
	var radar := get_tree().get_first_node_in_group("radar") as Radar
	if radar:
		radar.remove_blip(StringName("patrol/%d/%d" % [run_by, net_id]))
