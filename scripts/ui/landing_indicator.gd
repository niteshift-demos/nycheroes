class_name LandingIndicator
extends Control
## Reads out hard landings, part of the HUD (GameHud adds it). Two pieces,
## low in the middle of the screen:
##   - While our hero falls fast (FALL_SHOW and up, not web-swinging), a
##     fall-speed gauge: a bar from 0 to Hero.MAX_FALL_SPEED with a tick at
##     Hero.SLAM_SPEED, so the player can see whether the landing will slam.
##     A dive attack always slams; the gauge says so ("DIVE SLAM").
##   - On touching down at Hero.HARD_LANDING_SPEED or more, a short readout of
##     what happened: "HARD LANDING 27 m/s", or "SLAM 68 m/s" with the blast's
##     reach and how many thugs it hurled (Hero.slammed). The gauge stays,
##     frozen at the impact speed, under it.
## Gentler landings show nothing. The readout pops in slightly bigger and
## settles, unless Settings.reduce_motion() is on (then it just appears).
## Only our own hero's landings: other players' are theirs to read.

## Falling at least this fast (m/s) shows the gauge; it hides again below
## FALL_HIDE (a gap, so it doesn't flicker at the edge).
const FALL_SHOW := 16.0
const FALL_HIDE := 10.0
## How long the readout stays (s), and how long it then takes to fade.
const READOUT_TIME := 1.8
const FADE_TIME := 0.4
## The gauge fades in and out this fast (alpha per second).
const GAUGE_FADE_RATE := 6.0
## The readout's pop: it starts this much bigger and settles in POP_TIME (s).
const POP_SCALE := 0.25
const POP_TIME := 0.18
const BAR_WIDTH := 260.0
const BAR_HEIGHT := 10.0
const CALM_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const HARD_COLOR := Color(1.0, 0.8, 0.35)
const SLAM_COLOR := Color(1.0, 0.42, 0.22)

enum Tier { NONE, HARD, SLAM }

var hero: Hero:
	set(value):
		if hero == value:
			return
		if hero:
			hero.landed.disconnect(_on_landed)
			hero.slammed.disconnect(_on_slammed)
		hero = value
		if hero:
			hero.landed.connect(_on_landed)
			hero.slammed.connect(_on_slammed)

## The last hard landing's tier and speed (m/s); for the slam, the blast's
## reach (m) and the thugs it hurled.
var last_tier := Tier.NONE
var last_impact_speed := 0.0
var last_dive := false
var last_radius := 0.0
var last_hits := 0

var _font: Font
var _gauge_alpha := 0.0
var _gauge_shown := false
var _readout_age := INF  # seconds since the last readout began
var _calm := false  # Settings.reduce_motion() when the readout began


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


## Whether the fall-speed gauge is showing (or fading in or out).
func gauge_visible() -> bool:
	return _gauge_alpha > 0.0


## Whether a landing's readout is showing now.
func readout_visible() -> bool:
	return last_tier != Tier.NONE and _readout_age < READOUT_TIME + FADE_TIME


## The readout's text, e.g. "SLAM  68 m/s  ·  blast 9 m  ·  2 thugs hurled".
func readout_text() -> String:
	match last_tier:
		Tier.HARD:
			return "HARD LANDING  %d m/s" % roundi(last_impact_speed)
		Tier.SLAM:
			var text := "%s  %d m/s  ·  blast %d m" % ["DIVE SLAM" if last_dive else "SLAM",
				roundi(last_impact_speed), roundi(last_radius)]
			if last_hits > 0:
				text += "  ·  %d thug%s hurled" % [last_hits, "" if last_hits == 1 else "s"]
			return text
	return ""


## The current fall speed (m/s, 0 when rising or on the ground).
func fall_speed() -> float:
	return maxf(-hero.velocity.y, 0.0) if hero else 0.0


