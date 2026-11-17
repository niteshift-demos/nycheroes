class_name CityMapAtlas
extends Node2D
## Retained north-up map tiles, shared by radar and map. The overview is always
## available; detail loads one image per frame and only inside the visible rect.
## No city geometry or GPU render targets are built while the camera moves.

const ORIGIN := Vector2(-24576, -18432)
const EXTENT := 49152.0
const LEVEL_PIXELS := [1024, 2048, 8192]
const OVERVIEW: Texture2D = preload("res://assets/map/0/0_0.webp")
## Bound shared texture memory to roughly 48 MiB, plus visible tiles/overview.
const CACHE_LIMIT := 12
static var _cache: Dictionary[String, Texture2D] = {}
static var _recent: Array[String] = []
var _tiles: Dictionary[String, Sprite2D] = {}
var _pending: Array[String] = []
var _region := Rect2i()
var _level := -1
var _last_check := -1000


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var overview := Sprite2D.new()
	overview.texture = OVERVIEW
	overview.centered = false
	overview.position = ORIGIN
	overview.scale = Vector2.ONE * EXTENT / 1024.0
	add_child(overview)


## Pixel edge coordinates in a selected bake level, useful for geographic tests.
static func world_to_pixel(world: Vector3, level := 2) -> Vector2:
	return (Vector2(world.x, world.z) - ORIGIN) * float(LEVEL_PIXELS[level]) / EXTENT


func place(center: Vector2, world: Vector2, heading: float, ppm: float, viewport_size: Vector2) -> void:
	rotation = heading
	scale = Vector2.ONE * ppm
	position = center - world.rotated(heading) * ppm
	# Geometry stays retained; check tile visibility at most ten times a second.
	var now := Time.get_ticks_msec()
	if now - _last_check < 100:
		return
	_last_check = now
	var level := 2 if ppm > 0.06 else 1 if ppm > 0.025 else 0
	var width := EXTENT / float(LEVEL_PIXELS[level] / 1024)
	var half := viewport_size * 0.5 / ppm
	if not is_zero_approx(heading):
		half = Vector2.ONE * half.length()
	var low := Vector2i(((world - half - ORIGIN) / width).floor()).max(Vector2i.ZERO)
	var count := int(LEVEL_PIXELS[level] / 1024)
	var high := Vector2i(((world + half - ORIGIN) / width).floor()).min(Vector2i.ONE * (count - 1))
	var region := Rect2i(low, (high - low + Vector2i.ONE).max(Vector2i.ZERO))
	if region == _region and level == _level:
		return
	_region = region
	_level = level
	var wanted: Dictionary[String, Vector2] = {}
	if level > 0:
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				wanted["res://assets/map/%d/%d_%d.webp" % [level, x, y]] = ORIGIN + Vector2(x, y) * width
	for path: String in _tiles.keys():
		if not wanted.has(path):
			_tiles[path].queue_free()
			_tiles.erase(path)
	_pending.clear()
	for path: String in wanted:
		if _tiles.has(path):
			if not _tiles[path].texture:
				_pending.append(path)
			continue
		var tile := Sprite2D.new()
		tile.centered = false
		tile.position = wanted[path]
		tile.scale = Vector2.ONE * width / 1024.0
		add_child(tile)
		_tiles[path] = tile
		_pending.append(path)


func _process(_delta: float) -> void:
	if _pending.is_empty() or not is_visible_in_tree():
		return
	var path: String = _pending.pop_front()
	if not _cache.has(path):
		_cache[path] = load(path) as Texture2D
	_recent.erase(path)
	_recent.append(path)
	_tiles[path].texture = _cache[path]
	while _recent.size() > CACHE_LIMIT:
		_cache.erase(_recent.pop_front())
