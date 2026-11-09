class_name KnockedOutMode
extends HeroMode
## Out of health: the hero lies on the ground for a few seconds, then gets up
## with some health (HealthRecovery.KO_HEALTH, not full: the rest comes back
## out of combat) and a burst that shoves nearby thugs back.

@export var down_time := 3.5

var _time := 0.0


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_time = 0.0


func physics_update(delta: float) -> StringName:
	_time += delta
	var horizontal := Vector3(hero.velocity.x, 0.0, hero.velocity.z).move_toward(Vector3.ZERO, 20.0 * delta)
	var vertical := 0.0 if hero.is_on_floor() else hero.velocity.y - Hero.GRAVITY * delta
	hero.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	hero.move_and_slide()
	if _time < down_time:
		return &""
	hero.health = maxf(hero.health, HealthRecovery.KO_HEALTH)
	hero.recovery.interrupt()
	Combat.shockwave(hero.global_position, 6.0, 0.0, 12.0)
	return &"OnFoot"
