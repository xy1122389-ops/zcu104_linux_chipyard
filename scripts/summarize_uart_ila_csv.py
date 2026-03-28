#!/usr/bin/env python3
from __future__ import annotations

import csv
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <uart_ila.csv>", file=sys.stderr)
        return 2

    csv_path = Path(sys.argv[1])
    if not csv_path.exists():
        print(f"missing csv: {csv_path}", file=sys.stderr)
        return 3

    with csv_path.open() as f:
        reader = csv.DictReader(f)
        try:
            next(reader)  # skip radix row
        except StopIteration:
            print(f"empty csv: {csv_path}", file=sys.stderr)
            return 4
        rows = list(reader)

    if not rows:
        print(f"no samples: {csv_path}", file=sys.stderr)
        return 5

    ignore = {"Sample in Buffer", "Sample in Window"}

    print(f"CSV={csv_path}")
    print(f"SAMPLES={len(rows)}")
    for name in reader.fieldnames or []:
        if name in ignore:
            continue
        vals = [row[name] for row in rows]
        uniq = ",".join(sorted(set(vals)))
        transitions = sum(a != b for a, b in zip(vals, vals[1:]))
        head = ",".join(vals[:8])
        tail = ",".join(vals[-8:])
        print(f"{name}: uniq={uniq} transitions={transitions} head={head} tail={tail}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
