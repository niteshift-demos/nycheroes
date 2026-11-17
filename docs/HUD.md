# Gameplay presentation

The HUD uses Godot's built-in font, white text with a dark shadow, charcoal
panels, warm gold objectives, green health/cash and red danger. No new font,
image asset or shader is needed. Existing radar and touch-control placement
is preserved; health sits immediately below the desktop radar and above the
touch radar, clear of the movement stick.
There is no finite energy mechanic, so no decorative energy gauge is shown.

Wanted stars and cash share a top-right anchor, clear of the touch toolbar.
An active mission gets a small title and subtitle objective at bottom-centre,
including its countdown when relevant. Idle mission cards, always-visible job
buttons, distant contract labels and the defeated-thug counter are removed. Nearby
givers label only within 150 m and on-screen; they never clamp to screen
edges. Labels avoid each other, radar/health, wanted/cash and the driving hint.
Mission targets, navigation pins and nearby combat markers remain useful.
Short notifications stack at top-left, with at most three visible at once.
The driving mode owns its contextual car hint independently.

Mission completion, failure, knockouts and arrests share a centre-screen
banner with a neutral dim overlay and a short procedurally generated stinger
through the Master audio bus. The overlay softens the city's colour cheaply;
it is not a true saturation post-process. Arrest presentation wins over a
simultaneous mission failure. No gameplay rules or multiplayer state change.

## Pause and controls

Esc or P, gamepad Start, the desktop Pause button, or the touch gear opens
pause. Resume restores controls. Single-player simulation pauses; online
co-op keeps running and disables only local controls. The menu releases the
mouse and uses focusable buttons, 46-pixel touch targets and scrolling content.
Arrow keys / D-pad navigate, Enter / A selects, Esc / B returns or resumes.
Browser Esc may first release pointer lock; P is always available.

- Map opens the existing world map (comma remains its direct shortcut).
- Missions lists all catalog contracts, reward and Available / Active / Passed
  status. Set waypoint pins the giver, or the active objective. Side jobs,
  abandon and retry live here. Walk into a giver to start its contract.
- Stats shows current cash, successful missions, distinct cars taken during a
  session, highest wanted level, kilometres flown/driven, and the owned tier of
  each of the six shop upgrades through Stats → Upgrades. This list is read-only.
- Hero / Options and Co-op open the existing menus. O and M remain direct
  shortcuts, respectively. T changes time; N toggles sound.
- Skip tutorial permanently marks the contextual lessons as seen.

`Game/Stats` (`PlayerStats`) saves through Settings, including its synchronous
web localStorage mirror. Completion, theft and highest wanted level save on
change; distances save every ten seconds, on pause and on focus loss. Movement
uses absolute world coordinates, excludes frozen loading and large travel
jumps, and survives floating-origin shifts. Re-entering the same car does not
count it twice. Totals and per-contract completion counts survive reload.

## First visit

A new player sees NYC HEROES, a tagline and Press any key / Tap to play once
the city is ready, then the existing name prompt if needed. Input is withheld
until the card is dismissed. Returning players skip the card. Lightweight
top-left lessons teach movement, charged jump, flight/descend, webs, combat
(when enemies are near), taking a car, map and missions. Each lesson is saved
as it is shown, with twelve seconds between lessons; menus and loading defer
lessons. Touch copy names the visible buttons. Skip tutorial is in pause.

`?tutorial=reset` clears only the title/lesson progress at launch. It preserves
cash, options and lifetime stats. Automated headless runs, demos and free
camera/screenshot launches skip onboarding.

## Checks

`godot --headless --path . res://tests/hud_test.tscn` checks isolated stats and
tutorial persistence, reset/skip, contract navigation, keyboard conflicts,
menu focus and solo/co-op pause ownership. Existing options, missions, wanted,
driving, radar, movement, customization and startup tests cover integration.
Verify the exported web build at desktop and `844×390` with `?touch=1`, including
first visit, pause navigation, mission/wanted driving and result banners.

`tests/hud_web_check.tscn` is a browser presentation fixture excluded from
normal exports. After the normal web build, run
`python tools/web/build_hud_check.py` with other exporters idle, then open
`/hud-check.html?car=1&quality=low&solo=1&name=Agent`. Select the initial case with `?hud_case=foot|car|passed|busted|knocked`. It instantiates the real
world, drives the actual car/mission/arrest APIs and freezes transient result
banners for capture. It does not replace the interactive pause/navigation check.

In that fixture, F5 resumes play, F6 enters the starter car on a wanted
mission, F7 completes the real contract, F8 triggers an arrest through lethal
damage while wanted, and F9 triggers a knockout without police heat. F10
opens the real Hero Supply panel; its normal buttons buy upgrades.

The fixture suppresses rendering only while the city assembles, then restores
normal rendering before the title or any interaction. This speeds software
rendering checks; it does not measure normal startup time.

Service panels share HudStyle typography, gold headings, green cash and
charcoal panels. Shop, garage and safehouse labels use the same 150 m limit,
on-screen-only projection and overlap avoidance as mission givers. Their
radar blips remain available for navigation beyond that distance. The health
strip uses upgraded maximum health when computing its percentage.
