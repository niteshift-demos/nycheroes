class_name MissionDirector
extends Node
## Per-player objectives and rewards. Only our EncounterDirector spawns the
## mission gang; its existing replication allows any peer to help defeat it.

signal mission_started(id: String)
signal mission_step_changed(id: String, target_world_position: Vector3)
signal mission_finished(id: String, success: bool)

const THUG_BOUNTY := 50
const GIVER_RADIUS := 10.0
## Geographic references have no elevation; allow street grades around them.
const GIVER_HEIGHT_ALLOWANCE := 30.0
const RESULT_SECONDS := 9.0
var story := StoryCampaign.new()
var story_objectives: StoryObjectives
var phone_lines: Array[Dictionary] = []
var phone_seconds := 0.0
var _pending_story := ""

var hero: Hero
var encounters: EncounterDirector
var wallet: Wallet
var wanted: Wanted
## Game blocks startup while loading or choosing a name covers the controls.
var can_progress: Callable
var catalog: Array[Mission] = []
var active: Mission
var last_mission: Mission
var step_index := 0
var remaining := -1.0
var intro_remaining := 0.0
var banner := ""
var banner_remaining := 0.0
var collected: Array[int] = []
var gang: Array[Thug] = []
var _gang_spawned := false
var _inside_givers: Array[String] = []
var _last_target := Vector3.INF


func _ready() -> void:
	add_to_group("mission_director")
	if catalog.is_empty():
		catalog = MissionCatalog.all()
	catalog.append_array(StoryCatalog.all())
	if LaunchOptions.has("story"):
		var chapter := LaunchOptions.get_string("story")
		if chapter == "reset":
			story.reset()
		elif chapter.is_valid_int() and chapter.to_int() >= 1 and chapter.to_int() <= 12:
			_pending_story = "story_%02d" % chapter.to_int()
	Combat.thug_defeated.connect(_on_thug_defeated)
	if wanted:
		wanted.busted.connect(_on_busted)
	if LaunchOptions.has("mission"):
		if not start(LaunchOptions.get_string("mission")):
			push_warning("Unknown mission: " + LaunchOptions.get_string("mission"))

	var navigation := MissionRadar.new()
	navigation.name = "MissionRadar"
	navigation.director = self
	add_child(navigation)
	if LaunchOptions.has("story_playtest"):
		var pilot := StoryPlaytest.new()
		pilot.director = self
		add_child(pilot)

func _process(delta: float) -> void:
	if hero == null or hero.frozen or (can_progress.is_valid() and not can_progress.call()):
		return  # Loading and travel never spend a race's clock.
	if active and hero.mode.name == &"KnockedOut":
		finish(false)
	if not _pending_story.is_empty():
		var id := _pending_story
		_pending_story = ""
		for mission in catalog:
			if mission.id == id:
				# A test jump is session-only; it never erases saved progress.
				start_mission(mission, true)
	advance(delta, hero.world_position())


## Starts a catalog id, replacing no active job. False for unknown/busy.
func start(id: String) -> bool:
	for mission in catalog:
		if mission.id == id:
			return start_mission(mission)
	return false


## Custom definitions use the same path as catalog jobs (also useful to tests).
func start_mission(mission: Mission, preview := false) -> bool:
	if active or mission.steps.is_empty() or (not preview and not story.available(mission)):
		return false
	active = mission
	last_mission = mission
	step_index = 0
	intro_remaining = 5.0
	banner = ""
	banner_remaining = 0.0
	mission_started.emit(mission.id)
	_begin_step()
	phone_lines = mission.calls.duplicate()
	phone_seconds = 8.0
	return true


## Restart the same route and reset its timer, pickups and owned encounter.
func retry() -> bool:
	if active or last_mission == null:
		return false
	return start_mission(last_mission, LaunchOptions.has("story"))


## Offer a new nearby street bounty on demand, without accumulating jobs.
func side_job() -> bool:
	if active or hero == null or encounters == null:
		return false
	var center := hero.world_position()
	var lanes := encounters.city.lanes_near(center, 140.0)
	if lanes.is_empty():
		banner = "No street jobs here. Try near a road."
		banner_remaining = 4.0
		return false
	var lane: PackedVector3Array = lanes.pick_random()
	var position := lane[randi() % lane.size()]
	var job := MissionCatalog.make("side_job", "Neighborhood Watch", 1200,
		"A fresh street bounty. Clear the marked crew; your friends can help.", position)
	job.steps = [Mission.defeat_gang_at(position, randi_range(3, 5), "Clear the neighborhood crew")]
	return start_mission(job)


