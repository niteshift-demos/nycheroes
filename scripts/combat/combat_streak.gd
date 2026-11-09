class_name CombatStreak
extends RefCounted
## Our hero's combat streak: how many hits in a row landed on standing thugs
## with no long pause between them and without taking a hit. Combat feeds it
## the hits our hero really lands (Combat.strike and slam shockwaves that do
## damage; a thug already down, a miss, or the harmless push of getting back
## up don't count), and our hero getting hurt breaks it. GameHud shows it.
##
## It only reads fights, so damage balance is unchanged. It is plain local
## state of our own game (other players don't see it); time runs on the game's
## clock (delta), so hit stop and Movie Maker's fixed frame rate time it the
## same as normal play.

## The streak ended: `count` hits, `reason` &"timeout" or &"hurt".
signal ended(count: int, reason: StringName)

## Seconds after the last hit before the streak runs out.
const WINDOW := 3.0
## Streak counts that earn a callout, and the callout (GameHud).
const TIERS := [[5, "NICE"], [10, "GREAT"], [20, "BRUTAL"], [35, "UNSTOPPABLE"], [50, "LEGENDARY"]]

## Hits in the current streak (0: none going).
var count := 0
## The longest streak this session.
var best := 0
## Seconds left before the streak runs out.
var time_left := 0.0
## Game time since the last hit landed (for the counter's pop).
var since_hit := 0.0


## Our hero landed `hits` hits on standing thugs.
func add_hits(hits: int) -> void:
	if hits <= 0:
		return
	count += hits
	best = maxi(best, count)
	time_left = WINDOW
	since_hit = 0.0


## Ends the streak (our hero got hurt, or time ran out).
func break_streak(reason: StringName) -> void:
	if count == 0:
		return
	var was := count
	count = 0
	time_left = 0.0
	ended.emit(was, reason)


func update(delta: float) -> void:
	since_hit += delta
	if count == 0:
		return
	time_left -= delta
	if time_left <= 0.0:
		break_streak(&"timeout")


## The callout for a streak this long ("" below the first tier).
static func tier_name(hits: int) -> String:
	var name := ""
	for tier: Array in TIERS:
		if hits >= int(tier[0]):
			name = tier[1]
	return name