func _process(delta: float) -> void:
	if hero == null:
		return
	_readout_age += delta
	var airborne := not hero.grounded() and not hero.frozen
	var watching := airborne and hero.mode.name != &"Swing" and hero.mode.name != &"KnockedOut"
	var speed := fall_speed()
	if not watching or (speed < FALL_HIDE and not hero.slam_pending):
		_gauge_shown = false
	elif speed >= FALL_SHOW or hero.slam_pending:
		_gauge_shown = true
	var target := 1.0 if _gauge_shown or readout_visible() else 0.0
	_gauge_alpha = move_toward(_gauge_alpha, target, GAUGE_FADE_RATE * delta)
	queue_redraw()


func _draw() -> void:
	if hero == null or (_gauge_alpha <= 0.0 and not readout_visible()):
		return
	var center := Vector2(size.x * 0.5, size.y * 0.74)
	var readout := readout_visible()
	var speed := last_impact_speed if readout and not _gauge_shown else fall_speed()
	var slam := hero.slam_pending or speed >= Hero.SLAM_SPEED
	if readout and not _gauge_shown:
		slam = last_tier == Tier.SLAM
	var color := _tier_color(speed, slam)

	# The gauge: a dark bar, filled to the speed, with a tick at slam speed.
	var bar := Rect2(center.x - BAR_WIDTH * 0.5, center.y, BAR_WIDTH, BAR_HEIGHT)
	var alpha := _gauge_alpha
	draw_rect(bar.grow(2.0), Color(0.0, 0.0, 0.0, 0.55 * alpha))
	var share := clampf(speed / Hero.MAX_FALL_SPEED, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(color, color.a * alpha))
	var tick_x := bar.position.x + bar.size.x * Hero.SLAM_SPEED / Hero.MAX_FALL_SPEED
	var tick_color := Color(SLAM_COLOR if slam else CALM_COLOR, alpha)
	draw_line(Vector2(tick_x, bar.position.y - 5.0), Vector2(tick_x, bar.end.y + 5.0), tick_color, 2.0)
	_text(Vector2(tick_x - 14.0, bar.end.y + 19.0), "SLAM", 12, tick_color)
	var label := "DIVE SLAM" if hero.slam_pending and _gauge_shown else "FALL"
	_text(Vector2(bar.position.x, bar.position.y - 7.0), label, 13, Color(CALM_COLOR, alpha))
	var value := "%d m/s" % roundi(speed)
	var value_width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13).x
	_text(Vector2(bar.end.x - value_width, bar.position.y - 7.0), value, 13, Color(CALM_COLOR, alpha))

	if not readout:
		return
	var fade := clampf(1.0 - (_readout_age - READOUT_TIME) / FADE_TIME, 0.0, 1.0)
	var font_size := 24
	if not _calm and _readout_age < POP_TIME:
		font_size = roundi(24.0 * (1.0 + POP_SCALE * (1.0 - _readout_age / POP_TIME)))
	var text := readout_text()
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var readout_color := SLAM_COLOR if last_tier == Tier.SLAM else HARD_COLOR
	_text(Vector2(center.x - width * 0.5, center.y - 30.0), text, font_size, Color(readout_color, fade))


func _tier_color(speed: float, slam: bool) -> Color:
	if slam:
		return SLAM_COLOR
	if speed >= Hero.HARD_LANDING_SPEED:
		return HARD_COLOR
	return CALM_COLOR


func _on_landed(impact_speed: float) -> void:
	if hero.frozen:
		return
	var dive := hero.slam_pending
	var tier := Tier.NONE
	if impact_speed >= Hero.SLAM_SPEED or dive:
		tier = Tier.SLAM
	elif impact_speed >= Hero.HARD_LANDING_SPEED:
		tier = Tier.HARD
	_gauge_shown = false
	if tier == Tier.NONE:
		return
	last_tier = tier
	last_impact_speed = impact_speed
	last_dive = dive
	last_radius = 0.0
	last_hits = 0
	_readout_age = 0.0
	_calm = Settings.reduce_motion()


## (Its impact speed is a dive's made-up 60 m/s at least: the readout keeps
## the real one from `landed`.)
func _on_slammed(_impact_speed: float, radius: float, hits: int) -> void:
	last_tier = Tier.SLAM
	last_radius = radius
	last_hits = hits


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color(0.0, 0.0, 0.0, color.a))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