## Absolute position for radar consumers. INF means no active objective.
func current_target() -> Vector3:
	if active == null:
		return Vector3.INF
	var step := active.steps[step_index]
	if is_instance_valid(story_objectives):
		return story_objectives.target()
	if step.kind == "collect":
		var items: Array = step.items
		for i in items.size():
			if not collected.has(i):
				return items[i]
	if step.kind == "defeat_gang_at":
		for thug in gang:
			if is_instance_valid(thug) and not thug.is_down():
				return WorldOrigin.to_world(thug.global_position)
	return step.position


func objective_text() -> String:
	if active == null:
		return "Gold S: story · Purple: contract · or take a Side job"
	var step := active.steps[step_index]
	var text: String = step.text
	if step.kind == "collect":
		text += "  %d / %d" % [collected.size(), step.items.size()]
	elif step.kind == "defeat_gang_at" and _gang_spawned:
		var down := 0
		for thug in gang:
			if is_instance_valid(thug) and thug.is_down():
				down += 1
		text += "  %d / %d" % [down, int(step.count)]
	if is_instance_valid(story_objectives):
		text += story_objectives.status()
	return text


## Driven by the actual local hero; explicit positions keep the state machine
## deterministic in tests without creating fake city or network services.
func advance(delta: float, position: Vector3) -> void:
	banner_remaining = maxf(0.0, banner_remaining - delta)
	intro_remaining = maxf(0.0, intro_remaining - delta)
	_update_givers(position)
	if active == null:
		return
	if not phone_lines.is_empty():
		phone_seconds -= delta
		if phone_seconds <= 0.0:
			next_call()
		return
	if remaining >= 0.0:
		remaining = maxf(0.0, remaining - delta)
		if remaining <= 0.0:
			finish(false)
			return
	var step := active.steps[step_index]
	var target: Vector3 = step.position
	if is_instance_valid(story_objectives):
		var outcome := story_objectives.advance(delta, position)
		if outcome < 0:
			finish(false)
			return
		if outcome > 0:
			_next_step()
			return
	match String(step.kind):
		"go_to", "reach_in_time":
			if position.distance_to(target) <= float(step.radius):
				_next_step()
		"collect":
			var items: Array = step.items
			for i in items.size():
				if not collected.has(i) and position.distance_to(items[i]) <= float(step.radius):
					collected.append(i)
			if collected.size() == items.size():
				_next_step()
		"defeat_gang_at":
			if not _gang_spawned and encounters and position.distance_to(target) < 100.0 \
					and encounters.city.has_collision_at(target):
				if active.chapter > 0:
					var ground := encounters.city.ground_height_at(target, 5.0)
					if not is_finite(ground) or absf(ground + WorldOrigin.offset.y - target.y) > 20.0:
						return
					target.y = ground + WorldOrigin.offset.y + 0.2
				gang = encounters.spawn_gang(target, int(step.count), Vector3.RIGHT, hero)
				if step.has("boss"):
					gang[0].set_story_variant(int(step.boss))
				_gang_spawned = true
			if _gang_spawned:
				var down := 0
				for thug in gang:
					if not is_instance_valid(thug):
						finish(false)  # Despawned enemies cannot grant a free win.
						return
					if thug.is_down():
						down += 1
				if down == int(step.count):
					_next_step()
	var next_target := current_target()
	if active and next_target.distance_squared_to(_last_target) > 1.0:
		_last_target = next_target
		mission_step_changed.emit(active.id, next_target)


func finish(success: bool) -> void:
	if active == null:
		return
	var finished := active
	active = null  # Clear before emitting or crediting, so completion is once.
	remaining = -1.0
	phone_lines.clear()
	_clear_story_step()
	if success:
		story.complete(finished)
	banner = "MISSION PASSED  " + Wallet.format_cash(finished.reward) if success else "MISSION FAILED"
	banner_remaining = RESULT_SECONDS
	if success and wallet:
		wallet.add(finished.reward, finished.title)
	_cleanup_gang()
	mission_finished.emit(finished.id, success)


