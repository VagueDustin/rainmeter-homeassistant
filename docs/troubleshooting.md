# Troubleshooting

## The panel is blank / never appears

The now-playing skin hides itself unless `state` is `playing` or `paused`, and
it also hides on a failed download so a dead HA does not leave yesterday's track
frozen on the wall. So a blank panel means one of: nothing is playing, the JSON
is unreachable, or the regex did not match.

Check in this order:

1. Open `http://<your-ha>:8123/local/nowplaying.json` **from the Rainmeter PC**.
   Not from your laptop — the point is whether that machine can reach it.
2. Check `HA=` in the `.ini` matches that URL exactly, including port.
3. In Rainmeter, right-click the skin → **Manage skin** and look at the log.

## The text renders but the artwork does not

- `"art": "ok"` in the JSON but no image: Rainmeter downloaded nothing. Check
  `cover_url` in the JSON is an address the *desktop* can reach — if it says
  `127.0.0.1`, you set `--ha-base` wrong on the HA side.
- The art is a track behind: your source announces the title before the artwork
  URL resolves. The refresh automation re-runs on a ladder for exactly this; add
  another step or two to `for_each`.

## Weird characters instead of a degree sign

`Ã‚Â°` or similar means a `.ini` picked up non-ASCII. Rainmeter reads a `.ini`
with no BOM as ANSI. Either save the file as UTF-16 LE **with** a BOM, or —
better — keep the `.ini` ASCII and move the symbol into the JSON, which is what
this project does. Change the unit in the YAML, not the skin.

## Descenders are sliced off (the tail of g, y or p)

`ClipString=2` clips to **both** W and H, so a clip box shorter than the font's
full line box cuts the bottoms off. A point is 1.333 px, so a 22pt line box is
about 35px - a box of 34 looks right until a word with a descender comes along.

The skin derives each line's height from its font size (`H=(#TitleSize#*2)`)
so this cannot come back. If you change `TitleSize` or `ArtistSize`, leave the
`*2` alone: it clears the descenders and is still well short of two lines, so
long text ellipsizes instead of wrapping.

## The optional "playing on ..." line will not hide

`!ShowMeterGroup` un-hides every meter in the group, overriding a static
`Hidden=`. The skin re-asserts the setting immediately after the group show for
this reason. If you add another optional meter to the `NowPlaying` group, it
needs the same treatment.

## The panel width jumps a beat late

Expected. The width follows off-screen extent probes whose `:W` carries the
previous update's value, so the panel resizes one update after the text changes.
At a 1-second update rate you will not notice; at a much slower rate you will.

## The status board shows fewer people than I configured

`count` in the JSON drives how many slots are drawn and how they are spaced.
Slots past the count hide themselves. If someone is missing, check they are
inside the first six entries of `people` and that the entity id is right — a
typo produces an entity that never matches `home_states`, which renders as
present-but-away rather than as an error.

## Arrival times show from yesterday

They should not — the template only emits a time if `last_changed` is today.
If you see a stale one, the board has not re-rendered since midnight; confirm
the `00:00:01` trigger in the refresh automation still exists.

## Nothing updates at all after editing YAML

`command_line` sensors need a full Home Assistant restart when first added.
After that, edits to the *template* take effect on a template reload, but edits
to the `command:` itself need another restart.
