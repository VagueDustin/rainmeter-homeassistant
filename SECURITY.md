# Security

## Reporting a vulnerability

Please report it privately through GitHub rather than in a public issue: on this repository's
**Security** tab, choose **Report a vulnerability** (private vulnerability reporting). The report is
visible only to the maintainer until a fix is published.

Include what you found and how to reproduce it. Leave out real Home Assistant addresses, entity
names and tokens.

## Supported versions

Only the latest version of each skin and widget on the `main` branch receives fixes.

## Scope

The design keeps credentials off the desktop: Home Assistant writes data into `www/`, served at
`/local/`, and the skins only read it. Anything that leaks a token, exposes more than is shown on
screen, or lets a crafted media title or payload execute code (in the HA scripts, the Rainmeter
skins or the Plasma widgets) is in scope.

By design, anyone who can reach your Home Assistant host can read the published files under
`/local/`; that is documented behaviour, not a vulnerability. Issues in Home Assistant, Rainmeter
or Plasma themselves belong with those projects.
