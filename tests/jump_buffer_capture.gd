extends Node
## Video capture of the landing jump buffer, for Godot's Movie Maker: plays the
## real game (scenes/world.tscn, PlayerInput on) and presses the real "jump"
## input action at chosen moments before the hero lands, with captions saying
## what was pressed when and what the hero did. Nothing about the hero or the
## game is changed: the driver only presses and releases jump, and measures.
## It prints "[capture] start frame N" once the city has loaded, so the
## loading can be trimmed off the front of the movie.
## Run (Linux, under Xvfb on a free display; :99 may be the sandbox desktop):
##   xvfb-run -n 120 -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/jb/movie.avi \
##     res://tests/jump_buffer_capture.tscn -- --tiles_url=https://nycheroes.party/tiles/ \
##     --name=Hero --solo=1 --gangs=0

## Manhattan's avenues run about 29 degrees east of north.
const AVENUE := Vector3(0.485, 0.0, -0.875)
## 6th Avenue north of Times Square, open street ahead (world meters; dropped).
const START := Vector3(420.0, 30.0, -220.0)
## Seconds the city stays loaded before the shots start (warm-up, trimmed off).
const WARM_UP := 3.0
## Air time of a normal jump on flat ground (s); the driver measures its own
## first jump and uses that, this is only the fallback.
const AIR_TIME := 0.82

var _game: Game
var _hero: Hero
var _on_foot: OnFootMode
var _city: CityStreamer
var _caption: Label
var _result: Label
var _key: Label
var _shots: Array[Dictionary] = []
var _index := -1
var _time := 0.0
var _ready_time := 0.0
var _air_time := AIR_TIME
var _left_ground_at := -1.0  # (shot time) the hero left the ground last
var _press_at := -1.0  # (shot time) jump went down last, in the air
var _landed_at := -1.0
var _was_on_floor := true
var _held := false
var _takeoffs := 0  # in this shot


func _ready() -> void:
	_game = load("res://scenes/world.tscn").instantiate()
	add_child(_game)
	_hero = _game.hero
	_on_foot = _hero.get_mode(&"OnFoot")
	_city = _game.city
	process_physics_priority = -20  # press before PlayerInput reads the keys
	var yaw := atan2(-AVENUE.x, -AVENUE.z)
	_game.place_hero(START, yaw, true)
	_game.hero_camera.yaw = yaw + 1.25  # from the side, to see the hops
	_game.hero_camera.pitch = -0.08
	_add_overlay()
	_shots = [
		_shot("Buffered landing jumps", 2.0, Callable()),
		_shot("Tap jump on the ground: a normal jump", 1.6, _tap_and_measure),
		_shot("Press jump 0.08 s before landing: jumps again the moment it lands", 3.9, _hops.bind(0.08)),
		_shot("Press jump 0.35 s before landing: outside the 0.15 s buffer, ignored", 2.6, _hops.bind(0.35)),
		_shot("Press 0.10 s before landing and keep holding: charges a super jump", 1.6, _hold_through_landing),
		_shot("Let go: the super jump", 4.6, Callable()),
		_shot("Pressed in time it counts; pressed too early it doesn't", 1.5, Callable()),
	]


func _physics_process(delta: float) -> void:
	var on_floor := _hero.is_on_floor()
	if _index < 0:
		if _hero.frozen or _city.pending_count() > 0:
			_ready_time = 0.0
			return
		_ready_time += delta
		if _ready_time >= WARM_UP:
			print("[capture] start frame %d" % Engine.get_frames_drawn())
			_begin(0)
		_was_on_floor = on_floor
		return

	_time += delta
	var shot := _shots[_index]
	var down := false
	if shot.input.is_valid():
		down = shot.input.call(_time, on_floor)
	_set_jump(down)
	_track(on_floor)
	_was_on_floor = on_floor
	if _time >= shot.seconds:
		if _index + 1 >= _shots.size():
			_set_jump(false)
			print("[capture] end frame %d" % Engine.get_frames_drawn())
			get_tree().quit()
			return
		_begin(_index + 1)


