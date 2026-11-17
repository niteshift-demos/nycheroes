class_name StoryCatalog
extends RefCounted
## Original campaign: The Borrowed Skyline. WGS84 references, heights and
## route checks live in docs/STORY.md. No existing fictional characters.

const MARA := Color("39c6bf")
const HERO := Color("ffcf66")
const VOSS := Color("ed6975")


static func at(lat: float, lon: float, height := 20.0) -> Vector3:
	return MissionCatalog.at(lat, lon, height)


static func call_line(speaker: String, line: String, color := MARA) -> Dictionary:
	return {speaker = speaker, line = line, color = color}


static func job(chapter: int, title: String, reward: int, giver: Vector3,
		lines: Array[Dictionary], steps: Array[Dictionary]) -> Mission:
	var mission := MissionCatalog.make("story_%02d" % chapter, title, reward,
		"The Borrowed Skyline · Chapter %d / 12" % chapter, giver)
	mission.chapter = chapter
	mission.calls = lines
	mission.steps = steps
	return mission


static func all() -> Array[Mission]:
	var square := at(40.75835, -73.98565, 14.5)
	var esb := at(40.74845, -73.9848)
	var fdr := at(40.7440, -73.9718, 2.0)
	var dumbo := at(40.7033, -73.9894, 4.2)
	var queens := at(40.7460, -73.8446, 5.7)
	var coney := at(40.5754, -73.9816, 2.1)
	var bronx := at(40.8274, -73.9257, 10.0)
	var ferry := at(40.6432, -74.0748, 11.4)
	var bridge := at(40.7121, -74.0049, 10.6)
	var astoria := at(40.77869, -73.92114, 15.2)
	var trade := at(40.7120, -74.0130, 2.0)
	var roof := at(40.748455, -73.985382, 314.0)
	return [
		job(1, "A City on Loan", 10000, square, [
			call_line("Mara Vale", "New in town? I dispatch night repairs. Someone is charging our crews to cross their own streets."),
			call_line("You", "I came looking for a fresh start. Point me at the toll booth.", HERO)], [
			Mission.go_to(square + Vector3(0, 0, 42), 28.0, "Meet Mara's crew on Broadway"),
			Mission.defeat_gang_at(square, 3, "Stop the Tollkeepers' collection crew"),
			with_call(Mission.fly_through([square + Vector3(0, 65, 0), at(40.7550, -73.9859, 110), at(40.7515, -73.9856, 170)], "F: fly through Mara's gold sky rings"),
				"Mara Vale", "They call themselves the Tollkeepers. That stolen relay on the roof is how they pick their victims.")]),
		job(2, "Above the Noise", 12000, esb, [
			call_line("Mara Vale", "Their rooftop couriers carry repair-worker IDs. Retrieve the copies before they sell another night shift.")], [
			Mission.fly_through([at(40.7490, -73.9863, 130), at(40.7488, -73.9859, 240), roof + Vector3(0, 50, 0)], "Follow the courier's rooftop trail"),
			Mission.collect([roof + Vector3(0, 35, 0), roof + Vector3(35, 45, 0), roof + Vector3(0, 60, 35)], "Intercept three airborne ID packets", 24),
			with_call(Mission.go_to(esb, 40, "Return the IDs to the Fifth Avenue crew"), "Mara Vale", "A van on the FDR is carrying the original ledger. Keep it intact enough to read.")]),
		job(3, "East River Receipt", 15000, fdr, [
			call_line("Mara Vale", "Take the marked recovery car. Catch the ledger van on the FDR. Ram it, or get out and hit it with your powers."),
			call_line("You", "And after the van stops?", HERO),
			call_line("Mara Vale", "They cloned an emergency plate. The police will have questions. Lose their sight.")], [
			Mission.steal_car(fdr, "G: take the marked recovery car"),
			Mission.drive_to(fdr + Vector3(0, 0, -45), "Drive onto the marked FDR approach", 55),
			Mission.chase(fdr, "Stop the ledger van · ram or punch it"),
			Mission.escape_wanted(fdr, 1, "Lose the wanted star · fly high or break sight")]),
		job(4, "Someone Must Stay", 18000, dumbo, [
			call_line("Mara Vale", "The ledger names our witness, Ivo Chen. He is under the Manhattan Bridge in Brooklyn. Keep him alive while his upload runs.")], [
			Mission.go_to(dumbo, 35, "Find Ivo on Washington Street, DUMBO"),
			Mission.protect(dumbo, 65, "Protect Ivo · stay near the blue beacon"),
			with_call(Mission.collect([dumbo + Vector3(8, 0, 0)], "Recover Ivo's uploaded evidence", 16), "Ivo Chen", "Three lieutenants hold borough keys. Break the Queens relay first. Then their boss cannot erase me.")]),
		job(5, "Public Frequency", 20000, queens, [
			call_line("Mara Vale", "Flushing Meadows, by the Unisphere. Those service cars are jamming Ivo's upload. Smash the transmitters, then take the signal above the trees.")], [
			Mission.destroy(at(40.74534, -73.84699), 3, "Destroy three marked relay cars"),
			Mission.collect([queens + Vector3(15, 0, 0), queens + Vector3(-15, 0, 0)], "Collect the relay keys", 15),
			Mission.fly_through([queens + Vector3(0, 100, 0), at(40.7498, -73.8465, 180), at(40.7526, -73.8463, 220)], "Broadcast above Flushing Meadows")]),
		job(6, "No Free Ride", 25000, coney, [
			call_line("Mara Vale", "Lieutenant Nera Flint runs the southern tolls from Surf Avenue, Coney Island. Her powered brace lets her charge. Rise when she winds up."),
			call_line("Nera Flint", "This city gave me nothing. I collect the difference.", VOSS)], [
			Mission.defeat_gang_at(coney, 4, "Clear Flint's Surf Avenue crew"),
			Mission.boss(coney + Vector3(12, 0, 0), 1, "Defeat Nera Flint · dodge the charge"),
			Mission.fly_through([coney + Vector3(0, 90, 0), at(40.5741, -73.9775, 130)], "Lift the first borough key clear of Coney Island")]),
		job(7, "Home Crowd", 30000, bronx, [
			call_line("Mara Vale", "Lieutenant Oren Pike is outside Yankee Stadium on River Avenue. His stolen lift rig makes a ground slam. Jump or fly over the wave.")], [
			Mission.protect(bronx, 45, "Protect the stadium electrician"),
			Mission.boss(bronx + Vector3(10, 0, 0), 2, "Defeat Oren Pike · rise above his slam"),
			Mission.collect([bronx + Vector3(0, 8, 0)], "Take the second borough key", 20)]),
		job(8, "Last Boat Out", 35000, ferry, [
			call_line("Mara Vale", "St. George, Staten Island. Lieutenant Sable Quill plans to move the keys by ferry. Stop the cars outside the terminal, then stop her."),
			call_line("Sable Quill", "Every exit belongs to someone. Today, it belongs to me.", VOSS)], [
			Mission.destroy(ferry, 2, "Smash Quill's terminal relay cars"),
			Mission.defeat_gang_at(ferry, 4, "Clear the terminal crew"),
			Mission.boss(ferry + Vector3(8, 0, 0), 3, "Defeat Sable Quill and take the third key")]),
		job(9, "A Bridge for Everyone", 40000, bridge, [
			call_line("Mara Vale", "All three keys expose Alden Voss. He has closed the Brooklyn Bridge approach with relay cars. Borrow a car, break his roadblock, reopen the crossing.")], [
			Mission.steal_car(bridge, "Take the marked bridge maintenance car"),
			Mission.drive_to(at(40.7118, -74.0037), "Drive to the Brooklyn Bridge approach", 65),
			Mission.destroy(at(40.7118, -74.0037), 2, "Break the bridge approach roadblock"),
			Mission.fly_through([at(40.7072684, -73.9983348, 90), at(40.705686, -73.9963447, 110), at(40.7041035, -73.9943545, 90)], "Carry the public signal over Brooklyn Bridge", 35)]),
		job(10, "The Last Collection", 42000, astoria, [
			call_line("Mara Vale", "Voss's last courier is fleeing along Astoria Park. Take the car, catch him, then shake the false alert. That ledger buys us the roof access codes.")], [
			Mission.steal_car(astoria, "Take the marked Astoria recovery car"),
			Mission.chase(astoria, "Stop Voss's last courier"),
			Mission.escape_wanted(astoria, 2, "Lose two wanted stars with your powers")]),
		job(11, "Open Circuit", 45000, trade, [
			call_line("Mara Vale", "The master relay is outside One World Trade. Break it and collect the access code. Then fly north. Voss is waiting above the Empire State Building."),
			call_line("You", "A whole skyline for one frightened man.", HERO)], [
			Mission.defeat_gang_at(trade, 5, "Clear the master relay guards"),
			Mission.destroy(trade, 3, "Destroy the master relay cars"),
			Mission.collect([trade + Vector3(0, 5, 0)], "Collect Voss's roof access code", 20),
			Mission.fly_through([at(40.7200, -74.0080, 180), at(40.7350, -73.9950, 260), roof + Vector3(0, 45, 0)], "Follow Mara's flight corridor to Midtown", 40)]),
		job(12, "The Borrowed Skyline", 50000, esb, [
			call_line("Alden Voss", "I kept the lights on. Why should a city be free?", VOSS),
			call_line("Mara Vale", "Because everyone below you already paid for it. Get to the Empire State roof. His rig charges, then slams. Watch the gold warning."),
			call_line("You", "I have been here one night. Long enough to know whose city this is.", HERO)], [
			Mission.fly_through([roof + Vector3(70, 60, 0), roof + Vector3(0, 45, 0)], "Ascend to the Empire State Building", 35),
			Mission.boss(roof, 4, "Defeat Alden Voss · charge and slam rig"),
			with_call(Mission.fly_through([roof + Vector3(0, 70, 0), at(40.7580, -73.9855, 180)], "Return the skyline to the city"), "Mara Vale", "The network is public again. Welcome home. There is always another street that needs you.")])]


static func with_call(step: Dictionary, speaker: String, line: String) -> Dictionary:
	step.call = call_line(speaker, line)
	return step
