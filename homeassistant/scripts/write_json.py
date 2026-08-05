#!/usr/bin/env python3
"""Write a Home Assistant template's output into www/ as a JSON file.

The generic half of this project. Rainmeter can read `/local/anything.json`
without a token; Home Assistant has no built-in way to *put* a file there. So
this takes a JSON document that a template already rendered, checks it parses,
and writes it atomically.

That split matters: all the logic for the HA Status Board lives in ordinary
YAML templates you can edit, and this script stays a dumb, reusable file
writer. Point a new template at it and you have a new skin's data source
without touching Python.

    write_json.py --www /config/www --out statusboard.json --b64 <base64>

The payload arrives base64-encoded because a rendered JSON document is full of
quotes and braces, and passing that through a shell command line unescaped
will eventually mangle it. HA's `base64_encode` filter does the encoding side.

Exits non-zero and writes nothing if the payload is not valid JSON, so a
broken template leaves the previous good file in place rather than replacing
it with garbage that the skin would render as blanks.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--www", default="/config/www", help="HA www folder")
    ap.add_argument("--out", required=True, help="output filename, e.g. statusboard.json")
    ap.add_argument("--b64", required=True, help="base64 of the JSON document")
    args = ap.parse_args()

    # Never let --out escape www: it is templated from HA config, but a
    # traversal here would write anywhere the HA process can reach.
    name = os.path.basename(args.out)
    if not name or name != args.out:
        sys.stderr.write(f"--out must be a bare filename, got {args.out!r}\n")
        return 2

    try:
        text = base64.b64decode(args.b64).decode("utf-8")
    except Exception as err:  # noqa: BLE001
        sys.stderr.write(f"payload is not valid base64/utf-8: {err}\n")
        return 2

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as err:
        # Almost always an unescaped quote in a template. Echo the offending
        # region rather than the whole document.
        lo = max(0, err.pos - 60)
        sys.stderr.write(f"payload is not valid JSON: {err}\n  near: {text[lo:err.pos + 60]!r}\n")
        return 2

    path = os.path.join(args.www, name)
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(parsed, fh, ensure_ascii=False)
        # Atomic swap: Rainmeter polls this path and must never catch it
        # half-written.
        os.replace(tmp, path)
    except Exception as err:  # noqa: BLE001
        sys.stderr.write(f"cannot write {path}: {err}\n")
        return 1

    sys.stdout.write(json.dumps({"ok": 1, "bytes": len(text), "file": name}) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
