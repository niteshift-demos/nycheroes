class_name DodgeMode
extends HeroMode
## A committed ground step. Only the first 0.16 s avoids thug hits; the
## remaining recovery is vulnerable. World collision always stays enabled.

const DURATION := 0.36
const AVOID_TIME := 0.16
const COOLDOWN := 1.2
const SPEED := 13.0
var elapsed := 0.0
var _direction := Vector3.ZERO


func enter(_previous: StringName) -> void:
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	elapsed = 0.0
	hero.dodge_cooldown = COOLDOWN
	_direction = hero.input.move
	_direction.y = 0.0
	_direction = _direction.normalized() if _direction.length_squared() > 0.01 else -hero.forward()
	var on_foot := hero.get_mode(&"OnFoot") as OnFootMode
	on_foot.charging = false
	on_foot.charge = 0.0


func avoiding() -> bool:
	return elapsed < AVOID_TIME and hero.grounded() and not hero.is_in_water()


func physics_update(delta: float) -> StringName:
	elapsed += delta
	if hero.hurt_time > 0.0 or elapsed >= DURATION:
		return &"OnFoot"
	# Ease into recovery without steering; no attack, jump or flight cancel.
	var speed := SPEED * (1.0 - 0.65 * clampf(elapsed / DURATION, 0.0, 1.0))
	var vertical := -1.0 if hero.is_on_floor() else hero.velocity.y - Hero.GRAVITY * delta
	hero.velocity = _direction * speed + Vector3.UP * vertical
	hero.move_and_slide()
	return &""
