# KDE Plasma 6 widgets

Native Plasma 6 ports of both skins, for Linux desktops running KDE. They read the same `/local/nowplaying.json` and `/local/statusboard.json` as the Rainmeter skins, so the Home Assistant side is unchanged and no access token is stored on the desktop.

```
local.ha.nowplaying/     HA Now Playing: art, title, accent-tinted artist line, source line
local.ha.statusboard/    HA Status Board: clock, up to 4 stats and 6 chips
```

Behaviour matches the skins: Now Playing is only visible while something is playing or paused, and the Status Board keeps its clock ticking but hides the rows and shows a notice when `ts` stops advancing for longer than the stale limit.

What the widgets add over the skins (Now Playing 1.1.0, Status Board 1.4.0):

- **Glass panels.** A light, mostly clear pane with a bright rim, a sheen and a soft drop shadow (`Frost.qml`), instead of a flat dark rectangle. Turn **Frosted glass panel** off for the plain panel colour.
- **Panels sized to their content.** The status board is as wide and tall as what it shows (up to **Maximum board width**), so a short board leaves no empty band.
- **Long lines scroll.** Now Playing caps each line at **Maximum text width**; a longer title or artist holds for two seconds, then scrolls in a seamless loop (`Marquee.qml`). Short lines stay still.
- **Source line in the second accent.** With **Show which player it's coming from** on, the player name sits under the artist, tinted with the cover's second colour (`hex2` from `nowplaying.py`), falling back to the main accent.
- **Sharp text.** Text is drawn with hinting (native rendering) and a crisp 1 px shadow, so it stays sharp on large, low-density screens.

Tested on CachyOS with Plasma 6 on Wayland.

## Install

1. Set up the Home Assistant side first, exactly as in [docs/install.md](../docs/install.md), and check that both JSON files open in a browser on the desktop machine. Set `--ha-base` to the URL **this** machine uses to reach HA, since it is baked into `cover_url`.
2. Install the widgets:
   ```sh
   kpackagetool6 -t Plasma/Applet -i kde/local.ha.nowplaying
   kpackagetool6 -t Plasma/Applet -i kde/local.ha.statusboard
   ```
   To update later, use `-u` instead of `-i`. Copying the two folders into `~/.local/share/plasma/plasmoids/` works too.
3. Restart Plasma so it picks them up (`systemctl --user restart plasma-plasmashell`, or log out and in).
4. Right-click the desktop, **Enter Edit Mode**, **Add Widgets**, search for `HA`, and drag each one onto the desktop.
5. Right-click each widget, **Configure**, and set **Home Assistant URL** to the same base you used for `--ha-base`.

## Configuration

Everything that was a variable at the top of a skin's `.ini` is a field in the widget's settings dialog: poll interval, stale limit, clock and date format, alignment, width, panel on or off, corner radius, font and colours. Colours take `#AARRGGBB`, so the alpha comes first.

Two settings scale a whole widget:

- **Scale (%)** multiplies every size (text, padding, artwork, panel). 100% is the original design.
- **Minimum text size (px)** is a floor for every line after scaling (0 = none).

100% and 0 suit a desktop monitor. For a projector or a TV seen from across a room, start at **125%** with a **16 px** floor. Enlarge the widget's own area on the desktop to match, or the panel is clipped to it.

What the rows *show* is still decided in the HA package YAML, not in the widget.

## On a projector or a big TV

Lessons from running both widgets full-time on a 115" 1080p projector:

- **Soft or blurry text.** At 1080p on a large screen each pixel is over a millimetre wide, so thin, small type is mostly anti-aliasing. Raise **Scale** and **Minimum text size** (above) rather than individual font sizes; the hinted rendering keeps the larger text crisp. A heavy wallpaper shadow is not needed: the 1 px shadow carries readability.
- **Margins that look unequal.** Check the PC's own output first (a screenshot): if the panels are evenly spaced there, the projector or the screen frame is cropping or skewing the image. Fix it on the projector (keystone or four-corner correction, or turn its overscan off) rather than offsetting the widgets. Corner correction digitally resamples the picture and softens it slightly; squaring the projector physically avoids that.
- **Widgets snap to a 16 px grid.** Plasma rounds desktop widget positions and sizes to multiples of 16, and 1080 is not one, so an exact bottom margin can be a few pixels off. Now Playing's **Lift panel off the widget bottom** makes up the difference.
- **Colour range.** If blacks look grey or shadows crush, check whether the GPU sends full-range RGB and the projector expects limited (or the reverse) with a black/white-level test pattern, and set the range on the side that allows it.

## Why the glass does not blur the wallpaper

Desktop widgets are drawn in the same scene as the wallpaper, so KWin's window blur cannot reach them. Sampling the wallpaper from inside the widget (`ShaderEffectSource` plus a blur) works in principle, but it crash-looped plasmashell in the NVIDIA GL driver under an animated wallpaper plugin, so the glass is drawn with a tint, rim and sheen instead.

## Troubleshooting

- **Status Board says "Waiting for Home Assistant".** The widget cannot fetch `statusboard.json` or its `ts` is stale. Open `<your HA URL>/local/statusboard.json` from the desktop: a 404 means the HA side is not writing it (see [docs/troubleshooting.md](../docs/troubleshooting.md)), and a connection error means the URL or port is wrong.
- **`.local` hostnames fail although they resolve.** Some setups resolve `homeassistant.local` to a link-local IPv6 address first, which the widget cannot connect to. Use the HA host's IPv4 address instead.
- **Text looks soft on a TV or projector.** See [On a projector or a big TV](#on-a-projector-or-a-big-tv).
- **QML errors.** Run `journalctl --user -b | grep -i local.ha` to see anything the widgets logged.
