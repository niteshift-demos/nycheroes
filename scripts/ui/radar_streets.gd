class_name RadarStreets
extends Node2D
## Retained canvas commands for loaded streets. Tile changes rebuild only that
## tile; moving a map changes this node's transform, never its road geometry.

class StreetTile extends Node2D:
	var segments := PackedVector2Array()

	func _draw() -> void:
		if not segments.is_empty():
			draw_multiline(segments, Color("8d9caa"), 5.0)

var _tiles: Dictionary[Vector2i, StreetTile] = {}


func set_tile(key: Vector2i, segments: PackedVector2Array) -> void:
	if _tiles.has(key):
		_tiles[key].free()
		_tiles.erase(key)
	if segments.is_empty():
		return
	var tile := StreetTile.new()
	tile.segments = segments
	_tiles[key] = tile
	add_child(tile)


## X east, Z south maps directly to screen X right, Y down when north-up.
func place(center: Vector2, world_center: Vector2, heading: float, pixels_per_meter: float) -> void:
	rotation = heading
	scale = Vector2.ONE * pixels_per_meter
	position = center - world_center.rotated(heading) * pixels_per_meter
