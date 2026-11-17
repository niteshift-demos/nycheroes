# Radar and waypoint map

The radar shows a baked map of land, blue water, green parks, pale streets
and amber highways/bridges under the live streets, rotating with the active
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
pan, use the wheel or +/− buttons/keys to zoom, pinch with two fingers, and
click/tap to set a purple waypoint. The first opening fits all five boroughs;
City restores that view, You zooms to the hero, Clear pin removes it, and comma,
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
use loaded collision height (including bridges and roofs), converted back to
world Y after an origin shift. Unloaded locations use sea level. The
`place_map_waypoint()` helper does this; `set_waypoint()` preserves the
caller’s explicit altitude.

## Data and cost

`CityStreamer.traffic_lanes_changed` supplies world-space polylines when a
near tile arrives or leaves. The radar subscribes and also seeds itself
from `traffic_lanes()` if added after streaming starts. `RadarStreets`
retains one canvas multiline command per tile, shared as packed line pairs
with the full map. A tile change only rebuilds that tile; movement, rotation
and zoom update the parent transform. Blips refresh at 20 Hz. No viewport
is rendered to a texture each frame. The live lane overlay appears at street
zoom on the map and remains visible on the radar.

`CityMapAtlas` retains sprites beneath the live lines. Its overview is 1024²;
2048² and 8192² levels use 1024² tiles loaded on demand, at most one image per
frame. Both views share a 12-entry texture cache; visible sprites retain their
textures. The 69 images total 2.83 MB; the highest level is 6 m/texel. Texture imports include mipmaps to
keep the camera-relative radar from shimmering. Moving the camera changes
transforms; tile visibility is checked at 10 Hz. Hidden maps stop loading.

`?radar_profile=1` logs mean and maximum radar CPU update time every 300
frames, including atlas placement/culling. This excludes GPU rendering,
texture decoding/upload on tile changes, and live street geometry preparation;
it is not a total GPU frame-time measurement.

### Rebuilding the atlas

`tools/citygen/map_image.py` reads the same NYCT v7 geometry that the game
streams: ground material IDs, upward bridge road decks, and inland water.
Sea is the empty background. It uses all 1,022 published 1 km tiles, without
fetching raw city datasets or rebuilding tiles. A small NYC CSCL query for
highways (`rw_type=2`) distinguishes them from local streets. Source build ID,
projection, highway data SHA-256, and tile filenames are in
`assets/map/atlas.json`. The WebP images are committed; players need no map server.

```sh
# Python 3.14 uses compression.zstd; earlier Python needs zstandard.
python -m pip install numpy pillow pyproj zstandard
python tools/citygen/map_image.py --cache /tmp/nyc-map --out assets/map
# Or use an existing tile build, without downloading NYCT files:
python tools/citygen/map_image.py --source /path/to/tiles/nyc --cache /tmp/nyc-map
python -m unittest discover -s tools/citygen -p 'test_map_image.py'
godot --headless --path . --import
```

The cache keeps downloaded tiles under their build ID. A rebuild with the
same cache uses the same highway snapshot; remove its `highways.json` to
refresh that layer. `map_image.py` fails on missing/corrupt tiles rather than
silently leaving holes. All levels share the world rect (-24576, -18432) to
(24576, 30720), in X/Z meters. Godot's `Geo.to_world()` and the generator's
projection are the same; no Mercator screenshot is stretched into alignment.
No gameplay city tiles need rebuilding.

## Coverage and limits

The baked map covers all five boroughs, Central Park, the rivers, islands,
parks, roads, highway corridors and bridges independently of near-tile loading.
Areas outside NYC data coverage, including New Jersey, are left blue; blue
outside the boroughs is not a survey of surrounding states' coastlines.
Borough, neighborhood, park, water and landmark labels appear at suitable
zooms, with screen-space collision rejection. Street-name labels are a small
editorial Midtown set, not a searchable street directory. Building footprints
and the optional GPS route are not included. Roads come from the simplified
1 km meshes; close zoom still shows the more precise live lane lines.

Waypoints last for this game session and remain until cleared or replaced;
they do not auto-clear on arrival. Blips use the game's existing co-op
PlayerSync state. Police blips follow `Hero.wanted_stars` and the existing
PoliceOfficer nodes; missions and shops register through the API. No
gameplay or networking is added for them.

## Checks

After `godot --headless --path . --import`:

- `godot --headless --path . res://tests/radar_test.tscn`: synthetic blip
  kinds/lifecycle, tracking/freeing, coordinate round trips, edge clamping,
  actual origin shift, cached streets unloading, map zoom/pan/click/pinch,
  Times Square / Brooklyn Bridge / Statue of Liberty atlas pixels and land,
  loaded collision height through a vertical origin shift,
  visibility settings, standing police appearing only while wanted, driving
  zoom and the separate comma/G input bindings. Needs no city download.
- Keep `options_test`, `streaming_test`, and `hero_moves_test` passing.
- Export with `.niteshift/files/build-web`; in the browser check a street
  radar, camera rotation, a map click and its game marker, pan/zoom/clear,
  hidden radar restored in options, and touch placement away from the stick.
