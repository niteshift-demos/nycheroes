# Hero Supply, garages and safehouses

Cash buys permanent local upgrades at three **Hero Supply** markers: Union
Square in Manhattan, Downtown Brooklyn near Borough Hall, and the Yankee
Stadium area in the Bronx. Walk into a mint square marker to open the shop.
Each power has three tiers costing **$2,000, $8,000 and $25,000**. Each tier
adds 25% of the original value (maximum 175%, never compounded).

| Upgrade | Effect at tier 3 |
| --- | --- |
| Max health | 175 health; regeneration and recovery use the upgraded cap |
| Punch power | 175% damage for all three combo punches |
| Super speed | 105 m/s top speed on foot |
| Flight speed | 175% cruise and boost speed, including sustained boost |
| Slam radius | 175% radius of damaging landing slams |
| Car armor | Incoming damage to the occupied car's driver divided by 1.75 |

Purchasing health capacity does not instantly heal; normal regeneration,
a safehouse or recovery fills it. Armor is active while driving any car;
it belongs to the hero, not an individual stolen car.

**Precinct Payoff** garages near Union Square and Borough Hall have amber
car-shaped radar icons. Drive into the marker while wanted, break police
line of sight, then choose **Pay & respray**. It costs $500 per current star,
changes the paint index, clears wanted stars and removes the local response.
Payment checks actual police sight again, rather than trusting a stale
SEARCHING indicator. No car, no stars, visible police, or insufficient
funds leaves cash and pursuit unchanged. Fleet vehicles whose shader forces
a livery (taxis and buses) retain that livery despite the changed paint index.

Two apartment doors near Union Square and Borough Hall use blue house
icons. Entering heals and saves the apartment as the recovery point after
both ordinary knockout and BUSTED. **Sleep 8 hours** advances TimeOfDay
and heals again. These are outdoor service doors, not modeled interiors.
Recovery uses Game.travel_to: distant streets stream in before the hero
can move. The saved position is absolute and survives floating-origin shifts.

The dark panel uses the options menu's visual style, focusable buttons,
48-pixel touch targets and a scrolling body. Mouse/tap, Tab/arrows/Enter,
and the gamepad UI directions/confirm work; Escape or Start closes it.
Leave and re-enter a marker to reopen it. Single-player pauses while a
panel is open; co-op keeps running, with local hero controls disabled.
Nearby doors use the same projected 3D markers as the HUD's objectives.
All service icons are registered with Radar and appear on the map.

## Saves, launch options and co-op

Settings persists `upgrade_<health|punch|speed|flight|slam|armor>`,
`safehouse_position` and `safehouse_name`; the wallet persists cash.
The browser uses Settings' immediate localStorage mirror as well as its
normal file. `?upgrades=reset` (desktop `-- --upgrades=reset`) clears all
six upgrade tiers at startup. Remove it before reloading to test persistence.
It does not reset cash or the saved apartment.

`CityShops`, available at `Game.shops`, owns entry, purchase, respray,
safehouse and sleep logic. `HeroUpgrades` validates tier limits and prices.
Other systems can read `Hero.car_armor_multiplier` for vehicle damage.
Hero tunables are local; remote heroes never read local upgrades. Punch
and slam hits are already computed by the attacking player and routed
through Combat to the NPC owner. Existing PlayerSync sends resulting
health, movement, mode and car paint. Purchases and apartment choice do
not require new RPCs. Live multiplayer purchase/respawn is not yet checked.

## Locations

Landmark coordinates were verified on 2026-11-17. These are reference anchors,
not claims that the fictional shops occupy those landmarks. Door offsets
are authored in meters east/up/south; on loading, each marker moves to the
nearest sidewalk segment within 100 m, using the lane's elevation. Only
nearby markers are projected in the HUD; all remain on the map.

| Anchor | Latitude, longitude | Reference |
| --- | --- | --- |
| Union Square | 40.73556, -73.99056 | [Place coordinates](https://en.wikipedia.org/wiki/Union_Square,_Manhattan) |
| Brooklyn Borough Hall | 40.69278, -73.99000 | [Building coordinates](https://en.wikipedia.org/wiki/Brooklyn_Borough_Hall) |
| Yankee Stadium | 40.82917, -73.92639 | [Stadium coordinates](https://en.wikipedia.org/wiki/Yankee_Stadium) |

Offsets in `CityShops.catalog()`: Union supply `(55,0,15)`, garage
`(80,0,100)`, home `(90,0,-110)`; Brooklyn supply `(-45,0,15)`, garage
`(-75,0,130)`, home `(100,0,65)`; Bronx supply `(150,0,150)`.
No downloaded map extracts, artwork, new shaders or tile rebuilds.

## Checks

`godot --headless --path . res://tests/shops_test.tscn` uses synthetic
geometry and an isolated settings file. It covers entry, insufficient
funds, tier pricing/caps, persistence, applied powers and driver armor,
respray sight/funds/car requirements, paint, both recovery paths and origin
shifts. Keep missions_test, wanted_test, drive_test, combat_test,
hero_moves_test, options_test and radar_test passing.

For the web check, export with `.niteshift/files/build-web`, then visit
`?quality=low&name=Agent&solo=1&cash=50000&upgrades=reset&spawn=-372,20,2507,0`.
The Union Square supply marker is nearby. For its garage, use
`?quality=low&name=Agent&solo=1&cash=5000&wanted=3&car=1&spawn=-367,14,2606,0`.
Enter the starter car with G/R3, drive into the amber marker, and pay after
breaking police sight. Remove cash/reset options for save/reload checks.
For a deterministic unseen-payment check in a slow browser, replace
`wanted=3` with `shop_check=garage`: entering a garage in a car seeds three
stars immediately before opening the panel. The normal police sight and
payment checks still apply. This is a QA fixture, not a normal gameplay mode.
