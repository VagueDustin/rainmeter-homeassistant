# AGENTS.md

Guidance for coding agents working in this repository. README.md and `docs/` are the full
references.

## What this is

Two desktop panels driven by Home Assistant - **HA Now Playing** and **HA Status Board** - as
Rainmeter skins (Windows) and KDE Plasma 6 widgets (Linux). The core design: no access token on the
desktop. Home Assistant writes small JSON files (and a cover image) into its own `www/` folder, which
it serves unauthenticated at `/local/`, and the skins only read those files.

## Layout

```
homeassistant/scripts/nowplaying.py   runs inside HA: fetches artwork, picks the accent colour, writes JSON + cover
homeassistant/scripts/write_json.py   generic writer: validates a template-rendered JSON payload and writes it atomically
homeassistant/packages/*.yaml         drop-in HA packages: source picker, command_line sensors, refresh
skins/HANowPlaying/, skins/HAStatusBoard/   Rainmeter skins (.ini)
kde/local.ha.nowplaying/, kde/local.ha.statusboard/   Plasma 6 plasmoids (QML)
tests/test_accent.py                  accent-picker regression cases on generated covers, plus the JSON contract
docs/install.md, docs/sources.md, docs/troubleshooting.md
screenshots/                          demonstration data only
```

## Commands

There is no build system or package manifest. The Python scripts use only the standard library plus
optional Pillow (artwork and accent extraction; absent = no cover, neutral accent). The one test suite
covers the accent picker and needs Pillow.

```bash
python -m py_compile homeassistant/scripts/*.py                  # syntax check
python -m unittest discover -s tests -v                           # accent picker + JSON contract
python3 homeassistant/scripts/write_json.py --www <dir> --out statusboard.json --b64 <base64 json>
kpackagetool6 -t Plasma/Applet -i kde/local.ha.nowplaying       # install a widget (-u to update)
journalctl --user -b | grep -i local.ha                           # widget logs
```

Full end-to-end verification needs a Home Assistant instance plus Rainmeter 4.5+ or Plasma 6;
`docs/install.md` explains how to check each stage independently. Say what you could and could not
verify.

## Rules

- **Never introduce a Home Assistant access token on the desktop side**, and never have a skin or
  widget call the HA REST API. Data only flows HA -> `www/` -> skin.
- The published files must contain only what is already on screen; `/local/` is public on the LAN.
- **Keep the `.ini` files ASCII** (and CRLF). Rainmeter reads BOM-less files as ANSI, so non-ASCII
  characters break; format values such as temperature units in the HA YAML instead.
- Skins place themselves from screen size; no hardcoded coordinates.
- The status board is entity-agnostic: what the rows show is built in the package YAML, not in the
  skin or widget. Keep `write_json.py` a dumb, reusable writer that refuses invalid JSON.
- Staleness guard: the writer stamps `ts` (`--stamp ts`), the package re-renders at least every
  5 minutes, and the skins hide data rows when `ts` stops advancing. Keep all three in step. The
  WebParser regex anchors the epoch capture to the closing brace because of `(?U)`.
- The now-playing panel measures text with off-screen "extent probe" meters; a new text line that
  should affect panel width needs its own probe. Don't delete `[MeterCanvas]` in the status board.
- Each panel's version appears in its skin's `[Metadata]` `Version=` and in the matching
  `kde/*/metadata.json`; keep them in step when bumping, and don't bump unless asked.
- Never commit real entity names, people, addresses, hostnames or screenshots from a real home. The
  generated `nowplaying.json`, `nowplaying_cover.png` and `statusboard.json` are gitignored.

## Commit style

Short imperative subjects; skin releases are named after the skin and version
("Status board 1.3.0: staleness guard").
