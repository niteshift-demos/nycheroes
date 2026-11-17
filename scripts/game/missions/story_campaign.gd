class_name StoryCampaign
extends RefCounted
## Per-device, per-player completed chapters. Only completion is saved: a
## disconnected or abandoned job restarts without duplicating its reward.

const KEY := "story_completed_v1"
var completed := 0


func _init() -> void:
	completed = clampi(int(Settings.get_value(KEY, 0)), 0, 12)


func available(mission: Mission) -> bool:
	return mission.chapter == 0 or mission.chapter == completed + 1


func complete(mission: Mission) -> void:
	if mission.chapter != completed + 1:
		return
	completed = mission.chapter
	Settings.set_value(KEY, completed)


func reset() -> void:
	completed = 0
	Settings.set_value(KEY, 0)