## Markers are world-space data: HUDs and radar can share them safely.
func markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if active:
		var step := active.steps[step_index]
		if step.kind == "collect":
			var items: Array = step.items
			for i in items.size():
				if not collected.has(i):
					result.append({position = items[i], label = "CELL", color = Color.GOLD})
		else:
			result.append({position = current_target(), label = "TARGET", color = Color.GOLD})
	else:
		if banner_remaining > 0.0:
			return result  # Distant giver labels must not cross the result banner.
		for mission in available_missions():
			result.append({position = mission.giver, label = mission.title.to_upper(), color = Color.GOLD if mission.chapter > 0 else Color(0.75, 0.5, 1.0)})
	return result


func _update_givers(position: Vector3) -> void:
	for mission in available_missions():
		var horizontal := Vector2(position.x - mission.giver.x, position.z - mission.giver.z)
		var inside := horizontal.length() <= GIVER_RADIUS and absf(position.y - mission.giver.y) <= GIVER_HEIGHT_ALLOWANCE
		if inside and not _inside_givers.has(mission.id):
			_inside_givers.append(mission.id)
			if active == null and banner_remaining <= 0.0:
				start_mission(mission)
		elif not inside:
			_inside_givers.erase(mission.id)


func _begin_step() -> void:
	collected.clear()
	gang.clear()
	_gang_spawned = false
	var step := active.steps[step_index]
	remaining = float(step.get("seconds", -1.0))
	if step.has("call"):
		phone_lines = [step.call]
		phone_seconds = 8.0
	if step.kind in ["drive_to", "steal_car", "chase", "escape_wanted", "protect", "destroy", "fly_through"]:
		story_objectives = StoryObjectives.new()
		story_objectives.director = self
		add_child(story_objectives)
		story_objectives.begin(step)
	_last_target = current_target()
	mission_step_changed.emit(active.id, _last_target)


func _next_step() -> void:
	_clear_story_step()
	# Leave bodies to EncounterDirector after a completed fight.
	gang.clear()
	step_index += 1
	if step_index >= active.steps.size():
		finish(true)
	else:
		_begin_step()


func _cleanup_gang() -> void:
	# Match EncounterDirector's removal path: unregister before the next share,
	# then its normal gang sweep discards the freed members. Retry cannot pile
	# up standing crews; defeated bodies keep their usual lifecycle.
	for thug in gang:
		if is_instance_valid(thug) and not thug.is_down() and not thug.puppet:
			Combat.unregister(thug)
			thug.queue_free()
	gang.clear()
	_gang_spawned = false


func _on_thug_defeated(thug: Thug) -> void:
	# A shared local assist bounty, not a claim about who dealt the last hit.
	if wallet and hero and hero.world_position().distance_to(WorldOrigin.to_world(thug.global_position)) < 120.0:
		wallet.add(THUG_BOUNTY, "Gang takedown assist")


## Arrests cost a small local fine even when no contract is active.
func _on_busted() -> void:
	var on_mission := active != null
	finish(false)
	var fine := mini(1000, ceili(float(wallet.balance) * 0.1)) if wallet else 0
	if wallet:
		wallet.spend(fine)
	if not on_mission:
		banner = "BUSTED  -" + Wallet.format_cash(fine)
		banner_remaining = RESULT_SECONDS


## Only one story giver is visible alongside the replayable city contracts.
func available_missions() -> Array[Mission]:
	var result: Array[Mission] = []
	for mission in catalog:
		if story.available(mission):
			result.append(mission)
	return result


func next_call() -> void:
	if not phone_lines.is_empty():
		phone_lines.pop_front()
	phone_seconds = 8.0


func skip_calls() -> void:
	phone_lines.clear()


func _clear_story_step() -> void:
	if is_instance_valid(story_objectives):
		if story_objectives.step.kind == "protect":
			_cleanup_gang()
		# Free immediately: a late damage callback must not hit an old objective.
		if is_instance_valid(story_objectives.car) and story_objectives.car.driver:
			story_objectives.car.reparent(get_parent(), true)
		story_objectives.free()
	story_objectives = null
