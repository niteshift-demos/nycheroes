extends Node
## Headless check of the wall kick, against a real building on an avenue in
## Midtown: jump at the wall and press jump again beside it to kick off (up and
## away from it), the cooldown swallows a second press straight after, kicking
## back at the same wall gains less and less height and stops after
## OnFootMode.wall_kicks_per_jump kicks (no climbing a tower), touching down
## gives the kicks back, and jump in open air does nothing.
## Run: godot --headless --path . res://tests/wall_kick_test.tscn
## (streams tiles from the public site unless --tiles=DIR / data/tiles exist:
## add -- --tiles_url=https://nycheroes.party/tiles/ in a checkout without tiles).

## Manhattan's avenues run about 29 degrees east of north.
const AVENUE := Vector3(0.485, 0.0, -0.875)
## Across the avenue, toward the buildings either side.
const CROSS := Vector3(0.875, 0.0, 0.485)
## An open stretch of avenue in Midtown, with buildings along both sides (world meters).
const OPEN_AVENUE := Vector3(420.0, 3.0, -220.0)

var _world: Game
var _hero: Hero
var _on_foot: OnFootMode
var _city: CityStreamer
var _failures: Array[String] = []
var _wall_normal := Vector3.ZERO
var _wall_point := Vector3.ZERO


func _ready() -> void:
	var world: Game = load("res://scenes/world.tscn").instantiate()
	add_child(world)
	_world = world
	world.get_node("PlayerInput").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Crowd").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("Encounters").process_mode = Node.PROCESS_MODE_DISABLED
	_hero = world.get_node("Hero")
	_on_foot = _hero.get_mode(&"OnFoot") as OnFootMode
	_city = world.get_node("City")
	_run.call_deferred()


func _run() -> void:
	var start := Time.get_ticks_msec()
	while _hero.frozen or _city.pending_count() > 0:
		await get_tree().physics_frame
		if Time.get_ticks_msec() - start > 120000:
			_fail("the city didn't load in 2 minutes")
			_finish()
			return
	await _settle_at(OPEN_AVENUE)
	if not _find_wall():
		_fail("no building wall found across the avenue from %s" % OPEN_AVENUE)
		_finish()
		return
	print("wall at %s, facing %s" % [_wall_point.round(), _wall_normal.snapped(Vector3.ONE * 0.01)])

	# 1. Jump at the wall, kick off it.
	await _stand_off_wall(2.5)
	var ground_y := _hero.world_position().y
	var kicks_before := _on_foot.wall_kick_id
	await _ticks(1, func(i: HeroInput) -> void: _toward_wall(i); i.jump_held = true)
	# Drift in toward the wall until it's within reach (a fraction of a second).
	var near := Vector3.ZERO
	for n in 60:
		await _ticks(1, _toward_wall)
		near = _on_foot.find_wall()
		if near != Vector3.ZERO and n > 5:
			break
	_check(not _hero.is_on_floor(), "still in the air when the wall comes within reach (%.1f m up)" % (_hero.world_position().y - ground_y))
	_check(near != Vector3.ZERO, "beside the wall in the air, find_wall sees it (got %s)" % near)
	await _ticks(1, func(i: HeroInput) -> void: _toward_wall(i); i.jump_held = true)
	var velocity := _hero.velocity
	print("kick: velocity %s, out from the wall %.1f m/s, up %.1f m/s" % [
		velocity.snapped(Vector3.ONE * 0.1), velocity.dot(_wall_normal), velocity.y])
	_check(_on_foot.wall_kick_id == kicks_before + 1, "jump beside the wall kicks (id %d -> %d)" % [kicks_before, _on_foot.wall_kick_id])
	_check(velocity.dot(_wall_normal) > 8.0, "the kick pushes away from the wall (%.1f m/s)" % velocity.dot(_wall_normal))
	_check(velocity.y > 10.0, "the kick springs upward (%.1f m/s)" % velocity.y)
	# 2. Cooldown: pressing again straight away does nothing.
	await _ticks(2, func(i: HeroInput) -> void: pass)
	await _ticks(1, func(i: HeroInput) -> void: i.jump_held = true)
	_check(_on_foot.wall_kick_id == kicks_before + 1, "a second press within the cooldown doesn't kick")
	await _land()

	# 3. Keep kicking the same wall: weaker each time, then none at all.
	await _stand_off_wall(1.5)
	ground_y = _hero.world_position().y
	kicks_before = _on_foot.wall_kick_id
	var top := ground_y
	var lifts: Array[float] = []
	await _ticks(1, func(i: HeroInput) -> void: _toward_wall(i); i.jump_held = true)
	# Hold toward the wall for 5 s, pressing jump whenever it's within reach
	# again (as fast as a player could mash it).
	var since_press := 0
	for n in 300:
		var press := since_press >= 6 and not _hero.is_on_floor() and _on_foot.find_wall() != Vector3.ZERO
		since_press = 0 if press else since_press + 1
		var id := _on_foot.wall_kick_id
		await _ticks(1, func(i: HeroInput) -> void: _toward_wall(i); i.jump_held = press)
		if _on_foot.wall_kick_id != id:
			lifts.append(snappedf(_hero.velocity.y, 0.1))
		top = maxf(top, _hero.world_position().y)
		if _hero.is_on_floor() and n > 30:
			break
	var kicks := _on_foot.wall_kick_id - kicks_before
	print("ladder attempt: %d kicks, lifts %s, highest %.1f m above the ground" % [kicks, lifts, top - ground_y])
	_check(kicks >= 1, "the wall kicks the hero off it (%d)" % kicks)
	_check(kicks <= _on_foot.wall_kicks_per_jump, "at most %d kicks before landing (%d)" % [_on_foot.wall_kicks_per_jump, kicks])
	_check(lifts.size() < 2 or lifts[1] < lifts[0] * 0.6, "the same wall twice lifts less (%s)" % [lifts])
	_check(top - ground_y < 12.0, "kicking can't climb the wall (%.1f m up)" % (top - ground_y))

	# 4. Put back beside the same wall in mid-air after each kick (as bouncing
	# around a tight corner might): each kick lifts less, and the fourth fails.
	await _land()
	lifts.clear()
	kicks_before = _on_foot.wall_kick_id
	var air_spot := _wall_point + _wall_normal * 0.5 + Vector3.UP * 4.0
	for n in 5:
		_hero.global_position = WorldOrigin.to_local(air_spot)
		_hero.velocity = Vector3.ZERO
		await _ticks(25, func(i: HeroInput) -> void: pass)  # the cooldown runs out
		_hero.global_position = WorldOrigin.to_local(air_spot)
		_hero.velocity = Vector3.ZERO
		var id := _on_foot.wall_kick_id
		await _ticks(1, func(i: HeroInput) -> void: i.jump_held = true)
		if _on_foot.wall_kick_id != id:
			lifts.append(snappedf(_hero.velocity.y, 0.1))
	print("kicks off one wall in a row: lifts %s" % [lifts])
	_check(_on_foot.wall_kick_id - kicks_before == _on_foot.wall_kicks_per_jump,
		"only %d kicks before touching down (%d)" % [_on_foot.wall_kicks_per_jump, _on_foot.wall_kick_id - kicks_before])
	_check(lifts.size() == 3 and lifts[1] < lifts[0] * 0.5 and lifts[2] < lifts[1] * 0.5,
		"each kick off the same wall lifts less (%s)" % [lifts])

	# 5. Landing gives the kicks back.
	await _land()
	_check(_on_foot.wall_kicks_left == _on_foot.wall_kicks_per_jump, "landing gives the kicks back (%d)" % _on_foot.wall_kicks_left)

	# 6. In the middle of the avenue, a jump in the air is just a jump.
	await _settle_at(OPEN_AVENUE)
	kicks_before = _on_foot.wall_kick_id
	await _ticks(1, func(i: HeroInput) -> void: i.jump_held = true)
	await _ticks(20, func(i: HeroInput) -> void: pass)
	await _ticks(1, func(i: HeroInput) -> void: i.jump_held = true)
	_check(_on_foot.wall_kick_id == kicks_before, "no wall, no kick")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("wall kick test: all passed")
		get_tree().quit(0)
	else:
		for failure in _failures:
			printerr("FAILED: " + failure)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("ok      " if ok else "FAILED  ") + what)
	if not ok:
		_failures.append(what)


