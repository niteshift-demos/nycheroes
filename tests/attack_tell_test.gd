extends Node
## Headless check of thugs' wind-up tells (AttackTell): one thug fights the
## hero on 6th Avenue. Standing still, the tell shows over every punch from the
## tick it starts to the tick it lands, turned the way the punch checks, filling
## in step with it, and gone once it's over; the punches that land on the
## hero land then, for the same damage as ever. Then the hero steps out of
## the wedge a human reaction time (0.25 s) after each tell appears, and no
## punch lands; stepping out only 0.4 s in is too late, and they land as
## before. Exits non-zero on a failure.
## Run: godot --headless --path . res://tests/attack_tell_test.tscn
## (sandbox without tiles: add -- --tiles_url=http://localhost:8060/tiles/)

const AVENUE := Vector3(0.485, 0.0, -0.875)
## 6th Avenue with nothing in the way (world meters); as combat_test.
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)
const THUG_SCENE := preload("res://scenes/npc/thug.tscn")
## Seconds from a tell showing up to the (test) player moving: in time, and too late.
const REACTION_TIME := 0.25
const LATE_REACTION_TIME := 0.4

var _world: Node
var _hero: Hero
var _city: CityStreamer
var _thug: Thug
var _phase := "load"
var _time := 0.0
var _failures: Array[String] = []
## The current punch: seconds since its tell showed up (-1: none showing).
var _tell_age := -1.0
var _last_progress := 0.0
var _punches := 0
var _hits := 0
var _damage := 0.0
var _hit_at_progress: Array[float] = []


func _ready() -> void:
	_world = load("res://scenes/world.tscn").instantiate()
	add_child(_world)
	_world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	_world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = _world.get_node("Hero")
	_city = _world.get_node("City")
	_hero.hurt.connect(_on_hurt)
	process_physics_priority = -20  # before the hero reads its input


func _physics_process(delta: float) -> void:
	_check_tell(delta)
	_hero.input.clear()
	_hero.input.aim = AVENUE
	_time += delta
	match _phase:
		"load":
			if not _hero.frozen and _city.pending_count() == 0:
				_teleport(OPEN_AVENUE)
				_spawn_thug(OPEN_AVENUE + AVENUE * 6.0)
				_begin("stand")
			elif _time > 60.0:
				_fail("the city didn't load")
				_finish()
		"stand":
			if _time >= 9.0:
				_report("standing still")
				if _punches < 3:
					_fail("standing still: only %d punches" % _punches)
				if _hits == 0:
					_fail("standing still: no punch landed")
				if _hits > 0 and not is_equal_approx(_damage / _hits, Thug.PUNCH_DAMAGE):
					_fail("a punch hurt %.1f, not %.1f" % [_damage / _hits, Thug.PUNCH_DAMAGE])
				for progress in _hit_at_progress:
					if progress < 0.85:
						_fail("a punch landed with its tell only %d%% full" % int(progress * 100.0))
				_hero.health = Hero.MAX_HEALTH
				_begin("dodge")
		"dodge", "late":
			# Step straight away from the thug once the tell has been up a
			# reaction time; between punches, walk back up to it.
			var away := _hero.global_position - _thug.global_position
			away.y = 0.0
			if _tell_age >= (REACTION_TIME if _phase == "dodge" else LATE_REACTION_TIME):
				_hero.input.move = away.normalized()
				_hero.input.stick = Vector2(0.0, -1.0)
			elif _tell_age < 0.0 and away.length() > 1.6:
				_hero.input.move = -away.normalized() * 0.3
				_hero.input.stick = Vector2(0.0, -0.3)
			if _time >= 12.0 and _phase == "dodge":
				_report("stepping out in 0.25 s")
				if _punches < 3:
					_fail("dodging: only %d punches" % _punches)
				if _hits > 0:
					_fail("dodging: %d punches landed after stepping out of the tell" % _hits)
				_hero.health = Hero.MAX_HEALTH
				_begin("late")
			elif _time >= 12.0:
				_report("stepping out in 0.4 s")
				if _punches < 3 or _hits < _punches - 1:
					_fail("too late: %d of %d punches landed" % [_hits, _punches])
				_finish()


## Checks the thug's tell against its attack state, as both were left by the
## last tick (this node runs before the thug).
func _check_tell(delta: float) -> void:
	if _thug == null or _phase == "load":
		return
	var left := _thug.windup_left()
	var tell := _thug.find_children("*", "AttackTell", false, false)
	var shown := not tell.is_empty() and (tell[0] as AttackTell).visible
	if left > 0.0:
		if not shown:
			_fail("a punch winding up (%.2f s left) without its tell" % left)
			return
		var node := tell[0] as AttackTell
		if absf(angle_difference(node.rotation.y, _thug.facing())) > 0.001:
			_fail("the tell faces %.2f, the punch %.2f" % [node.rotation.y, _thug.facing()])
		if _tell_age < 0.0:
			_tell_age = 0.0
			_punches += 1
		else:
			_tell_age += delta
		_last_progress = 1.0 - left / Thug.PUNCH_HIT_TIME
	else:
		_tell_age = -1.0


func _on_hurt(damage: float) -> void:
	_hits += 1
	_damage += damage
	_hit_at_progress.append(_last_progress)


func _begin(phase: String) -> void:
	_phase = phase
	_time = 0.0
	_punches = 0
	_hits = 0
	_damage = 0.0
	_hit_at_progress.clear()


func _report(what: String) -> void:
	print("%-26s %d punches, %d landed (%.0f damage), tell full when they landed: %s" % [
		what, _punches, _hits, _damage, _hit_at_progress.map(func(p: float) -> String: return "%d%%" % int(p * 100.0))])


func _spawn_thug(world_position: Vector3) -> void:
	_thug = THUG_SCENE.instantiate()
	add_child(_thug)
	var ground := _city.ground_height_at(world_position, 6.0)
	world_position.y = ground if not is_nan(ground) else _hero.world_position().y
	_thug.global_position = WorldOrigin.to_local(world_position) + Vector3.UP * 0.2
	_thug.setup(_hero, 0, 0.0)


func _teleport(world_position: Vector3) -> void:
	var ground := _city.ground_height_at(world_position)
	if not is_nan(ground):
		world_position.y = ground + 0.05
	_hero.global_position = WorldOrigin.to_local(world_position)
	_hero.velocity = Vector3.ZERO


func _fail(message: String) -> void:
	if not _failures.has(message):
		_failures.append(message)
		print("FAIL  " + message)


func _finish() -> void:
	print("attack tells: %s" % ("ok" if _failures.is_empty() else "%d failure(s)" % _failures.size()))
	get_tree().quit(0 if _failures.is_empty() else 1)
