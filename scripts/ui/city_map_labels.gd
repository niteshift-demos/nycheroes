class_name CityMapLabels
extends RefCounted
## Sparse editorial labels in WGS84; Geo projects them exactly like city tiles.
## Screen-space collision rejection keeps names legible on phones and zoom out.

const PLACES := [
	["MANHATTAN", 40.789, -73.965, 0.0, 0.07, 0],
	["BROOKLYN", 40.650, -73.955, 0.0, 0.07, 0],
	["QUEENS", 40.731, -73.810, 0.0, 0.07, 0],
	["THE BRONX", 40.856, -73.866, 0.0, 0.07, 0],
	["STATEN ISLAND", 40.580, -74.150, 0.0, 0.07, 0],
	["HUDSON RIVER", 40.770, -74.005, 0.0, 0.15, 3],
	["UPPER BAY", 40.660, -74.060, 0.0, 0.10, 3],
	["ATLANTIC OCEAN", 40.515, -73.940, 0.0, 0.05, 3],
	["EAST RIVER", 40.776, -73.934, 0.025, 0.15, 3],
	["JAMAICA BAY", 40.612, -73.843, 0.0, 0.10, 3],
	["CENTRAL PARK", 40.7829, -73.9654, 0.018, 1.0, 2],
	["PROSPECT PARK", 40.6602, -73.9690, 0.018, 0.5, 2],
	["FLUSHING MEADOWS", 40.740, -73.840, 0.018, 0.5, 2],
	["VAN CORTLANDT PARK", 40.897, -73.886, 0.018, 0.5, 2],
	["GREENBELT", 40.588, -74.128, 0.018, 0.5, 2],
	["MIDTOWN", 40.754, -73.982, 0.04, 0.35, 1],
	["HARLEM", 40.813, -73.945, 0.04, 0.35, 1],
	["UPPER WEST SIDE", 40.789, -73.975, 0.04, 0.35, 1],
	["UPPER EAST SIDE", 40.773, -73.956, 0.04, 0.35, 1],
	["CHELSEA", 40.746, -74.001, 0.04, 0.35, 1],
	["GREENWICH VILLAGE", 40.733, -74.003, 0.04, 0.35, 1],
	["LOWER EAST SIDE", 40.717, -73.985, 0.04, 0.35, 1],
	["FINANCIAL DISTRICT", 40.707, -74.010, 0.04, 0.35, 1],
	["WILLIAMSBURG", 40.713, -73.957, 0.04, 0.35, 1],
	["DOWNTOWN BROOKLYN", 40.693, -73.988, 0.04, 0.35, 1],
	["ASTORIA", 40.765, -73.923, 0.04, 0.35, 1],
	["LONG ISLAND CITY", 40.746, -73.945, 0.04, 0.35, 1],
	["JACKSON HEIGHTS", 40.751, -73.882, 0.04, 0.35, 1],
	["FLUSHING", 40.761, -73.829, 0.04, 0.35, 1],
	["JAMAICA", 40.702, -73.800, 0.04, 0.35, 1],
	["ST. GEORGE", 40.643, -74.077, 0.04, 0.35, 1],
	["CONEY ISLAND", 40.577, -73.979, 0.025, 0.35, 1],
	["Times Square", 40.758, -73.9855, 0.075, 3.0, 4],
	["Empire State Building", 40.74844, -73.98566, 0.075, 3.0, 4],
	["Grand Central", 40.7527, -73.9772, 0.075, 3.0, 4],
	["Rockefeller Center", 40.7587, -73.9787, 0.075, 3.0, 4],
	["Brooklyn Bridge", 40.7061, -73.9969, 0.025, 3.0, 4],
	["Statue of Liberty", 40.68925, -74.0445, 0.018, 3.0, 4],
	["One World Trade Center", 40.71274, -74.01338, 0.075, 3.0, 4],
	["Yankee Stadium", 40.8296, -73.9262, 0.04, 3.0, 4],
	["JFK", 40.6413, -73.7781, 0.012, 0.3, 4],
	["LAGUARDIA", 40.7769, -73.8740, 0.012, 0.3, 4],
	["Broadway", 40.7622, -73.9832, 0.3, 3.0, 5],
	["7th Avenue", 40.7534, -73.9890, 0.3, 3.0, 5],
	["8th Avenue", 40.7594, -73.9896, 0.3, 3.0, 5],
	["5th Avenue", 40.7552, -73.9799, 0.3, 3.0, 5],
	["West 42nd Street", 40.7561, -73.9903, 0.3, 3.0, 5],
	["West 57th Street", 40.7663, -73.9809, 0.3, 3.0, 5],
	["FDR Drive", 40.7483, -73.9685, 0.15, 3.0, 5],
]
static var _world: Array[Vector3] = []


static func draw(canvas: Control, map: WorldMap) -> void:
	if _world.is_empty():
		for place: Array in PLACES:
			_world.append(Geo.to_world(place[1], place[2]))
	var occupied: Array[Rect2] = [Rect2(map.world_to_map(map.radar.world_center) - Vector2(12, 14), Vector2(60, 30))]
	var font := ThemeDB.fallback_font
	for i in PLACES.size():
		var place: Array = PLACES[i]
		if map.pixels_per_meter < float(place[3]) or map.pixels_per_meter > float(place[4]):
			continue
		var point := map.world_to_map(_world[i])
		var kind: int = place[5]
		var font_size := 18 if kind == 0 else 13 if kind != 5 else 12
		var text_size := font.get_string_size(place[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var label_point := point + Vector2(0, 32) if kind == 4 else point
		var rect := Rect2(label_point - text_size * 0.5, text_size).grow(6)
		if rect.position.y < map._header_height() + 8 or rect.end.y > map.size.y - 82 or rect.position.x < 12 or rect.end.x > map.size.x - 12:
			continue
		var overlaps := false
		for used in occupied:
			if rect.intersects(used):
				overlaps = true
				break
		if overlaps:
			continue
		occupied.append(rect)
		var color := Color("c9d6d9")
		if kind == 0 or kind == 4:
			color = Color("ffe0a2")
		elif kind == 2:
			color = Color("a5d1a8")
		elif kind == 3:
			color = Color("739daf")
		var baseline := label_point + Vector2(-text_size.x * 0.5, font_size * 0.35)
		canvas.draw_string_outline(font, baseline, place[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color("192c36"))
		canvas.draw_string(font, baseline, place[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		if kind == 4:
			canvas.draw_circle(point, 3, color)
