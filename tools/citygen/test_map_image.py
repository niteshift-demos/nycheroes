"""Synthetic atlas geometry tests; no network, city cache, or tile rebuild."""
import struct
import unittest

import numpy as np
from PIL import Image, ImageDraw

import map_image as atlas


def fixture(kind=1, material=2.75, normal=1.0):
    positions = np.array([[0, 2, 0], [100, 2, 0], [0, 2, 100]], dtype='<f4')
    normals = np.tile([0, normal, 0], (3, 1)).astype('<f4')
    uv = np.zeros((3, 2), dtype='<f4')
    uv2 = np.tile([material, 0], (3, 1)).astype('<f4')
    indices = np.array([0, 1, 2], dtype='<u4')
    return struct.pack('<4sIIIII', b'NYCT', 7, 1, kind, 3, 3) + b''.join(
        a.tobytes() for a in (positions, normals, uv, uv2, indices))


class MapImageTest(unittest.TestCase):
    def test_projection(self):
        self.assertEqual(atlas.world_pixel(0, 0), (4096, 3072))
        self.assertEqual(atlas.world_pixel(*atlas.ORIGIN), (0, 0))
        self.assertEqual(atlas.world_pixel(24576, 30720), (8192, 8192))
        self.assertEqual(atlas.world_pixel(0, -600)[1], 2972)

    def test_material_and_tile_origin(self):
        image = Image.new('RGB', (100, 100), atlas.WATER)
        atlas.render(ImageDraw.Draw(image), atlas.decode(fixture()), atlas.ORIGIN,
                     pixels=atlas.EXTENT)
        self.assertEqual(image.getpixel((20, 20)), (66, 107, 88))
        self.assertEqual(image.getpixel((90, 90)), (24, 53, 68))

    def test_water_and_decks(self):
        image = Image.new('RGB', (100, 100), atlas.LAND)
        draw = ImageDraw.Draw(image)
        atlas.render(draw, atlas.decode(fixture(kind=4)), atlas.ORIGIN, pixels=atlas.EXTENT)
        self.assertEqual(image.getpixel((20, 20)), (24, 53, 68))
        atlas.render(draw, atlas.decode(fixture(kind=3, material=1)), atlas.ORIGIN,
                     pixels=atlas.EXTENT, structures=True)
        self.assertEqual(image.getpixel((20, 20)), (232, 186, 121))

    def test_walls_and_cables_are_not_roads(self):
        image = Image.new('RGB', (100, 100), atlas.WATER)
        draw = ImageDraw.Draw(image)
        for material, normal in [(1, -1), (7, 1), (6, 1)]:
            atlas.render(draw, atlas.decode(fixture(3, material, normal)), atlas.ORIGIN,
                         pixels=atlas.EXTENT, structures=True)
        self.assertEqual(image.getpixel((20, 20)), (24, 53, 68))

    def test_invalid_or_truncated_tiles_fail(self):
        raw = fixture()
        for broken in [raw[:8], raw[:-1], b'FAIL' + raw[4:], raw[:4] + struct.pack('<I', 8) + raw[8:],
                       raw[:-4] + struct.pack('<I', 99), raw + b'extra']:
            with self.assertRaises(ValueError):
                atlas.decode(broken)

    def test_unknown_surfaces_skip(self):
        self.assertEqual(atlas.decode(fixture(kind=13)), [])


if __name__ == '__main__':
    unittest.main()
