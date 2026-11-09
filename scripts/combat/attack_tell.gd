class_name AttackTell
extends MeshInstance3D
## A thug's wind-up tell: a faint wedge on the ground over exactly where its
## punch will land (Thug.PUNCH_REACH, Thug.PUNCH_CONE), with a band sweeping
## out from the thug that reaches the wedge's edge the moment the punch lands.
## A hero still inside the wedge then is hit; one that got out (or jumped
## above Thug.REACH_HEIGHT) isn't. Driven every tick by the thug's own attack
## state, so it shows the real timing (see Thug), on copies of thugs too.
## Kept faint so a fight with several thugs doesn't turn into a carpet of
## warnings. A child of the thug, so it follows origin shifts with it.

const SHADER := preload("res://shaders/attack_tell.gdshader")
## Seconds to fade out once the punch has landed (or was cut short).
const FADE_TIME := 0.15
## Just above the ground, under the thug's feet.
const LIFT := 0.06

static var _mesh: PlaneMesh

var _material: ShaderMaterial
var _fade := 0.0


static func create(reach: float, cone: float) -> AttackTell:
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2.ONE
	var tell := AttackTell.new()
	tell.mesh = _mesh
	tell._material = ShaderMaterial.new()
	tell._material.shader = SHADER
	tell._material.set_shader_parameter("cone", cone)
	tell.material_override = tell._material
	tell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tell.scale = Vector3(reach * 2.0, 1.0, reach * 2.0)
	tell.position = Vector3.UP * LIFT
	tell.visible = false
	return tell


## The punch is winding up: `progress` 0 at its start, 1 when it lands;
## `facing` is the thug's facing (radians, as Thug.facing()).
func wind_up(progress: float, facing: float) -> void:
	_fade = 0.0
	rotation.y = facing
	_material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	_material.set_shader_parameter("strength", 1.0)
	visible = true


## The punch landed or was cut short: fade out over FADE_TIME.
func finish() -> void:
	if visible and _fade <= 0.0:
		_fade = FADE_TIME


## Gone at once (the thug went down).
func hide_now() -> void:
	_fade = 0.0
	visible = false


func _process(delta: float) -> void:
	if _fade <= 0.0:
		return
	_fade -= delta
	if _fade <= 0.0:
		visible = false
	else:
		_material.set_shader_parameter("strength", _fade / FADE_TIME)
