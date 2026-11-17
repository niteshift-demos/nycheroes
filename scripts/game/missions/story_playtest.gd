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
		JavaScriptBridge.eval("window.nycStoryPilot=false;window.nycStoryState={}")


func _physics_process(delta: float) -> void:
	_clock += delta
	_report -= delta
	if _report <= 0.0:
		_report = 0.25
		_publish()
	if not _enabled or director.hero.frozen or director.active == null:
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
				if step.has("boss"):
					_fly_to(target + Vector3.UP * 2.0, input, hero)
					if offset.length() < 4.0:
						input.fly_toggle_pressed = true
				elif flat.length() < 10:
					input.vertical = -1
					input.attack_held = true
				else:
					_fly_to(target + Vector3.UP * 8, input, hero)
			elif flat.length() < 9.0:
				input.attack_held = fmod(_clock, 0.4) < 0.2
			elif flat.length() > 70.0:
				_fly_to(target + Vector3.UP * 20, input, hero)


func _fly_to(target: Vector3, input: HeroInput, hero: Hero) -> void:
	if hero.mode.name == &"Drive":
		input.interact_pressed = true
		return
	if hero.mode.name != &"Flight":
		input.fly_toggle_pressed = true
		return
	var offset := target - hero.world_position()
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
		frozen = hero.frozen, phone = director.phone_lines, stars = hero.wanted_stars}
	if director.active:
		var target := director.current_target()
		state.target = [target.x, target.y, target.z]
		state.enemies = director.gang.filter(func(t: Thug) -> bool: return is_instance_valid(t) and not t.is_down()).size()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.nycStoryState=" + JSON.stringify(state))
	else:
		var summary := "%s step %d %s %s at %s target %s" % [state.active, state.step, state.objective, state.banner, at.round(), state.get("target", [])]
		if summary != _last_native and int(_clock) % 5 == 0:
			print("[story-playtest] " + summary)
			_last_native = summary
