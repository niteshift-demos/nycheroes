class_name StoryPlaytest
extends Node
## Opt-in browser playtest pilot (?story_playtest=1). Drives ordinary HeroInput
## only: never teleports, deals damage, changes health or advances objectives.
## window.nycStoryPilot toggles it; window.nycStoryState is read-only telemetry.

var director: MissionDirector
var _clock := 0.0
var _report := 0.0
var _enabled := false
var _last_native := ""


func _ready() -> void:
	# Software-rendered QA can draw one frame per second. Preserve elapsed
	# physics time instead of Godot capping each frame to eight ticks.
	Engine.max_physics_steps_per_frame = 120
	process_physics_priority = -5  # After keyboard, before Hero consumes input.
	if OS.has_feature("web"):
		# Keep full-size UI while making software-rendered QA practical.
		get_tree().root.scaling_3d_scale = 0.25
		# The loading overlay covers the city. Avoid software-rendering every
		# partially built tile; restore the real scene before any mission starts.
		get_tree().root.disable_3d = true
		director.encounters.city.initial_load_finished.connect(func(_seconds: float) -> void:
			get_tree().root.disable_3d = false, CONNECT_ONE_SHOT)
		JavaScriptBridge.eval("window.nycStoryPilot=false;window.nycStoryState={}")


func _physics_process(delta: float) -> void:
	_clock += delta
	_report -= delta
	if _report <= 0.0:
		_report = 0.25
		_publish()
	if director.hero.frozen:
		return
	if OS.has_feature("web"):
		var command: Variant = JavaScriptBridge.eval("JSON.stringify(window.nycStoryInput || null)")
		var controls: Variant = JSON.parse_string(str(command))
		if controls is Dictionary:
			_apply_input(controls, director.hero.input)
			return
	if not _enabled or director.active == null:
		return
	var hero := director.hero
	var input := hero.input
	input.clear()
	if not director.phone_lines.is_empty():
		return
	var step := director.active.steps[director.step_index]
	var target := director.current_target()
	var to_target := target - hero.world_position()
	var flat := Vector3(to_target.x, 0, to_target.z)
	var camera := hero.get_parent().get_node_or_null("HeroCamera") as ThirdPersonCamera
	if camera and flat.length() > 2.0:
		camera.yaw = lerp_angle(camera.yaw, atan2(-flat.x, -flat.z), 1.0 - exp(-delta * 3.0))
		camera.pitch = -0.16
	var drive := hero.get_mode(&"Drive") as DriveMode
	match String(step.kind):
		"fly_through", "collect", "go_to", "reach_in_time":
			_fly_to(target, input, hero)
		"steal_car":
			if hero.mode.name == &"Flight":
				if flat.length() < 3.0:
					input.vertical = -0.3
				else:
					_fly_to(target + Vector3.UP, input, hero)
			elif flat.length() < 3.2 and absf(to_target.y) < 3:
				input.interact_pressed = true
			else:
				input.move = flat.normalized() * minf(1, flat.length() / 6)
				input.aim = flat.normalized()
		"drive_to", "chase":
			if hero.mode.name == &"Drive" and is_instance_valid(drive.car):
				var angle := wrapf(atan2(flat.x, flat.z) - drive.car.heading, -PI, PI)
				input.stick = Vector2(clampf(-angle * 2.0, -1, 1), -1.0 if absf(angle) < 0.8 else -0.3)
			else:
				_fly_to(target + Vector3.UP * 4, input, hero)
				if step.kind == "chase" and flat.length() > 7.0:
					input.stick.y = -1.0  # Match a fleeing van before slowing to punch.
				if flat.length() < 7:
					input.attack_held = fmod(_clock, 0.5) < 0.25
		"escape_wanted":
			if hero.mode.name == &"Drive":
				input.interact_pressed = true
			else:
				_fly_to(Vector3(hero.world_position().x, 380, hero.world_position().z), input, hero)
		"defeat_gang_at", "destroy", "protect":
			if step.kind == "protect" and not director.gang.is_empty():
				for thug in director.gang:
					if is_instance_valid(thug) and not thug.is_down():
						target = WorldOrigin.to_world(thug.global_position)
						break
			var offset := target - hero.world_position()
			flat = Vector3(offset.x, 0, offset.z)
			input.aim = flat.normalized()
			input.move = flat.normalized() * clampf((flat.length() - 1.7) / 4.0, 0, 1)
			if hero.mode.name == &"Drive":
				input.interact_pressed = true
			elif hero.mode.name == &"Flight":
				if step.has("boss") or step.kind == "destroy":
					_fly_to(target + Vector3.UP * 2.0, input, hero)
					if offset.length() < 4.0:
						input.fly_toggle_pressed = true
				elif flat.length() < 10:
					input.vertical = -1
					input.attack_held = true
				else:
					_fly_to(target + Vector3.UP * 8, input, hero)
			elif offset.y > 3.0:
				_fly_to(target + Vector3.UP * 2.0, input, hero)
			elif flat.length() < (3.5 if step.kind == "destroy" else 9.0):
				input.attack_held = fmod(_clock, 0.4) < 0.2
			elif flat.length() > (12.0 if step.kind == "destroy" else 70.0):
				_fly_to(target + Vector3.UP * 20, input, hero)


