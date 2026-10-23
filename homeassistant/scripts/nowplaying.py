#!/usr/bin/env python3
"""Publish now-playing metadata and album art for the HA Now Playing skin.

Home Assistant already knows what every media player is doing. Rainmeter
cannot ask it directly without an access token living in a plain-text skin
file, so this script runs *inside* HA (as a `command_line` sensor) and drops
two files into `www/`, which HA serves at `/local/` with no authentication:

    <name>.json         title, artist, album, state, source, accent colour
    <name>_cover.png    the artwork, re-encoded, at a stable path

Nothing secret ever leaves HA: `/local/` is unauthenticated by design, and
these two files contain only what is already on screen.

The accent colour is the interesting part. It is the artwork's most dominant
colour region, found by clustering in Oklab and ignoring specks, so the skin
can tint text to match the album without looking washed out. See
pick_accent().

Source-agnostic: it takes whatever entity_picture / title / artist it is
handed, so Music Assistant, Spotify, Sonos, Cast, Plex, Jellyfin, Squeezebox,
a Universal media player, or anything else exposing the standard media_player
attributes all work identically. See docs/sources.md.

Usage (see homeassistant/packages/rainmeter_nowplaying.yaml for the wiring):

    nowplaying.py --www /config/www --name nowplaying \
        --ha-base http://127.0.0.1:8123 \
        --picture "/api/media_player_proxy/media_player.x?token=..." \
        --title-b64 <b64> --artist-b64 <b64> --album-b64 <b64> \
        --source-b64 <b64> --state playing

Text arrives base64-encoded so quotes, backslashes, emoji and CJK survive the
trip through the shell intact. This is not optional - track titles are hostile
input, and a stray apostrophe in a band name will otherwise truncate the
command.

Prints the JSON payload on stdout so the calling command_line sensor can use
it directly via json_attributes.
"""

from __future__ import annotations

import argparse
import base64
import colorsys
import hashlib
import io
import json
import math
import os
import sys
import urllib.request

# --- accent tuning ----------------------------------------------------------
# The accent is the cover's most dominant colour region, found in Oklab:
#   1. Pixels too grey or too dark to name a colour sit out (Oklab chroma and
#      lightness), so black, white and grey art falls back to FALLBACK_RGB.
#   2. The rest are clustered with k-means in Oklab, a perceptual space, so
#      "close" means close to the eye.
#   3. Clusters within ACCENT_MERGE_HUE of each other merge: light and dark red
#      are one colour.
#   4. A colour's area counts only its connected blobs of ACCENT_BLOB_SHARE of
#      the cover or more, so grain, JPEG noise and scattered specks add nothing
#      however many there are.
#   5. Colours rank by that area times their mean chroma, and must cover
#      ACCENT_MIN_SHARE of the cover to count at all.
#
# History: a 12-colour quantised palette scored on HLS saturation came first.
# HLS rates near-black as fully saturated (#020001 is S=1.0), so on dark covers
# a speck of black won and was lifted into a neon tint - The Witcher 3's
# black-and-red cover came out hot pink. A chroma-squared hue histogram
# replaced it, but it ranked pixels by vividness rather than area and had no
# notion of specks, so a small accent next to a large field could lose to
# noise or vanish.
#
# With numpy (optional, and shipped in the Home Assistant image) this runs on
# the whole cover in about a second; without it, the same method runs in plain
# Python on an ACCENT_SIDE thumbnail.
ACCENT_K = 16                   # k-means clusters before merging
ACCENT_ITER = 12
ACCENT_MIN_CHROMA = 0.045       # Oklab chroma; below this a pixel is neutral
ACCENT_MIN_L = 0.30             # Oklab lightness; below this it is too dark to name
# ...unless nothing on the cover clears it: then a second look at this, so deep
# blues and purples (navy is ~0.25) are named instead of falling back to
# neutral. Not the main cut: lower, the darker pixels reshape the clusters and
# a teal beside a blue can merge into it.
ACCENT_MIN_L_DARK = 0.22
ACCENT_MERGE_HUE = 30           # degrees; closer clusters are one colour
ACCENT_BLOB_SHARE = 0.0009      # smaller connected bits are specks
ACCENT_BLOB_MIN_PX = 8
ACCENT_MIN_SHARE = 0.005        # of the whole cover, in blobs, for a colour to count
ACCENT_SIDE = 160               # thumbnail for the plain-Python path
# Floors, so washed-out art still produces something readable against a dark
# panel rather than near-black text.
ACCENT_LIGHT_MIN = 0.58
ACCENT_LIGHT_MAX = 0.82
ACCENT_SAT_MIN = 0.45

