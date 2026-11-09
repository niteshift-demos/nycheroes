extends Node
## Video capture driver for the flight air brake (not a pass/fail test). Runs
## the real game scene (world.tscn, with its PlayerInput, camera, HUD, crowd,
## traffic and thugs all on) and, once the city has loaded and the hero stands
## on the street, presses ordinary input actions on a fixed timeline
## (Input.action_press, as a keyboard or gamepad would): take off, climb,
## boost along an avenue, air brake to a hover, turn around, boost back, then
## brake while descending to land. Nothing else about the game is touched.
## Prints "[capture] T0 frame N" when the timeline starts, so the loading
## frames before it can be trimmed off the recording.
## Record with Godot's Movie Maker (see docs/ROADMAP.md, step 2):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/brake/frame.png \
##     res://tests/flight_brake_capture.tscn -- --name=Hero --solo=1 \
##     --spawn=420,19,-220,-29 --tiles_url=https://nycheroes.party/tiles/

## Seconds after the city is ready before the timeline starts.
const SETTLE := 1.5
## [start s, end s, action, strength]: held from start until end.
const TIMELINE := [
	[1.0, 1.1, &"fly_toggle", 1.0],
	[1.2, 3.6, &"jump", 1.0],          # climb above the avenue
	[3.0, 3.13, &"look_up", 0.5],      # level the camera so boosting stays level
	[3.8, 10.5, &"move_forward", 1.0], # fly along the avenue...
	[3.8, 10.5, &"sprint", 1.0],       # ...boosting
	[8.4, 10.5, &"brake", 1.0],        # air brake, W and Shift still held
	[11.2, 12.46, &"look_left", 1.0],  # hovering: turn the camera around
	[12.8, 15.4, &"move_forward", 1.0],
	[12.8, 15.4, &"sprint", 1.0],
	[15.4, 20.5, &"brake", 1.0],       # brake while descending, down to the street
	[15.4, 20.5, &"descend", 1.0],
]
const END := 22.0

var _world: Game
var _hero: Hero
var _city: CityStreamer
var _frame := 0
var _ready_frame := -1
var _t0_frame := -1
var _pressed := {}


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_hero.mode_changed.connect(func(mode: StringName) -> void:
		print("[capture] frame %d mode %s" % [_frame, mode]))


func _process(_delta: float) -> void:
	_frame += 1
	if _t0_frame < 0:
		if _ready_frame < 0 and not _hero.frozen and _city.pending_count() == 0:
			_ready_frame = _frame
		if _ready_frame >= 0 and _frame - _ready_frame >= roundi(SETTLE * 30.0):
			_t0_frame = _frame
			print("[capture] T0 frame %d" % _t0_frame)
		return
	var t := float(_frame - _t0_frame) / 30.0
	var want := {}
	for entry: Array in TIMELINE:
		if t >= entry[0] and t < entry[1]:
			want[entry[2]] = entry[3]
	for action: StringName in _pressed.keys():
		if not want.has(action):
			Input.action_release(action)
			_pressed.erase(action)
	for action: StringName in want:
		if _pressed.get(action, 0.0) != want[action]:
			Input.action_press(action, want[action])
			_pressed[action] = want[action]
	if _frame % 15 == 0:
		var flight := _hero.get_mode(&"Flight") as FlightMode
		print("[capture] frame %d t %.2f mode %s speed %.1f height %.1f braking %s shed %.1f stop_in %.1f at %s" % [
			_frame, t, _hero.mode.name, _hero.velocity.length(), _hero.world_position().y, flight.braking,
			flight.speed_to_shed(), flight.stopping_distance(flight.speed_to_shed()), _hero.world_position().round()])
	if t >= END:
		print("[capture] END frame %d" % _frame)
		get_tree().quit()
