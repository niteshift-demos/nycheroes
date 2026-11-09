class_name TrialPilot
extends RefCounted
## Steers a hero toward points in the city the way a player at the keyboard
## would, for tests/time_trial_test.gd and tests/time_trial_recording.gd: it
## fills the hero's HeroInput each physics tick (the stick relative to the
## camera, which it turns toward where it's going, as the mouse would) and
## holds sprint (super speed) only on a straight run with room to slow down
## before the point. Nothing about the hero's movement is changed.

## On foot, the hero brakes at about this rate (m/s², OnFootMode.braking).
const BRAKING := 60.0
## Sprint only with the hero heading this close to the point (cosine).
const SPRINT_ALIGNMENT := 0.97

var hero: Hero
var camera: ThirdPersonCamera
## Off: run at running speed only.
var sprint := true
## Sprint stops this much earlier than the braking distance (m).
var sprint_margin := 15.0


func _init(driven: Hero, rig: ThirdPersonCamera) -> void:
	hero = driven
	camera = rig


## One tick of input toward a world position; returns the horizontal
## distance left to it.
func steer(target: Vector3, delta: float) -> float:
	var at := hero.world_position()
	var to := Vector3(target.x - at.x, 0.0, target.z - at.z)
	var distance := to.length()
	var direction := to / maxf(distance, 0.001)
	turn_camera(direction, delta)
	var local := Basis(Vector3.UP, camera.yaw).inverse() * direction
	var input := hero.input
	input.stick = Vector2(local.x, local.z).limit_length(1.0)
	input.move = Basis(Vector3.UP, camera.yaw) * Vector3(input.stick.x, 0.0, input.stick.y)
	input.aim = camera.aim_direction()
	var speed := hero.horizontal_speed()
	var heading := Vector3(hero.velocity.x, 0.0, hero.velocity.z).normalized() if speed > 1.0 else direction
	var stopping := speed * speed / (2.0 * BRAKING) + speed * 0.25
	input.sprint_held = sprint and heading.dot(direction) > SPRINT_ALIGNMENT and distance > stopping + sprint_margin
	return distance


## Swings the camera toward a direction on the ground, as a player would.
func turn_camera(direction: Vector3, delta: float, rate := 4.0) -> void:
	camera.yaw = lerp_angle(camera.yaw, atan2(-direction.x, -direction.z), 1.0 - exp(-rate * delta))
