extends Node
## Plays super swimming in the real city for a video, through the ordinary
## controls: it presses the game's own input actions (move_forward, sprint,
## move_right, look_right, jump) the way a keyboard would, so PlayerInput,
## the camera and the hero run exactly as when playing. Starts in the Hudson
## off Midtown (pass the spawn as a launch option) once the city has loaded,
## shows the keys held and the hero's speed and surge state, and quits when
## done. Prints "[record] start" when the shot rolls, so leading loading
## frames can be trimmed.
## Record (Movie Maker, 1280x720 at 30 fps):
##   godot --path . --write-movie out.avi --fixed-fps 30 --resolution 1280x720 \
##     res://tests/swim_sprint_recording.tscn -- --spawn=-1700,3,-250,-29 \
##     --solo=1 --name=Recorder --tiles_url=https://nycheroes.party/tiles/
## Headless, it just plays the same moves and prints what happened.

## Seconds after the city has loaded before the shot rolls.
const SETTLE := 1.5

## [start s, end s, action, strength] key holds, from the shot's start.
const KEYS := [
	[0.0, JUMP_AT + 0.6, "move_forward", 1.0],
	[JUMP_AT + 1.6, 40.0, "move_forward", 1.0],
	[2.0, 6.0, "sprint", 1.0],  # press: a surge kick, then building to super swimming
	[3.4, 3.9, "look_right", 1.0],  # an S-bend: at speed the hero carves after the camera
	[4.4, 4.9, "look_left", 1.0],
	[6.15, 7.3, "sprint", 1.0],  # tap at full speed: a surge to the cap
	[7.45, 8.9, "sprint", 1.0],  # tap during the cooldown: nothing (the limit)
	[9.05, 40.0, "sprint", 1.0],  # ready again: surge, then on into a breakwater
	[JUMP_AT, JUMP_AT + 0.2, "jump", 1.0],  # up and over it
	[JUMP_AT + 0.9, JUMP_AT + 1.5, "look_right", 1.0],  # turn toward the Manhattan shore

]
## When the hero, stopped against a breakwater, leaps over it.
const JUMP_AT := 14.3
const CAPTIONS := [
	[0.0, "Swimming in the Hudson, off Midtown"],
	[2.0, "Shift: a surge kick, then super swimming builds up"],
	[3.4, "Turning at speed: wide arcs, not spins"],
	[6.15, "Shift tap at full speed: SURGE (capped at 38 m/s)"],
	[7.45, "Shift tap again: still cooling down, no surge"],
	[9.05, "Surge ready again"],
	[WALL_CAPTION, "A breakwater stops a super swimmer dead"],
	[JUMP_AT, "Space: leap over it (Shift held: no new surge)"],
	[JUMP_AT + 2.0, "Super swimming builds up again toward the seawall"],
	[22.3, "Into the next wall at an angle: sliding, then stopped"],
]
const WALL_CAPTION := 12.9
const DURATION := 24.5

var _world: Game
var _hero: Hero
var _on_foot: OnFootMode
var _city: CityStreamer
var _loaded := 0.0
var _time := -1.0
var _overlay: Label
var _caption: Label
var _log_cooldown := 0.0


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_on_foot = _hero.get_mode(&"OnFoot") as OnFootMode
	_city = _world.get_node("City")
	# The stats text (on by default on desktop) would sit under the captions.
	(_world.get_node("HUD/DebugLabel") as CanvasItem).visible = false
	process_physics_priority = -30  # before PlayerInput reads the actions
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_caption = _label(layer, 30, Vector2(40, 40))
	_overlay = _label(layer, 24, Vector2(40, 570))


func _physics_process(delta: float) -> void:
	if _time < 0.0:
		if _hero.frozen or _city.pending_count() > 0:
			_loaded = 0.0
			return
		_loaded += delta
		if _loaded < SETTLE:
			return
		_time = 0.0
		print("[record] start at frame %d" % Engine.get_frames_drawn())
	_time += delta
	var held := {}  # action -> strength
	for key: Array in KEYS:
		if _time >= key[0] and _time < key[1]:
			held[key[2]] = key[3]
	for action: String in ["move_forward", "sprint", "jump", "look_right", "look_left"]:
		if held.has(action) and not Input.is_action_pressed(action):
			Input.action_press(action, held[action])
		elif not held.has(action) and Input.is_action_pressed(action):
			Input.action_release(action)
	_show(held)
	_log(delta)
	if _time >= DURATION:
		print("[record] finished")
		get_tree().quit()


func _show(held: Dictionary) -> void:
	for caption: Array in CAPTIONS:
		if _time >= caption[0]:
			_caption.text = caption[1]
	var keys := PackedStringArray()
	for pair: Array in [["move_forward", "W"], ["look_right", "look right"], ["look_left", "look left"], ["sprint", "Shift"], ["jump", "Space"]]:
		if held.has(pair[0]):
			keys.append(pair[1])
	var surge := "SURGE!" if _on_foot.surge_time > 0.0 else (
		"surge in %.1f s" % _on_foot.surge_cooldown if _on_foot.surge_cooldown > 0.0 else "surge ready")
	var where := "in the water" if _hero.is_in_water() else ("on land" if _hero.is_on_floor() else "in the air")
	_overlay.text = "Keys: %s\nSpeed %4.1f m/s  ·  %s  ·  %s" % [
		" + ".join(keys) if not keys.is_empty() else "-", _speed(), surge if _hero.is_in_water() else "", where]


func _log(delta: float) -> void:
	_log_cooldown -= delta
	if _log_cooldown > 0.0:
		return
	_log_cooldown = 0.25
	print("[record] t %5.2f  speed %5.1f  surge %.2f  cooldown %.2f  water %s  wall %s  floor %s  at %s" % [
		_time, _speed(), _on_foot.surge_time, _on_foot.surge_cooldown, _hero.is_in_water(),
		_hero.is_on_wall(), _hero.is_on_floor(), _hero.world_position().round()])


func _speed() -> float:
	return Vector2(_hero.velocity.x, _hero.velocity.z).length()


func _label(parent: Node, size: int, at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	parent.add_child(label)
	return label
