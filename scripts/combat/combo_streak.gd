class_name ComboStreak
extends RefCounted
## Personal feedback for confirmed damaging hits; never changes attack damage.
## The window uses game time so a pause cannot silently spend the streak.

const WINDOW := 4.0
const NOTICE_TIME := 2.0
var count := 0
var best := 0
var remaining := 0.0
var notice := ""
var notice_left := 0.0
var pulse := 0.0


func confirm(hits: int = 1) -> void:
	if hits <= 0:
		return
	count += hits
	best = maxi(best, count)
	remaining = WINDOW
	notice = ""
	notice_left = 0.0
	pulse = 1.0


func advance(delta: float) -> void:
	pulse = maxf(0.0, pulse - delta * 3.0)
	notice_left = maxf(0.0, notice_left - delta)
	if count == 0:
		return
	remaining = maxf(0.0, remaining - delta)
	if remaining == 0.0:
		reset("TIME UP")


func reset(reason: String) -> void:
	if count > 0:
		notice = "%d HIT STREAK · %s" % [count, reason]
		notice_left = NOTICE_TIME
	count = 0
	remaining = 0.0
	pulse = 0.0


func tier() -> String:
	if count >= 10:
		return "UNSTOPPABLE"
	if count >= 5:
		return "ON FIRE"
	if count >= 3:
		return "NICE COMBO"
	return "KEEP IT GOING"