func _process(_delta: float) -> void:
	_key.modulate = Color(1.0, 0.85, 0.2) if _held else Color(1, 1, 1, 0.45)


## Tap on the ground and time the jump, for the presses before landing.
func _tap_and_measure(t: float, on_floor: bool) -> bool:
	if on_floor and not _was_on_floor and _left_ground_at >= 0.0:
		_air_time = (t - _tick()) - _left_ground_at
		_say("in the air %.2f s" % _air_time)
	return t < 0.05


## Jumps, then presses (and lets go after 50 ms) `early` seconds before each
## landing; the hops chain on as long as the buffer catches the press, up to
## four jumps, so the shot ends standing.
func _hops(t: float, _on_floor: bool, early: float) -> bool:
	if t < 0.05:
		return true
	if _left_ground_at < 0.0 or _takeoffs >= 4:
		return false
	var press := _left_ground_at + _air_time - early - _tick() * 0.5  # (the nearest tick)
	return t >= press and t < press + 0.05


func _hold_through_landing(t: float, _on_floor: bool) -> bool:
	if t < 0.05:
		return true
	if _left_ground_at < 0.0:
		return false
	return t >= _left_ground_at + _air_time - 0.10 - _tick() * 0.5


## Presses or releases the real jump action, as a key would.
func _set_jump(down: bool) -> void:
	if down == _held:
		return
	_held = down
	if down:
		Input.action_press(&"jump")
		if not _hero.is_on_floor():
			_press_at = _time
	else:
		Input.action_release(&"jump")


## Watches takeoffs and landings, and says how each press before landing went.
## This runs before the hero's own tick, so what it sees happened last tick.
func _track(on_floor: bool) -> void:
	if not on_floor and _was_on_floor:
		_left_ground_at = _time - _tick()
		_takeoffs += 1
		if _landed_at >= 0.0 and _press_at >= 0.0:
			_say("pressed %d ms before landing → jumped %d ms after touching down" % [
				roundi((_landed_at - _press_at) * 1000.0), roundi((_left_ground_at - _landed_at) * 1000.0)])
			_press_at = -1.0
		_landed_at = -1.0
	if on_floor and not _was_on_floor:
		_landed_at = _time - _tick()
		if _press_at >= 0.0 and _landed_at - _press_at > _on_foot.jump_buffer_time:
			_say("pressed %d ms before landing → no jump (buffer is %d ms)" % [
				roundi((_landed_at - _press_at) * 1000.0), roundi(_on_foot.jump_buffer_time * 1000.0)])
			_press_at = -1.0
		elif _press_at >= 0.0 and _held:
			_say("pressed %d ms before landing, still held → charging" % [
				roundi((_landed_at - _press_at) * 1000.0)])
			_press_at = -1.0


func _tick() -> float:
	return 1.0 / Engine.physics_ticks_per_second


## Shows (and logs) what the last press before landing did.
func _say(text: String) -> void:
	_result.text = text
	print("[capture] %.2f s into \"%s\": %s" % [_time, _shots[_index].name, text])


func _begin(index: int) -> void:
	_index = index
	_time = 0.0
	_left_ground_at = -1.0
	_landed_at = -1.0
	_press_at = -1.0
	_takeoffs = 0
	_caption.text = _shots[index].name
	if index != 5:
		_result.text = ""


func _shot(shot_name: String, seconds: float, input: Callable) -> Dictionary:
	return {name = shot_name, seconds = seconds, input = input}


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	# Below the game's own stats lines at the top of the screen.
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.35)
	band.position = Vector2(0, 130)
	band.size = Vector2(1280, 92)
	layer.add_child(band)
	_caption = _label(layer, 32, Vector2(0, 134))
	_result = _label(layer, 24, Vector2(0, 182))
	_key = _label(layer, 30, Vector2(0, 600))
	_key.text = "[ JUMP ]"


func _label(layer: CanvasLayer, size: int, at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(1280, 50)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(label)
	return label
