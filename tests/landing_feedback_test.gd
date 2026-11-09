extends Node
## Headless check of hard-landing feedback in the real city (LandingIndicator,
## the camera's landing dip, Settings.reduce_motion()): a small hop shows
## nothing; a short super jump lands hard (readout, gauge while falling, the
## camera dips) but doesn't slam; a full super jump slams (readout with the
## blast and the thugs it hurled, gauge past the slam tick); with "Reduce
## camera motion" on, the same slam reads out but the camera keeps still; a
## dive attack from a low hop still slams and says so. Drives the hero only
## through HeroInput, like a player. Exits non-zero on any failed check.
## Run: godot --headless --path . res://tests/landing_feedback_test.tscn
##      [-- --tiles=DIR | --tiles_url=URL]

const AVENUE := Vector3(0.485, 0.0, -0.875)
## Start of a long stretch of 6th Avenue with nothing in the way (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _camera: ThirdPersonCamera
var _indicator: LandingIndicator
var _steps: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _failures := 0
## What each step saw: the most the gauge, the dip and the shake reached.
var _saw_gauge := false
var _max_dip := 0.0
var _max_shake := 0.0
var _gauge_max_speed := 0.0
var _grounded_for := 0.0


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_camera = _world.get_node("HeroCamera")
	_indicator = _world.get_node("HUD/GameHud/LandingIndicator")
	Settings.set_value("reduce_motion", false)
	process_physics_priority = -20
	_steps = [
		_step("wait for the city to load", 60.0, Callable(), func() -> bool:
			return not _hero.frozen and _city.pending_count() == 0, Callable()),
		_step("go to an open avenue", 1.0, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				_teleport(OPEN_AVENUE), Callable(), Callable()),
		_step("small hop", 2.0, func(i: HeroInput, t: float) -> void: i.jump_held = t < 0.1,
			_landed_after(0.3), func() -> void:
				_check(_indicator.last_tier == LandingIndicator.Tier.NONE, "a hop shows no readout")
				_check(not _saw_gauge, "a hop shows no gauge")
				_check(_max_dip == 0.0, "a hop doesn't dip the camera")),
		_step("short super jump (hard landing)", 6.0, func(i: HeroInput, t: float) -> void:
			i.jump_held = t < 0.21,
			_landed_after(0.6), func() -> void:
				var screen := _indicator.get_viewport_rect().size
				_check(_indicator.size == screen and screen.x > 0.0, "the indicator covers the screen (%s of %s)" % [_indicator.size, screen])
				_check(_indicator.last_tier == LandingIndicator.Tier.HARD,
					"lands hard, not a slam (%s, %.1f m/s)" % [_indicator.readout_text(), _indicator.last_impact_speed])
				_check(_indicator.readout_visible() and _indicator.readout_text().begins_with("HARD LANDING"),
					"readout: %s" % _indicator.readout_text())
				_check(_saw_gauge, "the gauge showed while falling")
				_check(_max_dip > 0.0, "the camera dipped (%.2f m)" % _max_dip)),
		_step("settle", 2.5, Callable(), Callable(), func() -> void:
			_check(not _indicator.readout_visible(), "the readout fades")),
		_step("full super jump (slam)", 10.0, func(i: HeroInput, t: float) -> void:
			if t == 0.0:
				_spawn_gang(_hero.world_position() + AVENUE * 3.0, 3)
			i.jump_held = t < 1.4,
			_landed_after(1.6), func() -> void:
				_check(_indicator.last_tier == LandingIndicator.Tier.SLAM, "slams (%.1f m/s)" % _indicator.last_impact_speed)
				_check(_gauge_max_speed >= Hero.SLAM_SPEED, "the gauge went past the slam tick (%.1f m/s)" % _gauge_max_speed)
				_check(_indicator.readout_text().contains("blast"), "readout: %s" % _indicator.readout_text())
				_check(_max_dip > 0.15 and _max_dip <= ThirdPersonCamera.DIP_MAX + 0.001, "a deeper dip, still small (%.2f m)" % _max_dip)
				_check(_max_shake > 0.0, "a slam shakes the camera")),
		_step("settle again", 2.5, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				Settings.set_value("reduce_motion", true), Callable(), Callable()),
		_step("slam with reduced motion", 10.0, func(i: HeroInput, t: float) -> void:
			i.jump_held = t < 1.4,
			_landed_after(1.6), func() -> void:
				_check(_indicator.last_tier == LandingIndicator.Tier.SLAM, "still slams")
				_check(_indicator.readout_visible(), "still reads out: %s" % _indicator.readout_text())
				_check(_max_dip == 0.0 and _max_shake == 0.0, "the camera keeps still (dip %.2f, shake %.2f)" % [_max_dip, _max_shake])),
		_step("settle once more", 2.5, func(_i: HeroInput, t: float) -> void:
			if t == 0.0:
				Settings.set_value("reduce_motion", false), Callable(), Callable()),
		_step("hop and dive attack", 6.0, func(i: HeroInput, t: float) -> void:
			i.jump_held = t < 0.1
			i.aim = (AVENUE * 0.3 - Vector3.UP).normalized()
			i.attack_held = t > 0.35 and t < 0.45,
			_landed_after(0.6), func() -> void:
				_check(_indicator.last_tier == LandingIndicator.Tier.SLAM, "a dive always slams")
				_check(_indicator.readout_text().begins_with("DIVE SLAM"), "readout: %s" % _indicator.readout_text())),
	]


