class_name ComboChain
extends RefCounted
## The hero's chain of landed hits, for the HUD's combo counter. Only hits that
## land on a thug count (a punch that whiffs, or a ram or slam that catches
## nobody, adds nothing); each thug caught counts once. The chain stays alive
## for WINDOW seconds after the last hit, so a player who keeps landing punches
## (one string of jab, cross and finisher after another) keeps it going; it
## drops when that time runs out, and breaks at once when a thug's punch lands
## on the hero or the hero is knocked out. Pedestrians are never hit (Combat
## only strikes thugs), so they never count.
##
## It also remembers how the current punch string (MeleeMode.COMBO) went: for
## each punch, whether it landed or whiffed, so the HUD can show which of jab,
## cross and finisher connected.
##
## Our hero's chain runs here; for a copy of another player's hero, PlayerSync
## sets `count` from the network (see PlayerSync.COMBO_SHIFT).

enum End { NONE, DROPPED, BROKEN }
enum Punch { PENDING, LANDED, MISSED }

## Seconds after the last landed hit before the chain drops. Longer than the
## gap between two punch strings (the last punch's recovery plus a jab's
## wind-up), shorter than walking up to the next group of thugs.
const WINDOW := 2.5
## A chain shorter than this isn't worth a word when it ends.
const MIN_REPORTED := 2

## Hits landed in the chain going now (0: no chain).
var count := 0
## The longest chain this session.
var best := 0
## Seconds left before the chain drops.
var time_left := 0.0
## How the last chain ended, how long it was, and how long ago (seconds), for
## the HUD's "5-hit chain dropped" line.
var last_end := End.NONE
var last_count := 0
var since_end := INF
## Seconds since the last landed hit, for the HUD's pop.
var since_hit := INF
## How the last landed hit went: a launching blow (finisher, ram, slam) or not.
var last_heavy := false
## The current punch string: one Punch per MeleeMode.COMBO step.
var punches: Array[int] = []


func _init() -> void:
	_reset_punches()


## `hits` thugs were just hit by our hero; `heavy` for a launching blow.
func land(hits: int, heavy: bool) -> void:
	if hits <= 0:
		return
	count += hits
	best = maxi(best, count)
	time_left = WINDOW
	since_hit = 0.0
	last_heavy = heavy


## A punch of the current string went out: `step` of MeleeMode.COMBO, landing
## on `hits` thugs. The first punch of a string starts the record afresh.
func punch(step: int, hits: int) -> void:
	if step == 0:
		_reset_punches()
	if step >= 0 and step < punches.size():
		punches[step] = Punch.LANDED if hits > 0 else Punch.MISSED


## A thug's hit landed on the hero: the chain is lost.
func break_chain() -> void:
	_end(End.BROKEN)


## Counts down; call once per physics tick for our own hero.
func update(delta: float) -> void:
	since_end += delta
	since_hit += delta
	if count == 0:
		return
	time_left -= delta
	if time_left <= 0.0:
		_end(End.DROPPED)


## A copy's count, as sent by its player's game.
func set_remote_count(value: int) -> void:
	if value > count:
		since_hit = 0.0
	count = value
	best = maxi(best, count)


## Fraction of the window left (1 just after a hit, 0 as it drops).
func remaining() -> float:
	return clampf(time_left / WINDOW, 0.0, 1.0) if count > 0 else 0.0


func _end(how: End) -> void:
	if count == 0:
		return
	if count >= MIN_REPORTED:
		last_end = how
		last_count = count
		since_end = 0.0
	count = 0
	time_left = 0.0
	_reset_punches()


func _reset_punches() -> void:
	punches.clear()
	punches.resize(MeleeMode.COMBO.size())
	punches.fill(Punch.PENDING)