func _fail(what: String) -> void:
	_check(false, what)


## Runs `apply` on the hero's input for `count` physics ticks.
func _ticks(count: int, apply: Callable) -> void:
	for n in count:
		_hero.input.clear()
		apply.call(_hero.input)
		await get_tree().physics_frame
	_hero.input.clear()


func _land() -> void:
	for n in 300:
		await _ticks(1, func(i: HeroInput) -> void: pass)
		if _hero.is_on_floor():
			break
	await _ticks(10, func(i: HeroInput) -> void: pass)


func _settle_at(world_position: Vector3) -> void:
	_world.place_hero(world_position, 0.0, true)
	await get_tree().physics_frame
	while _hero.frozen:
		await get_tree().physics_frame
	await _land()


## Finds a tall building face across the avenue: a wall 2 m up whose face is
## still there 20 m up.
func _find_wall() -> bool:
	var space := _hero.get_world_3d().direct_space_state
	var origin := _hero.global_position
	for side: Vector3 in [CROSS, -CROSS]:
		for along: float in [0.0, 20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 80.0]:
			var from := origin + AVENUE * along + Vector3.UP * 2.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + side * 60.0, Hero.WORLD_LAYER))
			if hit.is_empty() or absf(hit.normal.y) > 0.2:
				continue
			var high := from + Vector3.UP * 20.0
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(high, high + side * 62.0, Hero.WORLD_LAYER)).is_empty():
				continue
			var normal: Vector3 = hit.normal
			# Nothing overhead (an awning, scaffolding) where the hero will jump.
			var out := Vector3(normal.x, 0.0, normal.z).normalized()
			var covered := false
			for distance: float in [0.2, 0.5, 0.8, 1.2]:
				var spot: Vector3 = hit.position + out * distance
				covered = covered or not space.intersect_ray(
					PhysicsRayQueryParameters3D.create(spot, spot + Vector3.UP * 15.0, Hero.WORLD_LAYER)).is_empty()
			if covered:
				continue
			_wall_normal = Vector3(normal.x, 0.0, normal.z).normalized()
			_wall_point = WorldOrigin.to_world(hit.position)
			return true
	return false


## Stands the hero on the ground `distance` meters out from the wall, facing it.
func _stand_off_wall(distance: float) -> void:
	var spot := _wall_point + _wall_normal * distance
	await _settle_at(Vector3(spot.x, spot.y + 2.0, spot.z))
	_hero.face_toward(-_wall_normal)


func _toward_wall(input: HeroInput) -> void:
	input.move = -_wall_normal
	input.stick = Vector2(0.0, -1.0)
