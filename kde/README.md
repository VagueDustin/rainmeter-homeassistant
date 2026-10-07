# KDE Plasma 6 widgets

Native Plasma 6 ports of both skins, for Linux desktops running KDE. They read the same `/local/nowplaying.json` and `/local/statusboard.json` as the Rainmeter skins, so the Home Assistant side is unchanged and no access token is stored on the desktop.

```
local.ha.nowplaying/     HA Now Playing: art, title, accent-tinted artist line
local.ha.statusboard/    HA Status Board: clock, up to 4 stats and 6 chips
```

Behaviour matches the skins: Now Playing is only visible while something is playing or paused, and the Status Board keeps its clock ticking but hides the rows and shows a notice when `ts` stops advancing for longer than the stale limit.

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

What the rows *show* is still decided in the HA package YAML, not in the widget.

## Troubleshooting

- **Status Board says "Waiting for Home Assistant".** The widget cannot fetch `statusboard.json` or its `ts` is stale. Open `<your HA URL>/local/statusboard.json` from the desktop: a 404 means the HA side is not writing it (see [docs/troubleshooting.md](../docs/troubleshooting.md)), and a connection error means the URL or port is wrong.
- **`.local` hostnames fail although they resolve.** Some setups resolve `homeassistant.local` to a link-local IPv6 address first, which the widget cannot connect to. Use the HA host's IPv4 address instead.
- **QML errors.** Run `journalctl --user -b | grep -i local.ha` to see anything the widgets logged.