FALLBACK_RGB = (235, 235, 235)
FETCH_TIMEOUT = 10

# Default cover size. The skin draws the art at 156px, so 320 is already 2x
# oversampled - and small matters more than it looks.
#
# Rainmeter's WebParser downloads to a FIXED path. If a read stalls part way
# through, Rainmeter keeps that file handle open indefinitely: the partial file
# can never be replaced, it stops decoding, and nothing short of restarting
# Rainmeter clears it. The panel then shows title and artist correctly with a
# blank square where the art should be.
#
# That is not hypothetical - it happened on a Wi-Fi-connected machine once the
# covers grew past half a megabyte, wedging at 192 KB of a 289 KB transfer.
# A tenth of the bytes is a tenth of the exposure. Raise --cover-max if you
# scale the skin up, but know what you are trading.
COVER_MAX_DEFAULT = 320
# 256 colours is visually indistinguishable at this size and roughly halves the
# file again.
COVER_COLOURS = 256


def b64arg(value: str) -> str:
    """Decode a base64 CLI argument, tolerating empties and bad padding."""
    raw = (value or "").strip()
    if not raw:
        return ""
    try:
        return base64.b64decode(raw).decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - never crash the sensor over a title
        return ""


def _to_oklab(r, g, b):
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = lin(r), lin(g), lin(b)
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def _from_oklab(L, a, b):
    l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    rgb = (4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
           -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
           -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)

    def enc(c):
        c = min(1.0, max(0.0, c))
        return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return tuple(enc(c) for c in rgb)


def _hue_deg(a, b):
    return math.degrees(math.atan2(b, a)) % 360


def _hue_gap(h1, h2):
    d = abs(h1 - h2) % 360
    return min(d, 360 - d)


