#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def event_values(path: Path):
    rows = list(csv.reader(path.open()))[2:]
    out = []
    last = None
    for row in rows:
        vals = tuple(row[3:])
        if vals != last:
            out.append(vals)
            last = vals
    return out


def main():
    if len(sys.argv) < 3:
        print("usage: compare_jtagtunnel_event_values.py <csv_a> <csv_b> [<csv_c> ...]")
        raise SystemExit(2)

    paths = [Path(arg) for arg in sys.argv[1:]]
    seqs = {str(p): event_values(p) for p in paths}
    names = list(seqs)
    base = names[0]
    print(f"BASE={base}")
    print(f"BASE_EVENT_COUNT={len(seqs[base])}")
    for other in names[1:]:
        same = seqs[base] == seqs[other]
        print(f"COMPARE={other}")
        print(f"SAME_VALUES={same}")
        print(f"EVENT_COUNT={len(seqs[other])}")
        if not same:
            for idx, (a, b) in enumerate(zip(seqs[base], seqs[other])):
                if a != b:
                    print(f"FIRST_DIFF_INDEX={idx}")
                    print(f"BASE_VALUES={a}")
                    print(f"OTHER_VALUES={b}")
                    break
        print()


if __name__ == "__main__":
    main()
