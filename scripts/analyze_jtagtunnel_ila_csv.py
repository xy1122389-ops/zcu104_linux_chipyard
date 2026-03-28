#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def load_csv(path: Path):
    with path.open() as f:
        rows = list(csv.reader(f))
    header = rows[0]
    data = rows[2:]
    return header, data


def events(data):
    last = None
    out = []
    for i, row in enumerate(data):
        vals = row[3:]
        if last is None or vals != last:
            out.append((i, vals))
            last = vals
    return out


def main():
    if len(sys.argv) < 2:
        print("usage: analyze_jtagtunnel_ila_csv.py <csv> [<csv>...]")
        raise SystemExit(2)
    for arg in sys.argv[1:]:
        p = Path(arg)
        header, data = load_csv(p)
        print(f"=== {p} ===")
        print("header:", header[3:])
        print("rows:", len(data))
        ev = events(data)
        print("event_count:", len(ev))
        for idx, vals in ev[:120]:
            print(idx, vals)
        print()


if __name__ == "__main__":
    main()
