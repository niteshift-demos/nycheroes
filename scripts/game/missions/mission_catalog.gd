class_name MissionCatalog
extends RefCounted
## Small starter routes, authored in WGS84 and converted with the tile projection.
## Coordinate sources and height choices are listed in docs/MISSIONS.md.

static func at(lat: float, lon: float, height := 20.0) -> Vector3:
	return Geo.to_world(lat, lon) + Vector3.UP * height


static func all() -> Array[Mission]:
	var takedown := make("times_square", "Times Square Takedown", 5000,
		"Two crews are shaking down Broadway. Use punches or a landing slam to clear both gangs.",
		at(40.75855, -73.98515))
	takedown.steps = [
		Mission.defeat_gang_at(at(40.75835, -73.98565), 3, "Clear the first Broadway gang"),
		Mission.defeat_gang_at(at(40.7575, -73.9858), 3, "Clear the second gang by One Times Square")]
	var courier := make("rooftop_courier", "Rooftop Courier", 8000,
		"A sky-high delivery. Fly to the Empire State roof, then race downtown to One World Trade.",
		at(40.74845, -73.9848))
	courier.steps = [
		Mission.go_to(at(40.7483, -73.9856, 400.0), 65.0, "Fly to the Empire State Building roof"),
		Mission.reach_in_time(at(40.71306, -74.01333, 435.0), 150.0, "Deliver to One World Trade's roof")]
	var bridge := make("bridge_run", "Bridge Run", 4500,
		"Take the skyline route! Sprint, swing or fly through four checkpoints across the Brooklyn Bridge.",
		at(40.7121, -74.0049))
	bridge.steps = [
		Mission.reach_in_time(at(40.7072684, -73.9983348, 45.0), 70.0, "Reach the Manhattan tower", 55.0),
		Mission.reach_in_time(at(40.705686, -73.9963447, 49.0), 55.0, "Cross the East River", 55.0),
		Mission.reach_in_time(at(40.7041035, -73.9943545, 45.0), 50.0, "Pass the Brooklyn tower", 55.0),
		Mission.reach_in_time(at(40.7005, -73.9898, 28.0), 50.0, "Finish in Brooklyn", 55.0)]
	var park := make("central_park", "Central Park Collectibles", 3500,
		"Eight lost power cells around Bethesda Terrace. Follow the gold diamonds and bring them home.",
		at(40.77365, -73.9714))
	var items: Array[Vector3] = [at(40.77365, -73.9714), at(40.7739, -73.9711),
		at(40.77405, -73.9716), at(40.77423, -73.97145), at(40.77435, -73.97095),
		at(40.77395, -73.97055), at(40.77365, -73.97075), at(40.7734, -73.97105)]
	park.steps = [Mission.collect(items, "Gather the eight Bethesda power cells", 12.0)]
	var dash := make("broadway_dash", "Broadway Dash", 1500,
		"A quick power check: follow Broadway south through two gold checkpoints. "
		+ ("Tap SPEED for super speed." if Device.wants_touch_controls() else "Hold Shift for super speed."),
		at(40.7580, -73.9855) + Vector3(15.0, 0.0, 0.0))
	dash.steps = [Mission.reach_in_time(at(40.75778, -73.98565), 40.0, "Sprint to the first Broadway checkpoint", 14.0),
		Mission.reach_in_time(at(40.7575, -73.9858), 40.0, "Finish at One Times Square", 14.0)]
	return [takedown, courier, bridge, park, dash]


static func make(id: String, title: String, reward: int, intro: String, giver: Vector3) -> Mission:
	var mission := Mission.new()
	mission.id = id
	mission.title = title
	mission.reward = reward
	mission.intro = intro
	mission.giver = giver
	return mission
