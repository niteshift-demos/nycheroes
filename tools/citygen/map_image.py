"""Bake a north-up atlas from published (or local) 1 km NYCT v7 tiles.

No raw city downloads or tile rebuilds. Only ground, inland water and upward
road decks are rasterized; sea is the empty background. X east / Z south is
identical to Geo.to_world. Cache is outside the repository by default.

python map_image.py --cache /data/city-map --out assets/map
Requires numpy, pillow, pyproj, and zstandard (or Python 3.14 compression.zstd).
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import struct
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import numpy as np
from PIL import Image, ImageDraw
from pyproj import Transformer
try:
    from compression import zstd
    decompress = zstd.decompress
except ImportError:
    import zstandard
    def decompress(data):
        # Decompression contexts are not thread-safe. Each worker owns its call.
        return zstandard.ZstdDecompressor().decompress(data)

# A square, fixed world rect shared by every level. 6 m/texel at highest zoom.
ORIGIN = (-24576, -18432)
EXTENT = 49152
PIXELS = 8192
TILE_PIXELS = 1024
WATER = '#183544'
LAND = '#384650'
ROAD = '#aeb8b9'
PARK = '#426b58'
HIGHWAY = '#e8ba79'
COLORS = {0: LAND, 1: ROAD, 2: PARK, 3: LAND, 4: '#8b8269',
          5: '#3d625b', 9: '#43564e', 20: PARK, 21: '#657276', 22: ROAD}


def world_pixel(x, z, pixels=PIXELS):
    """Pixel edge coordinates, never rounded until rasterization."""
    return ((x - ORIGIN[0]) * pixels / EXTENT,
            (z - ORIGIN[1]) * pixels / EXTENT)


def decode(raw):
    """Validate NYCT framing and return only cartographic mesh surfaces.

    Unknown surfaces are skipped using their declared size, not interpreted as
    triangles (lanes use break indices). Reject partial or mismatched assets.
    """
    if len(raw) < 12:
        raise ValueError('Truncated NYCT header')
    magic, version, count = struct.unpack_from('<4sII', raw)
    if magic != b'NYCT' or version != 7 or 12 + count * 12 > len(raw):
        raise ValueError('Expected NYCT version 7')
    offset = 12 + count * 12
    surfaces = []
    for s in range(count):
        kind, vertices, indices = struct.unpack_from('<III', raw, 12 + s * 12)
        end = offset + vertices * 40 + indices * 4
        if end > len(raw):
            raise ValueError('Truncated NYCT surface')
        if kind in (1, 3, 4):
            positions = np.frombuffer(raw, '<f4', vertices * 3, offset).reshape(-1, 3)
            normals = np.frombuffer(raw, '<f4', vertices * 3, offset + vertices * 12).reshape(-1, 3)
            uv2 = np.frombuffer(raw, '<f4', vertices * 2, offset + vertices * 32).reshape(-1, 2)
            idx = np.frombuffer(raw, '<u4', indices, offset + vertices * 40)
            if indices % 3 or (indices and idx.max() >= vertices):
                raise ValueError('Invalid triangle indices')
            if not np.isfinite(positions).all() or not np.isfinite(uv2).all():
                raise ValueError('Non-finite geometry')
            surfaces.append((kind, positions, normals, uv2, idx.reshape(-1, 3)))
        offset = end
    if offset != len(raw):
        raise ValueError('Unexpected NYCT trailing bytes')
    return surfaces


def render(draw, surfaces, tile_origin, pixels=PIXELS, structures=False):
    """Draw flat cartographic materials, ignoring walls and bridge cables."""
    scale = pixels / EXTENT
    for kind, positions, normals, uv2, triangles in surfaces:
        if (kind == 3) != structures:
            continue
        materials = uv2[triangles[:, 0], 0].astype(int)
        keep = normals[triangles, 1].mean(axis=1) >= 0.3
        if kind == 3:
            keep &= materials == 1
        points = (positions[:, [0, 2]] + np.asarray(tile_origin) - ORIGIN) * scale
        for tri, material in zip(triangles[keep], materials[keep]):
            color = WATER if kind == 4 else HIGHWAY if kind == 3 else COLORS.get(material, LAND)
            draw.polygon([tuple(p) for p in points[tri]], fill=color)



def download(url, path):
    if path.exists():
        return path.read_bytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            with urlopen(Request(url, headers={"User-Agent": "NYCHeroes-Map/1.0"}), timeout=60) as response:
                data = response.read()
            path.write_bytes(data)
            return data
        except Exception:
            if attempt == 3:
                raise
            time.sleep(1 + attempt)


def save_pyramid(image, out):
    """Three levels, independent 1024 px tiles; lossless 32-color WebP images."""
    files = []
    for level, pixels in enumerate((1024, 2048, 8192)):
        scaled = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
        scaled = scaled.quantize(colors=32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        for y in range(pixels // TILE_PIXELS):
            for x in range(pixels // TILE_PIXELS):
                name = f'{level}/{x}_{y}.webp'
                path = out / name
                path.parent.mkdir(parents=True, exist_ok=True)
                scaled.crop((x * 1024, y * 1024, (x + 1) * 1024, (y + 1) * 1024)).save(path, lossless=True, method=6)
                files.append(name)
    return files


def highways(cache, projection):
    """Small CSCL subset; same source as fetch_data.py, no full data download.

    rw_type=2 is a highway: excluding ramps, service roads and pedestrian paths
    avoids giving those the visual weight of an expressway's main carriageway.
    """
    query = urlencode({'$select': 'the_geom,full_street_name', '$limit': 50000,
                       '$where': "rw_type='2'"})
    data = download('https://data.cityofnewyork.us/resource/inkn-q76z.json?' + query, cache / 'highways.json')
    records = json.loads(data)
    transform = Transformer.from_crs('EPSG:4326', projection, always_xy=True)
    paths = []
    for record in records:
        geom = record.get('the_geom', {})
        lines = [geom['coordinates']] if geom.get('type') == 'LineString' else geom.get('coordinates', [])
        for line in lines:
            paths.append([world_pixel(e, -n) for e, n in (transform.transform(*p[:2]) for p in line)])
    return paths, hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='https://nycheroes.party/tiles/nyc', help='URL or local nyc tile directory')
    parser.add_argument('--cache', type=Path, default=Path('/tmp/nycheroes-map'))
    parser.add_argument('--out', type=Path, default=Path('assets/map'))
    args = parser.parse_args()
    remote = args.source.startswith(('http://', 'https://'))
    manifest_bytes = (urlopen(Request(args.source + '/manifest.json', headers={'User-Agent': 'NYCHeroes-Map/1.0'}), timeout=60).read() if remote
                      else (Path(args.source) / 'manifest.json').read_bytes())
    manifest = json.loads(manifest_bytes)
    if manifest['version'] != 7:
        raise ValueError('Map decoder requires tile format 7')
    cache = args.cache / manifest['build']
    level = next(level for level in manifest['levels'] if level['name'] == 'lod1')
    size = level['tile_size']

    def fetch(tile):
        name = f"lod1/{tile['i']}_{tile['j']}.nyct"
        data = (download(args.source + '/' + name, cache / name) if remote
                else (Path(args.source) / name).read_bytes())
        raw = decompress(data)
        if len(raw) != tile['raw_bytes']:
            raise ValueError(f'Wrong uncompressed size: {name}')
        return tile, decode(raw)

    image = Image.new('RGB', (PIXELS, PIXELS), WATER)
    draw = ImageDraw.Draw(image)
    decks = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        # Bound in-flight decompressed geometry while the renderer consumes it.
        for start in range(0, len(level['tiles']), 16):
            for tile, surfaces in pool.map(fetch, level['tiles'][start:start + 16]):
                origin = (tile['i'] * size, tile['j'] * size)
                render(draw, surfaces, origin)
                decks.append((origin, [(s[0], *(a.copy() for a in s[1:])) for s in surfaces if s[0] == 3]))
            print(f"Rendered {min(start + 16, len(level['tiles']))}/{len(level['tiles'])} tiles", flush=True)
    for origin, surfaces in decks:
        render(draw, surfaces, origin, structures=True)
    paths, source_hash = highways(cache, manifest['projection'])
    for path in paths:
        if len(path) > 1:
            draw.line(path, fill=HIGHWAY, width=3, joint='curve')
    args.out.mkdir(parents=True, exist_ok=True)
    files = save_pyramid(image, args.out)
    info = {'version': 1, 'origin': ORIGIN, 'extent': EXTENT, 'levels': [1024, 2048, 8192],
            'tile_pixels': TILE_PIXELS, 'tile_build': manifest['build'],
            'source': args.source, 'projection': manifest['projection'],
            'highways_sha256': source_hash, 'files': files}
    (args.out / 'atlas.json').write_text(json.dumps(info, indent=2) + '\n')
    total = sum((args.out / f).stat().st_size for f in files)
    print(f'{len(files)} map images: {total:,} bytes', flush=True)


if __name__ == '__main__':
    main()
