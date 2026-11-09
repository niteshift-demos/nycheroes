class_name LandmarkDiscovery
extends Node
## Exploration: a short list of the city's hand-modeled landmarks (see
## tools/citygen/landmarks.py) to find by going there. The hero discovers one
## by coming within its radius (measured flat, so flying over counts, up to
## MAX_ALTITUDE); the HUD then shows its name and a line about it, counts how
## many have been found, and points to the nearest one still to find.
##
## Progress lasts for this session only (a reload starts over) and is this
## player's own: in co-op every player discovers for themselves, and nothing
## here is synced (it isn't hero state; PlayerSync carries the hero as before).
## Positions are world positions (Geo.to_world of each landmark's latitude and
## longitude, the tiles' own projection), compared with Hero.world_position(),
## so floating origin shifts don't matter.

## A landmark was discovered: its index in LANDMARKS, and the session's count.
signal discovered(index: int, found: int, total: int)

## How often discoveries are checked (seconds): even super speed (~60 m/s)
## moves less than a radius in between.
const CHECK_INTERVAL := 0.2
## Above this (m above sea level) nothing is discovered: from 600 m up the
## whole of midtown is "near". The Empire State's antenna tops out at 443 m.
const MAX_ALTITUDE := 600.0
## The curated landmarks: name, latitude, longitude (their middles: for the
## buildings, the footprint's; Columbus Circle, the Unisphere and the Wonder
## Wheel at the points their models are anchored to in landmarks.py), radius
## (m: about the building's half-size plus its sidewalks), the height its HUD
## marker points at (m above sea level, around the top of what's seen from
## the street) and a line shown when it's found.
const LANDMARKS: Array[Dictionary] = [
	{"name": "Times Square", "lat": 40.7580, "lon": -73.9855, "radius": 90.0, "height": 40.0,
		"line": "The Crossroads of the World, where Broadway meets Seventh Avenue."},
	{"name": "New York Times Building", "lat": 40.75625, "lon": -73.98995, "radius": 75.0, "height": 120.0,
		"line": "Renzo Piano's tower of ceramic rods on Eighth Avenue (2007)."},
	{"name": "New York Public Library", "lat": 40.75318, "lon": -73.98225, "radius": 90.0, "height": 30.0,
		"line": "Patience and Fortitude guard the marble steps on Fifth Avenue (1911)."},
	{"name": "Grand Central Terminal", "lat": 40.75273, "lon": -73.97723, "radius": 110.0, "height": 40.0,
		"line": "The Beaux-Arts terminal and its clock over 42nd Street (1913)."},
	{"name": "Chrysler Building", "lat": 40.75162, "lon": -73.97554, "radius": 70.0, "height": 250.0,
		"line": "Stainless steel arches and eagles on Lexington Avenue (1930)."},
	{"name": "Empire State Building", "lat": 40.748441, "lon": -73.985656, "radius": 100.0, "height": 330.0,
		"line": "102 floors on Fifth Avenue and 34th Street (1931)."},
	{"name": "Flatiron Building", "lat": 40.74106, "lon": -73.98965, "radius": 70.0, "height": 70.0,
		"line": "The wedge between Broadway and Fifth Avenue (1902)."},
	{"name": "30 Rockefeller Plaza", "lat": 40.75874, "lon": -73.97870, "radius": 75.0, "height": 200.0,
		"line": "The heart of Rockefeller Center, with the Top of the Rock (1933)."},
	{"name": "Radio City Music Hall", "lat": 40.75998, "lon": -73.97997, "radius": 70.0, "height": 30.0,
		"line": "The Showplace of the Nation's neon marquee on Sixth Avenue (1932)."},
	{"name": "St. Patrick's Cathedral", "lat": 40.75846, "lon": -73.97600, "radius": 75.0, "height": 90.0,
		"line": "Twin Gothic spires on Fifth Avenue (1878)."},
	{"name": "Columbus Circle", "lat": 40.768068, "lon": -73.981892, "radius": 90.0, "height": 25.0,
		"line": "The column at the corner of Central Park, where distances from the city are measured."},
	{"name": "One World Trade Center", "lat": 40.71274, "lon": -74.01338, "radius": 100.0, "height": 400.0,
		"line": "1,776 feet: the tallest building in the Western Hemisphere (2014)."},
	{"name": "Statue of Liberty", "lat": 40.689249, "lon": -74.0445, "radius": 120.0, "height": 90.0,
		"line": "Liberty Enlightening the World, on Liberty Island (1886)."},
	{"name": "Unisphere", "lat": 40.746404, "lon": -73.845076, "radius": 80.0, "height": 40.0,
		"line": "The steel globe of the 1964 World's Fair in Flushing Meadows."},
	{"name": "Wonder Wheel", "lat": 40.574065, "lon": -73.979146, "radius": 80.0, "height": 45.0,
		"line": "Coney Island's swinging Ferris wheel (1920)."},
]

var hero: Hero

## World positions (y 0) of LANDMARKS, in the same order.
var positions: PackedVector3Array = []
## Which LANDMARKS have been found this session.
var found: Array[bool] = []
var _found_count := 0
var _since_check := 0.0


func _ready() -> void:
	for landmark in LANDMARKS:
		positions.append(Geo.to_world(landmark.lat, landmark.lon))
		found.append(false)


func _physics_process(delta: float) -> void:
	_since_check += delta
	if _since_check < CHECK_INTERVAL or hero == null or hero.frozen:
		return  # (frozen: still placed or loading, not there yet)
	_since_check = 0.0
	check(hero.world_position())


## Discovers any landmark within reach of a world position; returns how many
## were new.
func check(world_position: Vector3) -> int:
	if world_position.y > MAX_ALTITUDE:
		return 0
	var new := 0
	for n in positions.size():
		if not found[n] and flat_distance(n, world_position) <= float(LANDMARKS[n].radius):
			found[n] = true
			_found_count += 1
			new += 1
			discovered.emit(n, _found_count, positions.size())
	return new


func found_count() -> int:
	return _found_count


func total() -> int:
	return positions.size()


## Horizontal distance (m) from landmark `n` to a world position.
func flat_distance(n: int, world_position: Vector3) -> float:
	return Vector2(positions[n].x - world_position.x, positions[n].z - world_position.z).length()


## The landmark not yet found nearest a world position, or -1 when all are.
func nearest_unfound(world_position: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for n in positions.size():
		if found[n]:
			continue
		var distance := flat_distance(n, world_position)
		if distance < best_distance:
			best_distance = distance
			best = n
	return best
