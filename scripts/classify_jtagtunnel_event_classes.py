#!/usr/bin/env python3
import csv
import hashlib
import sys
from pathlib import Path


def event_values(path: Path):
    rows = list(csv.reader(path.open()))[2:]
    out = []
    prev = None
    for row in rows:
        t = tuple(row[3:])
        if t != prev:
            out.append(t)
            prev = t
    return out


def main():
    if len(sys.argv) < 2:
        print("Usage: classify_jtagtunnel_event_classes.py <csv> [<csv> ...]", file=sys.stderr)
        raise SystemExit(2)

    classes = {}
    for arg in sys.argv[1:]:
        p = Path(arg)
        seq = event_values(p)
        h = hashlib.sha256(repr(seq).encode()).hexdigest()
        classes.setdefault(h, {"members": [], "len": len(seq)})
        classes[h]["members"].append(str(p))

    for i, (h, info) in enumerate(sorted(classes.items(), key=lambda kv: (len(kv[1]["members"]) * -1, kv[1]["members"][0])), 1):
        print(f"CLASS {i}")
        print(f"HASH={h}")
        print(f"EVENT_COUNT={info['len']}")
        for m in info["members"]:
            print(m)
        print()


if __name__ == "__main__":
    main()