## QA controls still pass through the same per-tick input as keyboard/gamepad.
func _apply_input(controls: Dictionary, input: HeroInput) -> void:
	input.clear()
	for key in ["jump_held", "sprint_held", "web_held", "attack_held", "fly_toggle_pressed", "interact_pressed"]:
		input.set(key, bool(controls.get(key, false)))
	if controls.has("driving"):
		input.interact_pressed = bool(controls.driving) != (director.hero.mode.name == &"Drive")
	if controls.has("flight"):
		input.fly_toggle_pressed = bool(controls.flight) != (director.hero.mode.name == &"Flight")
	input.vertical = clampf(float(controls.get("vertical", 0)), -1, 1)
	var stick: Array = controls.get("stick", [0, 0])
	input.stick = Vector2(float(stick[0]), float(stick[1])).limit_length()
	var move: Array = controls.get("move", [0, 0, 0])
	input.move = Vector3(float(move[0]), 0, float(move[2])).limit_length()
	var aim: Array = controls.get("aim", [0, 0, -1])
	input.aim = Vector3(float(aim[0]), float(aim[1]), float(aim[2])).normalized()
	if controls.has("toward"):
		var waypoint: Array = controls.toward
		var offset := Vector3(float(waypoint[0]), float(waypoint[1]), float(waypoint[2])) - director.hero.world_position()
		input.aim = offset.normalized()
		input.stick.y = -minf(0.7, offset.length() / 30.0)
	if controls.has("aim") or controls.has("toward"):
		var camera := director.hero.get_parent().get_node_or_null("HeroCamera") as ThirdPersonCamera
		if camera:
			camera.yaw = atan2(-input.aim.x, -input.aim.z)
			camera.pitch = clampf(asin(input.aim.y), -1.4, 1.2)


func _fly_to(target: Vector3, input: HeroInput, hero: Hero) -> void:
	if hero.mode.name == &"Drive":
		input.interact_pressed = true
		return
	if hero.mode.name != &"Flight":
		input.fly_toggle_pressed = true
		return
	var offset := target - hero.world_position()
	if target.y < 60.0 and Vector2(offset.x, offset.z).length() > 30.0 and offset.y > -60.0:
		offset.y += 45.0  # Cross low park buildings before approaching a street target.
		if hero.world_position().y < target.y + 35.0:
			offset.x = 0.0
			offset.z = 0.0
	# Clear a roof horizontally before a steep descent to a street objective.
	if offset.y < -60.0 and Vector2(offset.x, offset.z).length() > 12.0:
		offset.y = 0.0
	input.aim = offset.normalized()
	input.stick.y = -clampf(offset.length() / 40.0, 0.0, 1.0)
	input.sprint_held = offset.length() > 200.0


func _publish() -> void:
	if OS.has_feature("web"):
		_enabled = bool(JavaScriptBridge.eval("window.nycStoryPilot === true"))
	else:
		_enabled = true
	var hero := director.hero
	var at := hero.world_position()
	var state := {active = director.active.id if director.active else "", step = director.step_index,
		objective = director.objective_text(), mode = String(hero.mode.name), position = [at.x, at.y, at.z],
		completed = director.story.completed, banner = director.banner, health = hero.health,
		frozen = hero.frozen, phone = director.phone_lines, stars = hero.wanted_stars,
		cash = director.wallet.balance if director.wallet else 0, clock = _clock,
		room = Net.room_code, peers = Net.peers(), remote = []}
	var sync := hero.get_parent().get_node_or_null("Players") as PlayerSync
	if sync:
		for copy: Hero in sync.remote_heroes.values():
			var ride := (copy.get_mode(&"Drive") as DriveMode).car
			var point := copy.world_position()
			state.remote.append({id = copy.remote_id, mode = String(copy.mode.name), stars = copy.wanted_stars,
				position = [point.x, point.y, point.z], tag = (copy.get_node("NameTag") as Label3D).text,
				car = {model = ride.model, paint = ride.paint, health = ride.health} if is_instance_valid(ride) else {}})
	state.thugs = []
	for thug in Combat.thugs:
		var point := WorldOrigin.to_world(thug.global_position)
		state.thugs.append({position = [point.x, point.y, point.z], health = thug.health,
			puppet = thug.puppet, boss = thug.story_variant, police = thug is PoliceOfficer})
	state.police_cars = []
	for patrol: PoliceCar in get_tree().get_nodes_in_group("police_cars"):
		var point := WorldOrigin.to_world(patrol.global_position)
		state.police_cars.append({position = [point.x, point.y, point.z], health = patrol.health, puppet = patrol.puppet})
	var ride := (hero.get_mode(&"Drive") as DriveMode).car
	state.car = {model = ride.model, paint = ride.paint, health = ride.health, heading = ride.heading} if is_instance_valid(ride) else {}
	state.vehicles = []
	for vehicle: DriveVehicle in get_tree().get_nodes_in_group("drive_cars"):
		var point := WorldOrigin.to_world(vehicle.global_position)
		state.vehicles.append({position = [point.x, point.y, point.z], model = vehicle.model,
			paint = vehicle.paint, health = vehicle.health, exploded = vehicle.exploded})
	if director.active:
		var target := director.current_target()
		state.target = [target.x, target.y, target.z]
		var standing := 0
		for thug in director.gang:
			if is_instance_valid(thug) and not thug.is_down():
				standing += 1
		state.enemies = standing
		if is_instance_valid(director.story_objectives):
			var objective := director.story_objectives
			var relays: Array[Dictionary] = []
			for car in objective.targets:
				if is_instance_valid(car):
					var location := WorldOrigin.to_world(car.global_position)
					relays.append({position = [location.x, location.y, location.z], health = car.relay_health})
			state.relays = relays
			if objective.step.kind == "protect":
				state.witness_health = objective.witness_health
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.nycStoryState=" + JSON.stringify(state))
	else:
		var summary := "%s step %d %s %s %s at %s target %s" % [state.active, state.step, state.mode, state.objective, state.banner, at.round(), state.get("target", [])]
		if summary != _last_native and int(_clock) % 5 == 0:
			print("[story-playtest] " + summary)
			_last_native = summary