def _dist2(p, c):
    return (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2


def _in_big_blobs(label, w, h, blob_min):
    """For a row-major w x h grid of colour labels (-1 for none), a list
    saying for each cell whether it sits in a 4-connected run of its own label
    at least blob_min cells big. Shared by both pickers: the plain-Python one
    runs it on its thumbnail, the numpy one on a coarse grid of the cover."""
    n = w * h
    keep = [False] * n
    seen = [False] * n
    for start in range(n):
        g = label[start]
        if g < 0 or seen[start]:
            continue
        blob, stack = [], [start]
        seen[start] = True
        while stack:
            i = stack.pop()
            blob.append(i)
            x, y = i % w, i // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    q = ny * w + nx
                    if not seen[q] and label[q] == g:
                        seen[q] = True
                        stack.append(q)
        if len(blob) >= blob_min:
            for i in blob:
                keep[i] = True
    return keep


def _pick_accents_py(img, min_l=ACCENT_MIN_L):
    """pick_accents without numpy: the same method in plain Python, on an
    ACCENT_SIDE thumbnail to keep it to a few seconds."""
    import random

    small = img.copy()
    small.thumbnail((ACCENT_SIDE, ACCENT_SIDE))
    w, h = small.size
    raw = small.tobytes()
    n = w * h
    labs = [None] * n
    pts = []
    for i in range(n):
        L, a, b = _to_oklab(raw[3 * i] / 255, raw[3 * i + 1] / 255, raw[3 * i + 2] / 255)
        if L >= min_l and math.hypot(a, b) >= ACCENT_MIN_CHROMA:
            labs[i] = (L, a, b)
            pts.append(i)
    blob_min = max(ACCENT_BLOB_MIN_PX, int(round(n * ACCENT_BLOB_SHARE)))
    if len(pts) < max(blob_min, n * ACCENT_MIN_SHARE):
        return None, None, None

    # k-means++ seeding with a fixed seed, so a cover always yields the same
    # colours run to run.
    rng = random.Random(0)
    k = min(ACCENT_K, len(pts))
    cents = [labs[pts[rng.randrange(len(pts))]]]
    near = [_dist2(labs[i], cents[0]) for i in pts]
    while len(cents) < k:
        total = sum(near)
        if total <= 0:
            break
        pick, acc, j = rng.random() * total, 0.0, 0
        for j, dist in enumerate(near):
            acc += dist
            if acc >= pick:
                break
        cents.append(labs[pts[j]])
        near = [min(nd, _dist2(labs[i], cents[-1])) for nd, i in zip(near, pts)]
    assign = [0] * len(pts)
    for _ in range(ACCENT_ITER):
        sums = [[0.0, 0.0, 0.0, 0] for _ in cents]
        for j, i in enumerate(pts):
            p = labs[i]
            c = min(range(len(cents)), key=lambda q: _dist2(p, cents[q]))
            assign[j] = c
            s = sums[c]
            s[0] += p[0]
            s[1] += p[1]
            s[2] += p[2]
            s[3] += 1
        cents = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) if s[3] else cents[q]
                 for q, s in enumerate(sums)]

    # Merge clusters closer than ACCENT_MERGE_HUE, biggest first, so each merged
    # colour is anchored on its largest part.
    sizes = [0] * len(cents)
    for c in assign:
        sizes[c] += 1
    group_of = {}
    groups = []  # [hue, size]
    for c in sorted(range(len(cents)), key=lambda q: -sizes[q]):
        if not sizes[c]:
            continue
        hue = _hue_deg(cents[c][1], cents[c][2])
        for g, (gh, _gs) in enumerate(groups):
            if _hue_gap(hue, gh) < ACCENT_MERGE_HUE:
                group_of[c] = g
                groups[g][1] += sizes[c]
                break
        else:
            group_of[c] = len(groups)
            groups.append([hue, sizes[c]])
    label = [-1] * n
    for j, i in enumerate(pts):
        label[i] = group_of[assign[j]]

    # Connected blobs (4-neighbour) per colour; only big-enough ones count.
    kept = [[] for _ in groups]
    for i, ok in enumerate(_in_big_blobs(label, w, h, blob_min)):
        if ok:
            kept[label[i]].append(i)

    ranked = []
    for members in kept:
        if len(members) < n * ACCENT_MIN_SHARE:
            continue
        m = len(members)
        lab = tuple(sum(labs[i][c] for i in members) / m for c in range(3))
        chroma = sum(math.hypot(labs[i][1], labs[i][2]) for i in members) / m
        ranked.append((m * chroma, lab))
    ranked.sort(key=lambda x: -x[0])
    colours = [colorsys.rgb_to_hls(*_from_oklab(*lab)) for _score, lab in ranked[:3]]
    if not colours:
        return None, None, None
    colours += [None] * (3 - len(colours))
    return tuple(colours)


