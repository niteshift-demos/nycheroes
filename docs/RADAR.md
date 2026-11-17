# Radar and waypoint map

The radar shows the real streets around the hero, rotating with the active
camera. Its white arrow follows the hero's facing; N shows north. Its range
smoothly grows from 180 m on foot to 850 m at speed. Driving uses five
seconds of look-ahead (330 m at the car's 30 m/s top speed); other powers
use three seconds. Position-derived speed also covers a carried hero. It sits above health at
bottom-left on computers and below health at top-left on touch screens,
clear of the movement stick. Enemy triangles match the HUD's nearest thug;
colored dots track other co-op players. While the local hero is wanted,
standing PoliceOfficers in `Combat.thugs` appear as shields flashing blue
and red every 400 ms. Downed officers and cleared wanted stars remove those
blips. Off-radar icons stop at the edge.

Press comma (`,`) or tap/click the radar to open the north-up map. Drag to
pan, use the wheel or +/− buttons/keys to zoom, and click/tap to set a purple
waypoint. Center returns to the hero, Clear pin removes it, and comma,
Escape or Close returns to play. The pin appears on the radar and as a
projected distance marker in the game. Hero input is disabled while the map
is open; the world continues running, including co-op. Closing by keyboard
on web leaves the pointer free until the next click, as browsers require.

Options → Game → Show radar saves visibility between visits. `?radar=0`
(or desktop `-- --radar=0`) overrides it for that session until changed in
the menu. Comma still opens the map with a hidden radar.

## Integration API

`class_name Radar`, in `scripts/ui/radar.gd`. Get the live instance from
`Game.radar`, `HUD/Radar`, or `get_tree().get_first_node_in_group("radar")`.
The API is local UI state and does not send network messages:

```gdscript
func add_blip(id: StringName, world_position: Vector3, kind: StringName, color: Color) -> void
func update_blip(id: StringName, world_position: Vector3) -> void
func remove_blip(id: StringName) -> void
func add_node_blip(id: StringName, node: Node3D, kind: StringName, color: Color) -> void
func set_waypoint(world_position: Vector3) -> void
func clear_waypoint() -> void
```

Kinds are `player` (dot), `mission` and `waypoint` (diamond), `enemy`
(triangle), `police` (shield), and `shop` (square). Unknown kinds use a dot.
IDs are caller-owned: use a prefix such as `missions/delivery`. The `radar/`
prefix is reserved for co-op players, police, the nearest thug, and the waypoint.
Adding an existing ID replaces it; updating a missing ID does nothing;
removing is safe to repeat. Updating a node blip makes it a fixed blip.
Tracked nodes use weak references, so freeing one removes its blip.

All fixed positions are **world** coordinates (scene position plus
`WorldOrigin.offset`). Do not adjust them after an origin shift. Node blips
convert `global_position` through `WorldOrigin.to_world()` on refresh.
`waypoint_changed(world_position: Vector3, active: bool)` announces pin
changes; `waypoint_position` and `waypoint_active` expose the current pin.
The HUD converts the waypoint back to scene coordinates for projection.

`world_to_radar(world_position, clamp_edge := true)` returns a pixel offset
from the radar center. `radar_to_world(offset, altitude := 0.0)` is the
inverse of the **unclamped** transform. `WorldMap.world_to_map()` and
`map_to_world()` use map-local pixels, with north up. Map-picked waypoints
have world Y = 0; they are navigation pins, not ground raycasts or routes.

## Data and cost

`CityStreamer.traffic_lanes_changed` supplies world-space polylines when a
near tile arrives or leaves. The radar subscribes and also seeds itself
from `traffic_lanes()` if added after streaming starts. `RadarStreets`
retains one canvas multiline command per tile, shared as packed line pairs
with the full map. A tile change only rebuilds that tile; movement, rotation
and zoom update the parent transform. Blips refresh at 20 Hz. No viewport
is rendered to a texture each frame, no tiles are downloaded for the map,
and no new assets, data sources, shaders or tile rebuilds are needed.

`?radar_profile=1` logs mean and maximum radar CPU update time every 300
frames for browser profiling. This excludes GPU rendering and tile-change
geometry preparation; do not interpret it as total GPU frame time.

## Coverage and limits

The map intentionally shows **loaded near-tile streets only**, labeled on
screen. Zooming/panning does not request distant tiles; leaving an area
unloads its streets from both maps. It is not a whole-city atlas. Speed
zoom may therefore expose blank areas at low graphics settings, which
stream a smaller radius. Lane centerlines show real drivable streets,
including bridges, but do not include pedestrian-only paths or street names.
There is no route planning, coastline/borough outline, park or water fill:
those are rendered mesh surfaces, not an inexpensive retained 2D outline
in the current streaming API. Empty space must not be read as water.

Waypoints last for this game session and remain until cleared or replaced;
they do not auto-clear on arrival. Blips use the game's existing co-op
PlayerSync state. Police blips follow `Hero.wanted_stars` and the existing
PoliceOfficer nodes; missions and shops register through the API. No
gameplay or networking is added for them.

## Checks

After `godot --headless --path . --import`:

- `godot --headless --path . res://tests/radar_test.tscn`: synthetic blip
  kinds/lifecycle, tracking/freeing, coordinate round trips, edge clamping,
  actual origin shift, cached streets unloading, map zoom/pan/click,
  visibility settings, standing police appearing only while wanted, driving
  zoom and the separate comma/G input bindings. Needs no city download.
- Keep `options_test`, `streaming_test`, and `hero_moves_test` passing.
- Export with `.niteshift/files/build-web`; in the browser check a street
  radar, camera rotation, a map click and its game marker, pan/zoom/clear,
  hidden radar restored in options, and touch placement away from the stick.