func _physics_process(delta: float) -> void:
	if _index < 0:
		_index = 0
	var step := _steps[_index]
	_hero.input.clear()
	if step.apply.is_valid():
		step.apply.call(_hero.input, _time)
	_time += delta
	var finished: bool = _time >= step.seconds or (step.until.is_valid() and step.until.call())
	if not finished:
		return
	if step.check.is_valid():
		step.check.call()
	print("%-34s %5.1fs  tier %d  impact %5.1f  gauge %-5s max %5.1f  dip %.2f  shake %.2f  %s" % [
		step.name, _time, _indicator.last_tier, _indicator.last_impact_speed, _saw_gauge, _gauge_max_speed,
		_max_dip, _max_shake, _indicator.readout_text()])
	_index += 1
	_time = 0.0
	_saw_gauge = false
	_max_dip = 0.0
	_max_shake = 0.0
	_gauge_max_speed = 0.0
	_indicator.last_tier = LandingIndicator.Tier.NONE
	if _index >= _steps.size():
		print("FAILED: %d check(s)" % _failures if _failures else "PASSED")
		get_tree().quit(1 if _failures else 0)


func _process(_delta: float) -> void:
	if _indicator.gauge_visible():
		_saw_gauge = true
		_gauge_max_speed = maxf(_gauge_max_speed, _indicator.fall_speed())
	_max_dip = maxf(_max_dip, _camera.dip_offset())
	_max_shake = maxf(_max_shake, _camera._shake)


func _step(step_name: String, seconds: float, apply: Callable, until: Callable, check: Callable) -> Dictionary:
	return {name = step_name, seconds = seconds, apply = apply, until = until, check = check}


## Done once the hero has been back on its feet for a quarter second (for
## the camera's dip to show), after at least `after` seconds in the step.
func _landed_after(after: float) -> Callable:
	return func() -> bool:
		if _time <= after or not _hero.is_on_floor() or _hero.mode.name != &"OnFoot":
			_grounded_for = 0.0
			return false
		_grounded_for += get_physics_process_delta_time()
		return _grounded_for >= 0.25


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _spawn_gang(world_center: Vector3, count: int) -> void:
	for k in count:
		var thug: Thug = THUG_SCENE.instantiate()
		add_child(thug)
		var spot := world_center + Vector3(AVENUE.z, 0.0, -AVENUE.x) * (k - (count - 1) * 0.5) * 1.6
		spot.y = _hero.world_position().y  # the same street as the hero
		var ground := _city.ground_height_at(spot, 6.0)
		if not is_nan(ground):
			spot.y = ground
		thug.global_position = WorldOrigin.to_local(spot) + Vector3.UP * 0.2
		thug.setup(_hero, k, TAU * k / count)
