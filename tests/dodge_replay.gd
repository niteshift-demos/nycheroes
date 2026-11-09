extends Node
## Native Movie Maker evidence: drives ONLY ordinary HeroInput, never hero or
## world state. Uses normal solo/spawn/quality/gang launch options. AI varies.
## See docs/ROADMAP.md for recording commands and the limitations shown.
var world: Game
var hero: Hero
var time := -1.0
var last_mode: StringName
var last_caption := ""
var waiting := 0.0


func _ready() -> void:
	world = preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	hero = world.hero
	world.player_input.process_mode = Node.PROCESS_MODE_DISABLED
	process_physics_priority = -20
	hero.hurt.connect(func(damage: float) -> void: print("[replay] damage %.0f at %.2f health %.0f" % [damage, time, hero.health]))


func caption(text: String) -> void:
	if text != last_caption:
		last_caption = text
		(world.hud.get_node("GameHud") as GameHud).notify(text)
		print("[replay] ", text)


func _physics_process(delta: float) -> void:
	hero.input.clear()
	if time < 0.0:
		if hero.frozen or world.city.pending_count() > 0:
			return
		waiting += delta
		if waiting < 3.0:
			return
		time = 0.0
		print("[replay] START frame ", Engine.get_frames_drawn())
	time += delta
	if hero.mode.name != last_mode:
		last_mode = hero.mode.name
		print("[replay] mode %s at %.2f health %.0f cooldown %.2f" % [last_mode, time, hero.health, hero.dodge_cooldown])
	var nearest: Thug
	var distance := INF
	for thug in Combat.thugs:
		if not thug.is_down():
			var gap := thug.global_position.distance_to(hero.global_position)
			if gap < distance:
				distance = gap
				nearest = thug
	if nearest:
		var toward := nearest.global_position - hero.global_position
		toward.y = 0.0
		hero.input.aim = toward.normalized()
		if distance > 2.5 and time < 23.0:
			hero.input.move = toward.normalized()
	if time < 7.0:
		caption("Combat dodge · Q / R3 / touch DODGE · ground only")
	elif time < 18.0:
		caption("Tap to backstep · 0.16 s avoidance · 1.2 s cooldown")
		hero.input.move = Vector3.ZERO
		# React through input to a normal AI punch, without changing the AI.
		for thug in Combat.thugs:
			if thug.state == Thug.State.PUNCH and thug._timer < 0.14 and hero.can_dodge():
				hero.input.dodge_held = true
	elif time < 23.0:
		caption("Holding never repeats · recovery can still take damage")
		hero.input.move = Vector3.ZERO
		hero.input.dodge_held = true
	elif time < 29.0:
		caption("Dodge then counter with normal punches")
		hero.input.attack_held = fmod(time, 0.4) < 0.12
	else:
		caption("Ground only: no air dodge · walls remain solid")
		hero.input.jump_held = time < 29.15
		hero.input.dodge_held = time > 29.5 and fmod(time, 0.5) < 0.1
	if time >= 33.0:
		print("[replay] END frame ", Engine.get_frames_drawn())
		get_tree().quit()
