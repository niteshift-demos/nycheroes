extends Node
## Not a pass/fail test: plays a street fight in the real game (the main
## scene, with its own gangs) through the player's own controls, for
## recording health recovery between fights with Godot's Movie Maker. It
## presses the same input actions as the keyboard (move_forward, sprint,
## attack) and turns the camera the way the mouse does; nothing is placed,
## hurt or healed by it. The hero runs up to the nearest gang, takes a beating
## without fighting back (health drops, "IN COMBAT", nothing comes back while
## the thugs stand around), punches them down, then waits: "RECOVERY IN 6s"
## counting down, then "+ RECOVERING" as the bar slowly refills.
## Record (see docs/ROADMAP.md, step 3):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 30 --write-movie /tmp/recovery.avi \
##     res://tests/recovery_recording.tscn -- --name=Recorder --solo=1 --gangs=1 --peds=20

## Seconds to stand among the thugs before punching back.
const TAKE_HITS := 5.0
## Seconds to keep filming once the gang is down.
const AFTER_FIGHT := 13.0
## Closer than this (m), stop running at super speed (a ram would end the fight at once).
const SPRINT_UNTIL := 70.0
const PUNCH_RANGE := 2.6

enum Phase { LOADING, APPROACH, TAKE_HITS, FIGHT, RECOVER }

var _world: Node
var _hero: Hero
var _camera: ThirdPersonCamera
var _encounters: EncounterDirector
var _phase := Phase.LOADING
var _time := 0.0
var _frames := 0


func _ready() -> void:
	process_physics_priority = -20  # before PlayerInput reads the actions
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_hero = _world.get_node("Hero")
	_camera = _world.get_node("HeroCamera")
	_encounters = _world.get_node("Encounters")


func _physics_process(delta: float) -> void:
	_time += delta
	_release(["move_forward", "sprint", "attack"])
	match _phase:
		Phase.LOADING:
			if not _hero.frozen and _encounters.nearest_thug(_hero.world_position()) != null:
				_next(Phase.APPROACH)
		Phase.APPROACH:
			var thug := _encounters.nearest_thug(_hero.world_position())
			if thug == null:
				return
			var distance := _look_at(thug.global_position, delta)
			Input.action_press("move_forward")
			if distance > SPRINT_UNTIL:
				Input.action_press("sprint")
			if distance < PUNCH_RANGE + 1.5:
				_next(Phase.TAKE_HITS)
		Phase.TAKE_HITS:
			var thug := _encounters.nearest_thug(_hero.world_position())
			if thug:
				_look_at(thug.global_position, delta)
			if _time > TAKE_HITS or _hero.health < 45.0:
				_next(Phase.FIGHT)
		Phase.FIGHT:
			var thug := _encounters.nearest_thug(_hero.world_position())
			var standing := Combat.thugs.filter(func(t: Thug) -> bool: return not t.is_down())
			if standing.is_empty() or thug == null or _time > 30.0:
				_next(Phase.RECOVER)
				return
			var distance := _look_at(thug.global_position, delta)
			if distance > PUNCH_RANGE:
				Input.action_press("move_forward")
			elif fmod(_time, 0.3) < 0.12:
				Input.action_press("attack")
		Phase.RECOVER:
			_camera.yaw += 0.12 * delta  # a slow look around
			if _time > AFTER_FIGHT:
				print("[recording] finished: health %.1f" % _hero.health)
				get_tree().quit()
	_frames += 1
	if _frames % 30 == 0:
		print("[recording] %s %.1fs health %.1f recovering %s in_combat %s wait %.1f" % [
			Phase.keys()[_phase], _time, _hero.health, _hero.recovery.recovering,
			_hero.recovery.in_combat, _hero.recovery.wait])


## Turns the camera (as the mouse would) toward a scene position; returns the
## flat distance to it.
func _look_at(target: Vector3, delta: float) -> float:
	var offset := target - _hero.global_position
	var want := atan2(-offset.x, -offset.z)
	_camera.yaw = rotate_toward(_camera.yaw, want, 2.5 * delta)
	return Vector2(offset.x, offset.z).length()


func _next(phase: Phase) -> void:
	print("[recording] %s -> %s at health %.1f" % [Phase.keys()[_phase], Phase.keys()[phase], _hero.health])
	_phase = phase
	_time = 0.0


func _release(actions: Array[String]) -> void:
	for action in actions:
		Input.action_release(action)
