extends Node
## Browser presentation fixture, excluded from normal exports. Runs the real
## world and real mission/arrest APIs; holds transient results for screenshots.
## F5: foot/resume; F6: wanted mission car; F7: passed; F8: busted; F9: knockout.
## F2: boss label, F3: explosion; ?hud_case= also selects the initial case.

var _game: Game
var _ready_for_checks := false
var _telemetry := 0.0
var _drive_lane: TrafficLanes.Lane
var _drive_distance := 0.0
var _drive_recovery := AiRecovery.new()
var _chase_elapsed := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -5
	_run.call_deferred()


func _run() -> void:
	# Software-rendered QA needs no 3-D frames while tiles are being assembled.
	# Restore normal rendering before the title, any input, or capture.
	RenderingServer.set_render_loop_enabled(false)
	_game = load("res://scenes/world.tscn").instantiate()
	# The fixture keeps telemetry/input alive when paused, but the real game
	# must inherit the ordinary pause behavior, not this node's ALWAYS mode.
	_game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_game)
	while is_instance_valid(_game._loading) or _game.hero.frozen:
		await get_tree().process_frame
	RenderingServer.set_render_loop_enabled(true)
	while _game.onboarding and _game.onboarding.title_pending:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	_ready_for_checks = true
	_scenario(LaunchOptions.get_string("hud_case", "foot"))
	Engine.max_physics_steps_per_frame = 120


func _input(event: InputEvent) -> void:
	if not _ready_for_checks or not event is InputEventKey or not event.pressed or event.echo:
		return
	var cases := {KEY_F2: "boss", KEY_F3: "explosion", KEY_F5: "foot", KEY_F6: "car", KEY_F7: "passed", KEY_F8: "busted", KEY_F9: "knocked", KEY_F10: "shop", KEY_F4: "desktop"}
	if cases.has(event.keycode):
		get_viewport().set_input_as_handled()
		_scenario(cases[event.keycode])


