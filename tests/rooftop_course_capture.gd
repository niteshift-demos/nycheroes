extends Node
## Not a test: records the rooftop run for a video with Godot's Movie Maker.
## Runs the real game scene (scenes/world.tscn, with its pedestrians,
## traffic, gangs and trains as usual) with the hero started on the START
## pad by the game's own `--course=start`, waits for the city to load and
## settle, then plays the run with ordinary input actions
## (tests/rooftop_course_driver.gd): every jump, one of them charged too
## little on purpose so the attempt fails and is retried. The hero's moves,
## the clock and the course are the game's own; nothing is sped up.
## Prints the movie frame the run starts at, so the loading can be cut off.
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/rooftop/frame.png \
##     res://tests/rooftop_course_capture.tscn -- --tiles_url=https://nycheroes.party/tiles \
##     --course=start --name=Recorder --solo=1

const Driver := preload("res://tests/rooftop_course_driver.gd")
## Seconds to let the city settle after it has loaded, and to stay on the
## finish afterwards.
const WARM_UP := 4.0
const LINGER := 3.0
const LEGS: Array[Dictionary] = [
	{"to": 1}, {"to": 2}, {"to": 3}, {"to": 4}, {"to": 5},
	{"to": 6, "charge": 0.45},  # too little for the tower: falls to the street
	{"to": 6},
]

var _world: Game
var _driver: Driver
var _loaded_at := -1.0
var _time := 0.0
var _done_at := -1.0


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	var city := _world.get_node("City") as CityStreamer
	city.initial_load_finished.connect(func(_s: float) -> void: _loaded_at = _time, CONNECT_ONE_SHOT)
	_world.course.run_failed.connect(func(reason: String) -> void:
		print("[capture] frame %d: failed: %s" % [Engine.get_frames_drawn(), reason]))
	_world.course.pad_reached.connect(func(index: int) -> void:
		print("[capture] frame %d: pad %d, clock %.2f s" % [Engine.get_frames_drawn(), index, _world.course.elapsed]))
	_world.course.run_finished.connect(func(seconds: float, _best: bool) -> void:
		print("[capture] frame %d: finished in %.2f s, falls %d" % [Engine.get_frames_drawn(), seconds, _world.course.falls]))


func _process(delta: float) -> void:
	_time += delta
	var hero := _world.hero
	if _driver == null and _loaded_at >= 0.0 and not hero.frozen and _time - _loaded_at > WARM_UP \
			and (_world.get_node("City") as CityStreamer).pending_count() == 0:
		print("[capture] frame %d: driving starts (%.1f s game time)" % [Engine.get_frames_drawn(), _time])
		_driver = Driver.new()
		_driver.hero = hero
		_driver.camera = _world.hero_camera
		_driver.course = _world.course
		_driver.legs = LEGS
		_driver.settle_time = 0.3
		_driver.finished.connect(func() -> void: _done_at = _time)
		add_child(_driver)
	if _done_at >= 0.0 and _time - _done_at > LINGER:
		print("[capture] frame %d: done" % Engine.get_frames_drawn())
		get_tree().quit()
