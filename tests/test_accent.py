#!/usr/bin/env python3
"""Self-check for the accent picker in nowplaying.py, on generated images.

    python -m unittest discover -s tests -v

Needs Pillow and nothing else. Each case is a cover that a picker has
actually got wrong, or a shape that is easy to get wrong: dark art with one
vivid colour, art with no colour at all, and a small accent lost in a field.
The last test runs the whole script against a throwaway local HTTP server to
pin the JSON contract the skin parses (rgb, hex, rgb_rm).
"""

from __future__ import annotations

import colorsys
import functools
import http.server
import json
import os
import random
import subprocess
import sys
import tempfile
import threading
import unittest

from PIL import Image, ImageDraw

SCRIPTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "homeassistant", "scripts")
sys.path.insert(0, SCRIPTS)

import nowplaying  # noqa: E402


def hue_deg(rgb) -> float:
    return colorsys.rgb_to_hsv(*(c / 255 for c in rgb))[0] * 360


def hue_dist(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def hls_hue(hls) -> float:
    return hls[0] * 360


# pick_accents uses numpy when it is installed and plain Python otherwise;
# cases that matter for both run against each explicitly.
PICKERS = [nowplaying.pick_accents, nowplaying._pick_accents_py]


def speckle(img, colours, count, seed=1):
    """Scatter single pixels of the given colours, the way JPEG noise and
    film grain put stray near-black chroma into an otherwise clean cover."""
    rnd = random.Random(seed)
    px = img.load()
    w, h = img.size
    for _ in range(count):
        px[rnd.randrange(w), rnd.randrange(h)] = rnd.choice(colours)
    return img


class AccentTests(unittest.TestCase):
    def test_black_and_red_is_red_not_pink(self):
        # The Witcher 3 case: a mostly black cover with a red emblem. Near-black
        # specks such as #020001 have HLS saturation 1.0 and a magenta hue, and
        # the old palette picker let them win and lifted them into hot pink.
        # This exact image came out (255, 41, 201) under the old picker.
        img = Image.new("RGB", (400, 400), (3, 0, 2))
        speckle(img, [(2, 0, 1), (8, 0, 6), (12, 2, 9), (20, 4, 14)], 30000)
        ImageDraw.Draw(img).ellipse((140, 140, 260, 260), fill=(120, 12, 16))
        rgb = nowplaying.pick_accent(img)
        self.assertLess(hue_dist(hue_deg(rgb), 0), 12, "accent %r is not red" % (rgb,))
        r, g, b = rgb
        self.assertGreater(r, 200)
        # Pink is red with blue lifted toward it; red keeps blue near green.
        self.assertLess(b - g, 20, "accent %r leans pink" % (rgb,))

    def test_near_white_is_neutral(self):
        # [246,244,240] is white to any eye but reports HLS saturation 0.25,
        # which is enough to fool a picker that trusts HLS into a tint.
        img = Image.new("RGB", (300, 300), (246, 244, 240))
        speckle(img, [(240, 238, 232), (250, 249, 247), (236, 233, 228)], 20000)
        self.assertEqual(nowplaying.pick_accent(img), nowplaying.FALLBACK_RGB)

    def test_greyscale_is_neutral(self):
        img = Image.new("RGB", (256, 256))
        draw = ImageDraw.Draw(img)
        for x in range(256):
            draw.line((x, 0, x, 255), fill=(x, x, x))
        self.assertEqual(nowplaying.pick_accent(img), nowplaying.FALLBACK_RGB)

    def test_small_vivid_accent_on_dark_field(self):
        # About 2% of the cover. Quantising to a small palette averaged spots
        # like this into the surrounding mass; per-pixel weighting keeps them.
        img = Image.new("RGB", (480, 480), (24, 22, 30))
        speckle(img, [(34, 30, 44), (18, 16, 22), (40, 34, 30)], 40000)
        ImageDraw.Draw(img).rectangle((300, 60, 368, 128), fill=(30, 215, 70))
        rgb = nowplaying.pick_accent(img)
        self.assertNotEqual(rgb, nowplaying.FALLBACK_RGB)
        self.assertLess(hue_dist(hue_deg(rgb), hue_deg((30, 215, 70))), 12, "accent %r is not green" % (rgb,))

    def test_scattered_specks_are_not_a_colour(self):
        # 4% of the cover in single red pixels, on grey: grain, not a colour.
        # A thumbnail blurs specks like these away; the numpy path works on the
        # full cover, where they stay sharp, so only the blob test stops them.
        img = speckle(Image.new("RGB", (400, 400), (128, 128, 128)), [(220, 30, 30)], 6400)
        for pick in PICKERS:
            with self.subTest(pick=pick.__name__):
                self.assertEqual(pick(img), (None, None, None))
        self.assertEqual(nowplaying.pick_accent(img), nowplaying.FALLBACK_RGB)

    def test_close_hues_merge_and_a_small_region_still_counts(self):
        # Red and orange-red halves are one colour, not two; the green dot,
        # about 1.8% of the cover, is the second colour and nothing is third.
        img = Image.new("RGB", (400, 400), (220, 40, 40))
        draw = ImageDraw.Draw(img)
        draw.rectangle((200, 0, 400, 400), fill=(235, 90, 40))
        draw.ellipse((170, 170, 230, 230), fill=(40, 190, 60))
        for pick in PICKERS:
            with self.subTest(pick=pick.__name__):
                first, second, third = pick(img)
                self.assertLess(hue_dist(hls_hue(first), hue_deg((225, 60, 40))), 20)
                self.assertIsNotNone(second, "the green dot was lost")
                self.assertLess(hue_dist(hls_hue(second), hue_deg((40, 190, 60))), 15)
                self.assertIsNone(third)

    def test_dark_vivid_colour_is_still_named(self):
        # A deep purple is dark (Oklab L ~0.3) but plainly a colour; a
        # lightness cut set too high called covers like this neutral.
        img = Image.new("RGB", (200, 200), (60, 20, 90))
        rgb = nowplaying.pick_accent(img)
        self.assertNotEqual(rgb, nowplaying.FALLBACK_RGB)
        self.assertLess(hue_dist(hue_deg(rgb), hue_deg((60, 20, 90))), 15)

    def test_accent_respects_the_readability_floors(self):
        # A dark, dull blue still has to read against a dark panel.
        img = Image.new("RGB", (200, 200), (20, 30, 70))
        h, l, s = colorsys.rgb_to_hls(*(c / 255 for c in nowplaying.pick_accent(img)))
        self.assertGreaterEqual(l, nowplaying.ACCENT_LIGHT_MIN - 0.01)
        self.assertLessEqual(l, nowplaying.ACCENT_LIGHT_MAX + 0.01)
        self.assertGreaterEqual(s, nowplaying.ACCENT_SAT_MIN - 0.01)


class _Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


class ContractTests(unittest.TestCase):
    """The skin parses rgb_rm, and HA sensors read rgb/hex. Keep them stable."""

    def run_script(self, picture: str, base: str, www: str) -> dict:
        out = subprocess.run(
            [sys.executable, os.path.join(SCRIPTS, "nowplaying.py"), "--www", www,
             "--ha-base", base, "--picture", picture, "--state", "playing"],
            capture_output=True, text=True, timeout=60, check=True,
        )
        printed = json.loads(out.stdout)
        with open(os.path.join(www, "nowplaying.json"), encoding="utf-8") as fh:
            self.assertEqual(printed, json.load(fh))
        return printed

    def test_json_contract(self):
        with tempfile.TemporaryDirectory() as srv, tempfile.TemporaryDirectory() as www:
            Image.new("RGB", (64, 64), (170, 18, 22)).save(os.path.join(srv, "cover.png"))
            httpd = http.server.ThreadingHTTPServer(
                ("127.0.0.1", 0), functools.partial(_Quiet, directory=srv))
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            base = "http://127.0.0.1:%d" % httpd.server_address[1]
            try:
                got = self.run_script("/cover.png", base, www)
                none = self.run_script("", base, www)
            finally:
                httpd.shutdown()
                httpd.server_close()

        self.assertEqual(got["art"], "ok")
        rgb = tuple(got["rgb"])
        self.assertEqual(len(rgb), 3)
        self.assertTrue(all(isinstance(c, int) and 0 <= c <= 255 for c in rgb))
        self.assertEqual(got["hex"], "#%02x%02x%02x" % rgb)
        self.assertEqual(got["rgb_rm"], "%d,%d,%d" % rgb)
        self.assertLess(hue_dist(hue_deg(rgb), 0), 12)

        self.assertEqual(none["art"], "no-art")
        self.assertEqual(tuple(none["rgb"]), nowplaying.FALLBACK_RGB)
        self.assertEqual(none["rgb_rm"], "%d,%d,%d" % nowplaying.FALLBACK_RGB)


if __name__ == "__main__":
    unittest.main()
