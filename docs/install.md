# Install

Three stages, each verifiable on its own. Do them in order and you will know
exactly which one broke if the panel comes up blank.

## 1. Home Assistant: the producers

Copy the scripts:

```
/config/rainmeter/nowplaying.py
/config/rainmeter/write_json.py
```

Copy the packages to `/config/packages/` and make sure `configuration.yaml` has:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

Now edit the marked blocks:

**`rainmeter_nowplaying.yaml`**
- `exclude` — media players that should never take over the panel (TVs, mostly).
- `--ha-base` — **the URL your desktop uses**, not `127.0.0.1`. It is baked into
  `cover_url`, so the Rainmeter PC has to be able to resolve it. Include the port.

**`rainmeter_statusboard.yaml`**
- `people` — up to six `(entity, LABEL)` pairs. See [sources.md](sources.md).
- `climate_entity` — or `''` to hide the whole temperature block.

Restart Home Assistant (a reload is not enough the first time — `command_line`
sensors are only picked up on a full start).

**Verify:** open `http://<your-ha>:8123/local/nowplaying.json` in a browser. You
should see JSON. Same for `statusboard.json`. If you get a 404, the producer has
not run — check Developer Tools → States for `sensor.rainmeter_now_playing` and
`sensor.rainmeter_status_board`.

## 2. Home Assistant: check the artwork

Play something, then open `http://<your-ha>:8123/local/nowplaying_cover.png`.

If the JSON has `"art": "no-art"`, the chosen player is not reporting an
`entity_picture`. If it says `err:fetch:...`, HA could not download the artwork —
common with Spotify on a VLAN without outbound internet. `err:pillow-missing`
means Pillow is not installed; metadata still works, artwork does not.

## 3. Rainmeter

Copy `skins/HANowPlaying` and `skins/HAStatusBoard` into
`Documents\Rainmeter\Skins\`, then in Rainmeter refresh the skin list and load
`HANowPlaying.ini` and `HAStatusBoard.ini`.

Set `HA=` at the top of each `.ini` to the same URL you used for `--ha-base`.

Both skins place themselves automatically — now playing at the bottom-left,
status board at the top-centre, with a matching margin at any resolution. Drag
them if you want them elsewhere; Rainmeter remembers the position, but a refresh
will snap them back unless you remove the `OnRefreshAction` line.

## Running them on a machine that is not yours

If this is going on a shared or projector PC, the useful property is that the
skins hold no credentials — you can walk away from that machine without leaving
a token on it. See the security note in the [README](../README.md).