func _scenario(scenario: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	_chase_elapsed = -1.0
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.nycDrivePilot=false")
	var display := _game.hud.get_node("GameHud") as GameHud
	var wanted := _game.get_node("Wanted") as Wanted
	if scenario in ["boss", "explosion", "call", "foot"]:
		wanted.set_stars(0)
		wanted._clear_response()
		wanted.pursuit.advance(0.0)
	if scenario in ["boss", "explosion"]:
		_game.hero.set_mode(&"OnFoot")
	(_game.hud.get_node("DebugLabel") as DebugHud).visible = scenario == "chase" and LaunchOptions.has("stats")
	match scenario:
		"chase":
			_scenario("car")
			_seed_chase_car(wanted)
			_chase_elapsed = 0.0
			# Fill the ordinary response through its actual spawn checks. The
			# optional pilot below supplies only steering/throttle, never travel.
			for attempt in 10:
				wanted._spawn_response()
			for attempt in 60:
				if wanted.pursuit.cars.size() >= PolicePursuit.cap(5):
					break
				wanted.pursuit._spawn_patrol(false)
			JavaScriptBridge.eval("window.nycDrivePilot=true")
		"call":
			_game.missions.finish(false)
			_game.missions.start_mission(StoryCatalog.all()[0], true)
			display.banner_remaining = 0.0
		"boss":
			_game.missions.finish(false)
			display.banner_remaining = 0.0
			_game.missions.banner_remaining = 0.0
			var forward := -_game.hero_camera.camera.global_basis.z
			forward.y = 0.0
			var at := _game.hero.world_position() + forward.normalized() * 22.0
			var crew := _game.encounters.spawn_gang(at, 1, Vector3.RIGHT, _game.hero)
			crew[0].set_story_variant(4)
			crew[0].set_physics_process(false)
			print("[hud-check] boss tag=" + crew[0].story_tag())
		"explosion":
			_game.missions.finish(false)
			display.banner_remaining = 0.0
			_game.missions.banner_remaining = 0.0
			var forward := -_game.hero_camera.camera.global_basis.z
			forward.y = 0.0
			var car := DriveVehicle.new()
			car.traffic = _game.get_node("Traffic") as Traffic
			_game.add_child(car)
			car.global_position = _game.hero.global_position + forward.normalized() * 14.0
			# Slow only this visual fixture: a software-rendered frame can take
			# longer than a fireball's whole life. Damage and countdown stay real.
			Engine.time_scale = 0.1
			car.take_hit(1000.0, Vector3.ZERO, false)
			await car.detonated
			get_tree().paused = true
			print("[hud-check] explosion held; burnt=" + str(car.exploded))
		"desktop":
			# Reuse the loaded city to compare HUD layouts without another cold GPU compile.
			LaunchOptions._options["touch"] = "0"
			var controls := _game._touch_controls
			if controls:
				controls._release_all()
				controls.queue_free()
			_game._touch_controls = null
			display.touch_controls = null
			_game.radar.touch_controls = null
			get_window().content_scale_factor = 1.0
			Device.set_page_touch_mode(false)
		"foot":
			display.banner_remaining = 0.0
			_game.missions.banner_remaining = 0.0
			_game.hero.health = _game.hero.max_health
			if _game.hero.mode.name == &"KnockedOut":
				_game.hero.set_mode(&"OnFoot")
		"car":
			_game.missions.start("broadway_dash")
			var drive := _game.hero.get_mode(&"Drive") as DriveMode
			if _game.hero.mode != drive:
				_game.hero.set_mode(&"OnFoot")
				_game.hero.health = _game.hero.max_health
				if not drive.can_take_car():
					var starter := DriveVehicle.new()
					starter.heading = _game.hero.facing + PI
					starter.traffic = _game.get_node("Traffic") as Traffic
					_game.add_child(starter)
					starter.global_position = _game.hero.global_position + Vector3.RIGHT * 2.5
				drive.interact()
			wanted.set_stars(5)
			print("[hud-check] car mode=" + str(_game.hero.mode.name))
		"shop":
			_game.pause_menu.close(false)
			_game.shops.active = _game.shops.locations[0]
			_game.shops.entered.emit(_game.shops.active)
		"passed":
			_game.missions.start("rooftop_courier")
			_game.missions.finish(true)
			print("[hud-check] mission finished; cash=" + str(_game.wallet.balance))
		"busted":
			_game.hero.health = _game.hero.max_health
			wanted.set_stars(2)
			_game.hero.take_hit(1000.0, Vector3.ZERO)
			print("[hud-check] arrest event; stars=" + str(_game.hero.wanted_stars))
		"knocked":
			_game.hero.health = _game.hero.max_health
			wanted.set_stars(0)
			_game.hero.set_mode(&"OnFoot")
			_game.hero.take_hit(1000.0, Vector3.ZERO)
			print("[hud-check] knockout event")
	if scenario in ["passed", "busted", "knocked"]:
		await get_tree().process_frame
		await get_tree().process_frame
		print("[hud-check] banner=" + display.banner_title)
		get_tree().paused = true
	print("[hud-check] ready " + scenario)


func _process(delta: float) -> void:
	if not _ready_for_checks or not OS.has_feature("web"):
		return
	_telemetry -= delta
	if _telemetry > 0.0:
		return
	_telemetry = 0.5
	var action := str(JavaScriptBridge.eval("window.nycPolishAction || ''"))
	if action in ["call", "car", "chase", "foot", "boss", "explosion"]:
		JavaScriptBridge.eval("window.nycPolishAction=''")
		_scenario(action)
	var officers := 0
	for thug in Combat.thugs:
		if thug is PoliceOfficer and not thug.is_down():
			officers += 1
	var state := {mode = String(_game.hero.mode.name), stars = _game.hero.wanted_stars,
		officers = officers, patrols = get_tree().get_node_count_in_group("police_cars"),
		paused = get_tree().paused, nodes = get_tree().get_node_count(),
		position = _game.hero.world_position(), phone = _game.missions.phone_lines.size()}
	state.blasts = Combat.effects._explosions.size() if Combat.effects else 0
	state.chase_seconds = _chase_elapsed
	state.speed = _game.hero.velocity.length()
	var rectangles := {}
	for child in _game.hud.get_children():
		if child is StoryPhone and child.visible:
			rectangles.phone = _rect(child.get_global_rect())
		if child is MissionHud:
			rectangles.cash = _rect(child._cash.get_global_rect())
			if child._title.visible:
				rectangles.title = _rect(child._title.get_global_rect())
				rectangles.objective = _rect(child._objective.get_global_rect())
	var touch := _game._touch_controls
	if touch:
		for button in touch._buttons:
			if button.shown:
				rectangles[String(button.id)] = _rect(Rect2(button.center - Vector2.ONE * button.radius, Vector2.ONE * button.radius * 2.0) if button.is_round() else button.rect)
	state.rectangles = rectangles
	JavaScriptBridge.eval("window.nycPolishState=" + JSON.stringify(state))


func _rect(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Seed on an actual free loaded road, as story recovery cars do. Takeover
## uses Drive mode; the steering pilot never changes this placement again.
func _seed_chase_car(wanted: Wanted) -> void:
	var hero := _game.hero
	var nearest := INF
	var spot := Vector3.ZERO
	var selected: TrafficLanes.Lane
	var progress := 0.0
	for lanes: Array in wanted.pursuit.graph.tiles.values():
		for lane: TrafficLanes.Lane in lanes:
			if lane.length < 45.0:
				continue
			var d := minf(lane.length * 0.5, lane.length - 20.0)
			var point := lane.point_on(lane.segment_at(d, 0), d) + Vector3.UP * 0.12
			var distance := point.distance_squared_to(hero.world_position())
			if distance < nearest and _game.city.has_collision_at(point) and wanted.pursuit._free_spot(point, lane.yaws[lane.segment_at(d, 0)]):
				nearest = distance
				spot = point
				selected = lane
				progress = d
	if selected == null:
		return
	hero.set_mode(&"OnFoot")
	var car := DriveVehicle.new()
	car.traffic = _game.get_node("Traffic") as Traffic
	car.heading = selected.yaws[selected.segment_at(progress, 0)]
	_game.add_child(car)
	car.global_position = WorldOrigin.to_local(spot)
	var drive := hero.get_mode(&"Drive") as DriveMode
	drive.car = car
	hero.set_mode(&"Drive")
	_drive_lane = selected
	_drive_distance = progress
	_drive_recovery = AiRecovery.new()


## Repeatable CPU stress route using the real car's ordinary input. No health,
## position, wanted or mission edits happen while the pilot is driving.
func _physics_process(delta: float) -> void:
	if not _ready_for_checks or not OS.has_feature("web") or get_tree().paused \
			or not bool(JavaScriptBridge.eval("window.nycDrivePilot === true")):
		return
	var hero := _game.hero
	var drive := hero.get_mode(&"Drive") as DriveMode
	if hero.mode != drive or not is_instance_valid(drive.car):
		return
	if _chase_elapsed >= 0.0:
		_chase_elapsed += delta
		if _chase_elapsed >= 8.0:
			(_game.hud.get_node("DebugLabel") as DebugHud).visible = false
			get_tree().paused = true
			print("[hud-check] chase held after %.1f seconds of ordinary driving" % _chase_elapsed)
			return
	var car := drive.car
	var at := hero.world_position()
	var graph := (_game.get_node("Wanted") as Wanted).pursuit.graph
	if _drive_lane == null or _drive_lane.removed:
		var best := INF
		for lanes: Array in graph.tiles.values():
			for lane: TrafficLanes.Lane in lanes:
				for i in lane.points.size() - 1:
					var point := Geometry3D.get_closest_point_to_segment(at, lane.points[i], lane.points[i + 1])
					var angle := wrapf(lane.yaws[i] - car.heading, -PI, PI)
					var score := point.distance_to(at) + absf(angle) * 10.0
					if score < best:
						best = score
						_drive_lane = lane
						_drive_distance = lane.along[i] + point.distance_to(lane.points[i])
	if _drive_lane == null:
		return
	var segment := _drive_lane.segment_at(_drive_distance, 0)
	var point := Geometry3D.get_closest_point_to_segment(at, _drive_lane.points[segment], _drive_lane.points[segment + 1])
	_drive_distance = maxf(_drive_distance, _drive_lane.along[segment] + point.distance_to(_drive_lane.points[segment]))
	if _drive_distance >= _drive_lane.length - 8.0:
		var options := graph.leaving(_drive_lane.to_node)
		var best := INF
		var next_lane: TrafficLanes.Lane
		for lane: TrafficLanes.Lane in options:
			var angle := absf(wrapf(lane.yaws[0] - car.heading, -PI, PI))
			if angle < best:
				best = angle
				next_lane = lane
		if next_lane:
			_drive_lane = next_lane
			_drive_distance = 0.0
	var ahead := minf(_drive_lane.length, _drive_distance + 12.0)
	var target := _drive_lane.point_on(_drive_lane.segment_at(ahead, 0), ahead)
	var toward := target - at
	var angle := wrapf(atan2(toward.x, toward.z) - car.heading, -PI, PI)
	if _drive_recovery.advance(at, delta, true, angle):
		_drive_lane = null
	hero.input.stick = Vector2(clampf(-angle * 2.0, -1.0, 1.0), -0.7 if absf(angle) < 0.6 else -0.3)
	if _drive_recovery.reverse_time > 0.0:
		hero.input.stick = Vector2(_drive_recovery.turn, 0.8)
