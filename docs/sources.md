# Music sources

The now-playing skin does not know or care which integration is playing. It reads
whatever the source picker in `rainmeter_nowplaying.yaml` selects, and every
Home Assistant media player exposes the same handful of attributes:

| Attribute | Used for |
|---|---|
| `media_title` | the title line, and to decide a player is worth showing |
| `media_artist` (falls back to `media_album_artist`) | the tinted line |
| `media_album_name` | published in the JSON, not drawn by default |
| `entity_picture` | artwork, and therefore the accent colour |
| `friendly_name` | the optional "playing on ..." line |

Anything providing those works. What follows is per-integration detail worth
knowing, not a list of what is supported.

## The default: whatever is playing

Out of the box the picker walks every `media_player`, skips an exclude list, and
takes the first one that is `playing`, falling back to the first `paused` one so
the panel does not vanish the moment you hit pause. Entities with no
`media_title` are ignored, which quietly filters out idle speakers, TVs showing
an input, and group members that mirror a parent.

That is usually all you need. Put your TV and anything else that would fight for
the panel in `exclude`.

## Pinning a priority order

If two things can play at once (a desk speaker and a whole-home group, say),
give the picker an explicit list instead, and the first match in *your* order
wins:

```jinja
{% for p in [ states.media_player.office,
              states.media_player.kitchen,
              states.media_player.whole_home ]
      if p is not none and p.state == want and p.attributes.get('media_title') %}
```

## Music Assistant

Works with no special handling. Two notes:

- MA creates a `media_player` per player *and* mirrors players it has adopted
  from other integrations, so the same audio can appear twice under different
  entity ids. Exclude whichever copy you do not want, or use a pinned list.
- MA serves artwork through its own proxy as a relative `/api/...` path, which
  the script resolves against `--ha-base`. Nothing to configure.

## Spotify

`entity_picture` is an **absolute** `https://i.scdn.co/...` URL rather than an
HA-proxied path. The script handles both: it only prefixes `--ha-base` when the
value starts with `/`. Your HA box does need outbound internet to fetch the
artwork, which is otherwise not a given on a locked-down VLAN.

## Sonos, Cast, DLNA, Squeezelite

Standard. Sonos group members all report the same track; exclude the followers
or pin the coordinator so the panel does not flip between identical entries.

## Plex and Jellyfin

Both report video as well as music. If you only want music on the panel, add a
content-type guard to the picker:

```jinja
and p.attributes.get('media_content_type') in ['music', 'track']
```

## AirPlay receivers and other fixed-path artwork

Some devices serve *every* cover from one unchanging URL. Nothing keyed off the
URL alone can detect a change there, which is exactly why `nowplaying.py`
derives its cache-buster from a hash of the image **bytes**. It re-downloads on
every refresh and only changes `?v=` when the image really differs, so Rainmeter
picks up the new art and does not re-fetch when nothing happened.

Related: some integrations announce the new title *before* the new artwork URL
resolves, so a single fetch on the metadata change grabs the previous track's
cover. The refresh automation re-runs on a short ladder for that reason. If your
source is well behaved, trim the list.

## Universal media player

A [universal media player](https://www.home-assistant.io/integrations/universal/)
is a clean way to collapse several sources into one entity, then point the
picker at just that. Worth it if your picker logic is getting long.

---

# Status board slots

The board has two rows and neither is tied to any particular kind of entity.

**Stats** are `(label, value, colour)`. The value is whatever string you build:

```jinja
('POWER',  states('sensor.house_power') ~ ' W',            AMBER)
('DISK',   states('sensor.nas_free') | round(0) | int ~ '%', WHITE)
('BINS',   states('sensor.next_collection') | title,        BLUE)
('UPTIME', states('sensor.server_uptime'),                  MUTED)
```

**Chips** are `(name, colour, sub-line)`: a coloured word with something small underneath. Good for anything with a state worth glancing at:

```jinja
('DOOR',    GREEN if is_state('binary_sensor.front','off') else RED,
            'Closed' if is_state('binary_sensor.front','off') else 'OPEN')
('PRINTER', GREEN if is_state('sensor.printer','idle') else AMBER,
            states('sensor.printer') | title)
('BACKUP',  GREEN if is_state('binary_sensor.backup_ok','on') else RED,
            states('sensor.backup_age') ~ 'h ago')
```

Two practical limits: four stats and six chips, and each slot clips to its
column width, so keep names short. With six chips on a 680px panel a column is
about 97px.

Anything referenced in a slot must also appear in the sensor's `state`
fingerprint at the top of the package, or the board will not re-render when
that entity changes.

## Presence, specifically

The status board's people list takes any entity whose state is one of
`home_states` (default `home`, `on`, `true`). The arrival time is that entity's
`last_changed`, shown only if it happened today.

- **`person.*`**: the natural fit, and what the example uses.
- **`device_tracker.*`**: same shape; noisier, since Wi-Fi trackers flap.
- **`binary_sensor.*` / `input_boolean.*`**: for a badge reader, a desk sensor,
  or a manual toggle.

## Using an automation's last_triggered instead

If "arrived" means "this automation fired" rather than "this person is home"
(a door contact, a badge scan, a specific arrival routine), swap the per-person
lookup for the automation's `last_triggered`:

```jinja
{%- set lt = state_attr('automation.alex_arrives', 'last_triggered') -%}
{%- set today = lt is not none and (lt | as_local).date() == now().date() -%}
{%- set ns.chips = ns.chips + [(
      'ALEX',
      GREEN if today else RED,
      (lt | as_local).strftime('%-I:%M %p') if today else '--'
    )] -%}
```

This form has a useful property: the "did they arrive today" test *is* the reset.
Nothing needs clearing at midnight, because a timestamp from yesterday simply
stops matching. The board still needs one re-render after the date rolls over,
which is what the midnight trigger in the package is for.