def pick_accents(img):
    """(primary, secondary, third) colours of the cover, each (hue, lightness,
    saturation) in HLS or None, most dominant first. Primary is None when the
    cover has no colour worth naming; secondary and third are None when it has
    fewer distinct colours than that. See the accent tuning comment above.

    Runs on the full cover with numpy, which ships in the Home Assistant
    image. Without it, it falls back to _pick_accents_py, the same method in
    plain Python on an ACCENT_SIDE thumbnail."""
    try:
        import numpy as np

        def pick(min_l):
            return _pick_accents_np(img, np, min_l)
    except ImportError:
        def pick(min_l):
            return _pick_accents_py(img, min_l)
    # A second look at ACCENT_MIN_L_DARK only when the first finds no colour
    # at all, so deep navy and purple covers are still named while brighter
    # covers keep the colours the normal cut gives them.
    found = pick(ACCENT_MIN_L)
    if found[0] is None:
        found = pick(ACCENT_MIN_L_DARK)
    return found


# sRGB -> linear light for every 8-bit value, built once: a table lookup is
# far cheaper than a power per channel over 400k pixels.
_LINEAR = None


def _pick_accents_np(img, np, min_l=ACCENT_MIN_L):
    global _LINEAR
    rgb8 = np.asarray(img.convert("RGB"))
    h, w, _ = rgb8.shape
    n = h * w

    # sRGB -> Oklab, vectorised; same matrices as _to_oklab.
    if _LINEAR is None:
        v = np.arange(256) / 255.0
        _LINEAR = np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)
    lin = _LINEAR[rgb8]
    lms = np.cbrt(lin @ np.array([[0.4122214708, 0.2119034982, 0.0883024619],
                                  [0.5363325363, 0.6806995451, 0.2817188376],
                                  [0.0514459929, 0.1073969566, 0.6299787005]]))
    lab = lms @ np.array([[0.2104542553, 1.9779984951, 0.0259040371],
                          [0.7936177850, -2.4285922050, 0.7827717662],
                          [-0.0040720468, 0.4505937099, -0.8086757660]])
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    mask = (lab[..., 0] >= min_l) & (chroma >= ACCENT_MIN_CHROMA)
    blob_min = max(ACCENT_BLOB_MIN_PX, int(round(n * ACCENT_BLOB_SHARE)))
    if mask.sum() < max(blob_min, n * ACCENT_MIN_SHARE):
        return None, None, None
    pts = lab[mask]

    # k-means++ seeded from a fixed-seed sample (a cover always yields the
    # same colours), then Lloyd iterations over every chromatic pixel.
    rng = np.random.default_rng(0)
    sample = pts[rng.choice(len(pts), size=min(len(pts), 20000), replace=False)]
    k = min(ACCENT_K, len(sample))
    cents = [sample[rng.integers(len(sample))]]
    near = ((sample - cents[0]) ** 2).sum(1)
    while len(cents) < k and near.sum() > 0:
        cents.append(sample[rng.choice(len(sample), p=near / near.sum())])
        near = np.minimum(near, ((sample - cents[-1]) ** 2).sum(1))
    cents = np.array(cents)

    def nearest(p, cs):
        # |p - c|^2 = |p|^2 - 2 p.c + |c|^2: one (pixels x k) matrix rather
        # than a (pixels x k x 3) one.
        return ((p ** 2).sum(1)[:, None] - 2 * p @ cs.T + (cs ** 2).sum(1)[None, :]).argmin(1)
    # The centroids are fitted on the sample, and only the final assignment
    # touches every pixel. A pass over the whole 640px cover costs about a
    # second on the HA box's CPU, so iterating on it took 20s - over the
    # sensor's command_timeout. A 20k-pixel sample places the centroids just
    # as well.
    for _ in range(ACCENT_ITER):
        sa = nearest(sample, cents)
        for c in range(len(cents)):
            hit = sa == c
            if hit.any():
                cents[c] = sample[hit].mean(0)
    assign = nearest(pts, cents)

    # Merge clusters closer than ACCENT_MERGE_HUE, biggest first.
    sizes = np.bincount(assign, minlength=len(cents))
    group_of = np.full(len(cents), -1)
    groups = []  # hue of each group's anchor
    for c in np.argsort(-sizes):
        if not sizes[c]:
            continue
        hue = _hue_deg(cents[c][1], cents[c][2])
        for g, gh in enumerate(groups):
            if _hue_gap(hue, gh) < ACCENT_MERGE_HUE:
                group_of[c] = g
                break
        else:
            group_of[c] = len(groups)
            groups.append(hue)
    label = np.full((h, w), -1)
    label[mask] = group_of[assign]

    # Connected blobs (4-neighbour) per colour; only big-enough ones count.
    # Found on a coarse grid - each cell the majority colour of an f x f block,
    # 160 cells a side for a 640px cover - with the same plain-Python walk the
    # fallback uses. scipy.ndimage.label could do it at full size, but just
    # importing scipy costs 0.7s on the HA box, a quarter of a whole run, and
    # a speck is as small on the grid as on the cover.
    f = max(1, min(h, w) // ACCENT_SIDE)
    gh, gw = h // f, w // f
    blocks = label[:gh * f, :gw * f].reshape(gh, f, gw, f)
    counts = np.stack([(blocks == g).sum((1, 3)) for g in range(len(groups))])
    cells = counts.argmax(0)
    cells[counts.max(0) * 2 < f * f] = -1  # mostly grey or dark: no colour
    cell_min = max(ACCENT_BLOB_MIN_PX, int(round(gh * gw * ACCENT_BLOB_SHARE)))
    big = np.array(_in_big_blobs(cells.ravel().tolist(), gw, gh, cell_min)).reshape(gh, gw)
    big_cells = np.where(big, cells, -1)
    in_big = np.full((h, w), -1)
    in_big[:gh * f, :gw * f] = np.repeat(np.repeat(big_cells, f, 0), f, 1)
    ranked = []
    for g in range(len(groups)):
        keep = (label == g) & (in_big == g)
        m = int(keep.sum())
        if m < n * ACCENT_MIN_SHARE:
            continue
        ranked.append((m * float(chroma[keep].mean()), tuple(lab[keep].mean(0))))
    ranked.sort(key=lambda x: -x[0])
    colours = [colorsys.rgb_to_hls(*_from_oklab(*mean)) for _score, mean in ranked[:3]]
    if not colours:
        return None, None, None
    colours += [None] * (3 - len(colours))
    return tuple(colours)


def pick_accent(img) -> tuple[int, int, int]:
    """Choose a vibrant, readable accent colour from the artwork: the most
    dominant colour region (pick_accents), lifted to the readability floors.

    Neutral art (black, white, grey, sepia) has no hue worth tinting with, so
    it gets FALLBACK_RGB rather than an invented colour.
    """
    primary = pick_accents(img)[0]
    if primary is None:
        return FALLBACK_RGB
    hue, light, sat = primary
    light = min(max(light, ACCENT_LIGHT_MIN), ACCENT_LIGHT_MAX)
    sat = max(sat, ACCENT_SAT_MIN)
    return tuple(int(round(v * 255)) for v in colorsys.hls_to_rgb(hue, light, sat))


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=FETCH_TIMEOUT) as resp:
        return resp.read()


