class_name HealthRecovery
extends RefCounted
## Health coming back between fights: slowly, and only out of combat.
##
## A hero is in combat while a standing thug is within THREAT_RANGE (close
## enough to come after them) or while hit, and for DELAY seconds after the
## last of either. Then health climbs at RATE per second up to the maximum,
## never past it. Knocked out (or frozen) counts as in combat: nothing comes
## back while down, and the wait starts over on getting up (KnockedOutMode
## gets the hero up at KO_HEALTH, so going down is never a faster heal than
## walking away). Plain state run by the game that owns the hero; co-op
## copies only show `recovering`, which PlayerSync sends.

## Seconds out of combat before health starts coming back.
const DELAY := 6.0
## Health per second while recovering (from empty to full in 25 s).
const RATE := 4.0
## A standing thug this close (m) keeps the hero in combat: thugs notice
## heroes within Thug.NOTICE_RANGE and come after them.
const THREAT_RANGE := Thug.NOTICE_RANGE
## Health a knocked-out hero gets up with (of Hero.MAX_HEALTH).
const KO_HEALTH := 40.0

## Seconds left before recovery can start.
var wait := 0.0
## Health is coming back right now.
var recovering := false
## Fighting (or down) as of the last tick: the wait can't run down.
var in_combat := false


## Hit, or still fighting: recovery stops and the wait starts over.
func interrupt() -> void:
	wait = DELAY
	recovering = false


## One tick: returns the hero's health after `delta` seconds. `fighting`:
## a thug is near, or the hero can't recover (knocked out).
func step(delta: float, health: float, max_health: float, fighting: bool) -> float:
	in_combat = fighting
	if fighting:
		interrupt()
		return health
	wait = maxf(wait - delta, 0.0)
	recovering = wait <= 0.0 and health < max_health
	if recovering:
		health = minf(health + RATE * delta, max_health)
	return health


## Whether a standing thug is near enough to `hero_position` (scene space)
## to fight. Copies of other players' thugs count too: they hit just as hard.
static func threatened(hero_position: Vector3) -> bool:
	for thug: Thug in Combat.thugs:
		if not thug.is_down() and thug.global_position.distance_to(hero_position) < THREAT_RANGE:
			return true
	return false
