extends Node3D
## Synthetic floor: real hero physics, dodge timing, counter consumption,
## wall collision, input edges, snapshot round trip and floating origin.
## Run: godot --headless --path . res://tests/dodge_test.tscn

var hero: Hero
var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	print("%s: %s" % ["PASS" if ok else "FAIL", message])


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(shape)
	add_child(floor_body)
	hero = preload("res://scenes/hero/hero.tscn").instantiate()
	add_child(hero)
	hero.frozen = false
	await get_tree().create_timer(0.15).timeout
	check(hero.grounded(), "hero settles on synthetic ground")
	hero.input.dodge_held = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(hero.dodge_time > 0.0, "HeroInput starts dodge")
	check(not hero.try_dodge(), "cooldown rejects repeated dodge")
	var origin := hero.world_position() + Vector3.FORWARD * 1.7
	hero.resolve_punch(origin, Vector3.BACK)
	check(hero.health == Hero.MAX_HEALTH and hero.counter_time > 0.0, "narrow evasion avoids damage and earns counter")
	var sync := PlayerSync.new()
	sync.hero = hero
	var packet := sync._encode(hero)
	check(packet.size() == 16 and packet[13] > 0.0 and packet[15] > 0.0, "snapshot carries dodge and counter")
	var copy: Hero = preload("res://scenes/hero/hero.tscn").instantiate()
	copy.remote_id = 2
	add_child(copy)
	var buffer := SnapshotBuffer.new()
	buffer.push(float(packet[0]), packet)
	sync._follow(copy, buffer)
	check(copy.dodge_time == hero.dodge_time and copy.counter_time == hero.counter_time, "remote hero displays evasion state")
	sync.free()
	WorldOrigin.shift(Vector3(500.0, 0.0, 0.0))
	hero.resolve_punch(origin, Vector3.BACK)
	check(hero.health == Hero.MAX_HEALTH, "evasion survives origin shift")
	WorldOrigin.shift(Vector3(-500.0, 0.0, 0.0))
	await get_tree().create_timer(0.36).timeout
	hero.set_mode(&"Melee")
	check((hero.mode as MeleeMode).step == 2 and hero.counter_time == 0.0, "counter becomes one heavy punch and is consumed")
	hero.set_mode(&"OnFoot")
	await get_tree().create_timer(0.9).timeout
	check(hero.dodge_time == 0.0, "holding dodge never repeats")
	hero.input.clear()
	hero.dodge_cooldown = 0.0
	hero.try_dodge()
	hero.dodge_time = Hero.DODGE_DURATION - 0.18
	hero.resolve_punch(hero.world_position() + Vector3.FORWARD * 1.7, Vector3.BACK)
	check(hero.counter_time == 0.0 and hero.health == Hero.MAX_HEALTH, "early safe dodge has no counter reward")
	hero.dodge_time = 0.0
	hero.resolve_punch(hero.world_position() + Vector3.FORWARD * 1.7, Vector3.BACK)
	check(hero.health == Hero.MAX_HEALTH - Thug.PUNCH_DAMAGE, "unprotected punch still damages hero")
	hero.hurt_time = 0.0
	hero.counter_time = 0.05
	await get_tree().create_timer(0.1).timeout
	hero.set_mode(&"Melee")
	check((hero.mode as MeleeMode).step == 0, "expired counter returns to ordinary jab")
	hero.set_mode(&"Flight")
	hero.dodge_cooldown = 0.0
	check(not hero.try_dodge(), "flight cannot dodge")
	hero.set_mode(&"OnFoot")
	hero.global_position = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	await get_tree().create_timer(0.1).timeout
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.2, 4.0, 10.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(1.0, 1.0, 0.0)
	add_child(wall)
	hero.input.move = Vector3.RIGHT
	hero.try_dodge()
	await get_tree().create_timer(0.4).timeout
	check(hero.global_position.x < 0.65, "dodge collides with walls instead of teleporting through")
	wall.queue_free()
	hero.global_position = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	hero.input.clear()
	hero.health = Hero.MAX_HEALTH
	hero.dodge_cooldown = 0.0
	hero.face_toward(Vector3.FORWARD)
	var thug: Thug = preload("res://scenes/npc/thug.tscn").instantiate()
	add_child(thug)
	thug.position = Vector3(0.0, 0.0, -1.7)
	thug.setup(hero, 1, PI)
	var deadline := 5.0
	var evaded := false
	while deadline > 0.0 and hero.counter_time <= 0.0:
		await get_tree().physics_frame
		deadline -= 1.0 / 60.0
		if not evaded and thug.state == Thug.State.PUNCH and thug.punch_time_remaining() <= 0.1:
			hero.input.dodge_held = true
			evaded = true
	check(hero.counter_time > 0.0 and hero.health == Hero.MAX_HEALTH, "real thug windup and impact award timed evasion")
	print("Dodge checks: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
