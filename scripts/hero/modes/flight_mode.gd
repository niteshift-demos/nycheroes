class_name FlightMode
extends HeroMode
## Free flight: the stick steers relative to where the camera looks, Space/C
## climb and descend, Shift boosts. Descending onto the ground lands.
##
## The air brake (Q, the left trigger, or BRAKE on touch screens) sheds speed
## hard and holds the hero in a hover, even with the stick pushed: letting go
## of everything only eases off (hover_damping), which from full boost drifts
## a block or more and never quite stops. Climbing or descending still works
## while braking, so a hero can brake out of a boost and drop straight down
## onto a roof.

@export var cruise_speed := 33.0
@export var boost_speed := 150.0
## Sustained boost builds to 187.5 m/s over six seconds of actual flight.
@export var sustained_boost_multiplier := 1.25
@export var boost_ramp_seconds := 6.0
@export var acceleration := 40.0
@export var boost_acceleration := 100.0
## How quickly the hero comes to a hover with no input (per second).
@export var hover_damping := 2.5
## The air brake slows by a constant part (m/s^2) plus a part that grows with
## speed (per second): hardest at full boost, so a long boost doesn't take a
## long way to stop, while the last few m/s go at a steady pace. From the 187.5 m/s of
## a sustained boost it stops in about 0.8 s and 47 m (150 m/s: 36 m; cruise:
## 4.5 m), where letting go of everything drifts 75 m and keeps creeping.
@export var brake_deceleration := 60.0
@export var brake_damping := 3.0

## Holding the air brake this tick (copies of other players' heroes get it
## from PlayerSync, to draw the braking pose and play its sound).
var braking := false
var _boost_time := 0.0


func enter(_previous: StringName) -> void:
	_boost_time = 0.0
	braking = false
	hero.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func exit() -> void:
	_boost_time = 0.0
	braking = false
	hero.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED


func physics_update(delta: float) -> StringName:
	var input := hero.input
	if input.fly_toggle_pressed:
		return &"OnFoot"
	if hero.attack_pressed:
		return &"Dive"

	var forward := input.aim
	var right := forward.cross(Vector3.UP).normalized()
	var wish := forward * -input.stick.y + right * input.stick.x + Vector3.UP * input.vertical
	braking = input.brake_held
	if braking:
		# Everything but the climb or descent asked for goes; the stick and
		# boost wait until the brake is let go.
		_boost_time = 0.0
		var target := Vector3.UP * clampf(input.vertical, -1.0, 1.0) * cruise_speed
		var rate := brake_deceleration + brake_damping * hero.velocity.distance_to(target)
		hero.velocity = hero.velocity.move_toward(target, rate * delta)
	elif wish.length() > 0.05:
		var boosting := input.sprint_held
		# Don't charge while hovering or pushing into a wall. Releasing boost
		# starts the next run at the normal boost speed.
		if boosting and hero.velocity.dot(wish.normalized()) > cruise_speed:
			_boost_time = minf(_boost_time + delta, boost_ramp_seconds)
		else:
			_boost_time = 0.0
		var ramp := clampf(_boost_time / maxf(boost_ramp_seconds, 0.001), 0.0, 1.0)
		var speed := boost_speed * lerpf(1.0, sustained_boost_multiplier, ramp) if boosting else cruise_speed
		var target := wish.limit_length(1.0) * speed
		hero.velocity = hero.velocity.move_toward(target, (boost_acceleration if boosting else acceleration) * delta)
	else:
		_boost_time = 0.0
		hero.velocity *= exp(-hover_damping * delta)
	hero.move_and_slide()

	var flat := Vector3(hero.velocity.x, 0.0, hero.velocity.z)
	hero.face_toward(flat if flat.length() > 2.0 else forward, 6.0 * delta)
	if input.vertical < 0.0 and _touching_ground():
		return &"OnFoot"
	return &""


## How far the air brake takes to stop from `speed` (m/s), in meters: the
## distance covered while dv/dt = -(brake_deceleration + brake_damping * v).
## The HUD shows it while braking.
func stopping_distance(speed: float) -> float:
	if speed <= 0.0:
		return 0.0
	var k := maxf(brake_damping, 0.001)
	var a := maxf(brake_deceleration, 0.001)
	return speed / k - a / (k * k) * log(1.0 + k * speed / a)


## Speed the air brake is taking away: everything but the climb or descent
## asked for.
func speed_to_shed() -> float:
	var target := Vector3.UP * clampf(hero.input.vertical, -1.0, 1.0) * cruise_speed
	return hero.velocity.distance_to(target)


func _touching_ground() -> bool:
	for i in hero.get_slide_collision_count():
		if hero.get_slide_collision(i).get_normal().y > 0.7:
			return true
	return false