def write_atomic(path: str, data: bytes) -> None:
    """Write via a temp file and rename.

    Rainmeter polls these paths continuously and must never read a half-written
    file - a torn PNG shows as a broken image until the next track.
    """
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--www", default="/config/www", help="HA www folder")
    ap.add_argument("--name", default="nowplaying", help="output basename")
    ap.add_argument(
        "--ha-base",
        default="http://127.0.0.1:8123",
        help="base URL used to resolve relative entity_picture paths, and "
        "baked into cover_url for Rainmeter. Use the address the Rainmeter "
        "PC can reach, e.g. http://192.168.1.10:8123",
    )
    ap.add_argument("--picture", default="", help="entity_picture (absolute or /api/...)")
    ap.add_argument("--title-b64", default="")
    ap.add_argument("--artist-b64", default="")
    ap.add_argument("--album-b64", default="")
    ap.add_argument("--source-b64", default="", help="friendly name of the player")
    ap.add_argument("--state", default="unknown")
    ap.add_argument(
        "--cover-max",
        type=int,
        default=COVER_MAX_DEFAULT,
        help="longest edge of the published cover in px (default %d). See the "
        "comment by COVER_MAX_DEFAULT before raising it." % COVER_MAX_DEFAULT,
    )
    args = ap.parse_args()

    title = b64arg(args.title_b64)
    artist = b64arg(args.artist_b64)
    album = b64arg(args.album_b64)
    source = b64arg(args.source_b64)

    json_path = os.path.join(args.www, f"{args.name}.json")
    cover_name = f"{args.name}_cover.png"
    cover_path = os.path.join(args.www, cover_name)

    payload = {
        "title": title,
        "artist": artist,
        "album": album,
        "source": source,
        "state": args.state,
        "ver": "none",
        "art": "none",
        "rgb": list(FALLBACK_RGB),
        "hex": "#%02x%02x%02x" % FALLBACK_RGB,
        # Rainmeter's FontColor wants bare "r,g,b" - handing it a preformatted
        # string keeps arithmetic out of the skin.
        "rgb_rm": "%d,%d,%d" % FALLBACK_RGB,
        "cover_url": "",
    }

    def emit(code: int = 0) -> int:
        try:
            write_atomic(
                json_path, json.dumps(payload, ensure_ascii=False).encode("utf-8")
            )
        except Exception as err:  # noqa: BLE001
            sys.stderr.write(f"cannot write {json_path}: {err}\n")
            return 1
        sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
        return code

    picture = (args.picture or "").strip()
    if not picture or picture in ("None", "unknown", "unavailable"):
        payload["art"] = "no-art"
        return emit()

    try:
        from PIL import Image
    except ImportError:
        # Pillow ships with the official HA container. On a bare venv install
        # the metadata still works, just without artwork or an accent.
        payload["art"] = "err:pillow-missing"
        return emit()

    # Spotify and friends hand back absolute https URLs; HA-proxied artwork is
    # a relative /api/... path that needs the base prefixed.
    url = picture if picture.startswith("http") else args.ha_base.rstrip("/") + picture
    try:
        data = fetch(url)
    except Exception as err:  # noqa: BLE001 - degrade, never crash the sensor
        payload["art"] = f"err:fetch:{type(err).__name__}"
        return emit()

    # Cache-buster derived from the image bytes, so Rainmeter re-downloads
    # exactly when the artwork really changed - not on every poll, and not
    # never. Some players serve every cover from one fixed URL, which is why
    # keying off the URL alone does not work.
    payload["ver"] = hashlib.sha1(data).hexdigest()[:10]

    try:
        from PIL import ImageOps

        img = Image.open(io.BytesIO(data)).convert("RGB")
        accent = pick_accent(img)
        payload.update(
            rgb=list(accent),
            hex="#%02x%02x%02x" % accent,
            rgb_rm="%d,%d,%d" % accent,
        )
        # Square, and never upscaled: enlarging a small cover adds no detail,
        # it only adds bytes for the download to stall on. Rainmeter scales it
        # to the art box either way.
        side = min(args.cover_max, min(img.size))
        square = ImageOps.fit(img, (side, side), Image.LANCZOS, centering=(0.5, 0.5))
        buf = io.BytesIO()
        square.convert("P", palette=Image.ADAPTIVE, colors=COVER_COLOURS).save(
            buf, "PNG", optimize=True
        )
        write_atomic(cover_path, buf.getvalue())
        payload["art"] = "ok"
        payload["cover_url"] = "%s/local/%s?v=%s" % (
            args.ha_base.rstrip("/"),
            cover_name,
            payload["ver"],
        )
    except Exception as err:  # noqa: BLE001
        payload["art"] = f"err:decode:{type(err).__name__}"

    return emit()


if __name__ == "__main__":
    sys.exit(main())
