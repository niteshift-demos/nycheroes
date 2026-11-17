class_name PoliceLivery
extends Node3D
## Extra geometry keeps the existing car shader small. Paint 12 travels in
## ordinary driver snapshots too, so a stolen patrol car keeps its markings.

const PAINT := 12.0
var _red: StandardMaterial3D
var _blue: StandardMaterial3D
var _wait := 0.0
var _flash := false


func _ready() -> void:
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.03, 0.22, 0.65)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.025, 0.18, 3.9), Vector3(side * 0.916, 0.73, 0), stripe)
		var label := Label3D.new()
		label.text = "NYPD"
		label.font_size = 60
		label.pixel_size = 0.004
		label.modulate = Color(0.08, 0.32, 0.85)
		label.position = Vector3(side * 0.94, 1.0, 0)
		label.rotation.y = side * PI * 0.5
		add_child(label)
	var mount := StandardMaterial3D.new()
	mount.albedo_color = Color(0.08, 0.09, 0.12)
	_box(Vector3(1.45, 0.07, 0.35), Vector3(0, 1.53, -0.05), mount)
	_red = _lamp(Color(1.0, 0.025, 0.025))
	_blue = _lamp(Color(0.025, 0.18, 1.0))
	_box(Vector3(0.64, 0.18, 0.32), Vector3(-0.37, 1.64, -0.05), _red)
	_box(Vector3(0.64, 0.18, 0.32), Vector3(0.37, 1.64, -0.05), _blue)


func _lamp(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	return material


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = material
	visual.position = at
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.16
	var car := get_parent() as DriveVehicle
	if car and car.health <= 0.0:
		_red.emission_energy_multiplier = 0.0
		_blue.emission_energy_multiplier = 0.0
		_red.albedo_color = Color(0.05, 0.02, 0.02)
		_blue.albedo_color = Color(0.02, 0.02, 0.05)
		return
	_flash = not _flash
	_red.emission_energy_multiplier = 4.0 if _flash else 0.0
	_blue.emission_energy_multiplier = 0.0 if _flash else 4.0
	_red.albedo_color = Color(1, 0.03, 0.03) if _flash else Color(0.15, 0.01, 0.01)
	_blue.albedo_color = Color(0.01, 0.02, 0.15) if _flash else Color(0.03, 0.18, 1)
