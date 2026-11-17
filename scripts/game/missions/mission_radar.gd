class_name MissionRadar
extends Node
## Adapts local mission state to Radar without teaching the mission state
## machine about map controls. Own IDs keep other map users' blips intact.

const OBJECTIVE_ID := &"mission/objective"
var director: MissionDirector
var radar: Radar
var _owned: Array[StringName] = []
var _enemy_ids: Array[StringName] = []


func _ready() -> void:
	director.mission_started.connect(func(_id: String) -> void: _clear_blips())
	director.mission_step_changed.connect(_step_changed)
	director.mission_finished.connect(func(_id: String, _success: bool) -> void:
		if is_instance_valid(radar):
			_clear_blips()
			radar.clear_waypoint()
			_show_givers())
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Also handles a radar appearing after the mission node at scene startup.
func refresh() -> void:
	if not is_instance_valid(radar):
		radar = get_tree().get_first_node_in_group("radar") as Radar
		if radar == null:
			return
		_owned.clear()
		_enemy_ids.clear()
		if director.active:
			_step_changed(director.active.id, director.current_target())
		else:
			_show_givers()
	if director.active == null:
		if _owned.is_empty():
			_show_givers()
		return
	var position := director.current_target()
	if radar.blips.has(OBJECTIVE_ID):
		radar.update_blip(OBJECTIVE_ID, position)
	var standing: Array[StringName] = []
	if director.active.id == "side_job":
		for thug in director.gang:
			if not is_instance_valid(thug) or thug.is_down():
				continue
			var id := StringName("mission/enemy/%d" % thug.get_instance_id())
			standing.append(id)
			if not _enemy_ids.has(id):
				radar.add_node_blip(id, thug, &"enemy", GameHud.MARKER_COLOR)
				_owned.append(id)
	for id in _enemy_ids:
		if not standing.has(id):
			radar.remove_blip(id)
			_owned.erase(id)
	_enemy_ids = standing


func _step_changed(_id: String, position: Vector3) -> void:
	if not is_instance_valid(radar):
		return
	# Keep crew blips across moving-target updates within one fight.
	for id in _owned.duplicate():
		if String(id).begins_with("mission/giver/"):
			radar.remove_blip(id)
			_owned.erase(id)
	radar.add_blip(OBJECTIVE_ID, position, &"mission", Color.YELLOW)
	if not _owned.has(OBJECTIVE_ID):
		_owned.append(OBJECTIVE_ID)
	radar.set_waypoint(position)


func _show_givers() -> void:
	for mission in director.catalog:
		var id := StringName("mission/giver/" + mission.id)
		radar.add_blip(id, mission.giver, &"mission", Color.YELLOW)
		if not _owned.has(id):
			_owned.append(id)


func _clear_blips() -> void:
	if is_instance_valid(radar):
		for id in _owned:
			radar.remove_blip(id)
	_owned.clear()
	_enemy_ids.clear()


func _exit_tree() -> void:
	_clear_blips()
