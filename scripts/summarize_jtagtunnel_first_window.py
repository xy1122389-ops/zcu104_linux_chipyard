#!/usr/bin/env python3
import csv
import sys
from pathlib import Path


def load_rows(path: Path):
    with path.open() as f:
        rows = list(csv.reader(f))
    header = rows[0][3:]
    data = rows[2:]
    return header, data


def first_shift_window(data):
    shift_idx = 1
    pos_idx = 7
    neg_idx = 8
    start = None
    end = None
    for i, row in enumerate(data):
        shift = row[3 + shift_idx]
        if start is None and shift == "1":
            start = i
        elif start is not None and shift == "0":
            end = i
            break
    if start is None:
        return None
    if end is None:
        end = len(data)
    segment = data[start:end]
    return {
        "start": start,
        "end": end,
        "len": end - start,
        "first": segment[0][3:],
        "last": segment[-1][3:],
        "max_pos": max(int(r[3 + pos_idx], 16) for r in segment),
        "max_neg": max(int(r[3 + neg_idx], 16) for r in segment),
    }


def main():
    if len(sys.argv) < 2:
        print("usage: summarize_jtagtunnel_first_window.py <csv> [<csv>...]")
        raise SystemExit(2)
    for arg in sys.argv[1:]:
        p = Path(arg)
        header, data = load_rows(p)
        print(f"=== {p} ===")
        print("header:", header)
        info = first_shift_window(data)
        if info is None:
            print("no shift window")
            continue
        print(
            f"shift_window start={info['start']} end={info['end']} len={info['len']} "
            f"max_pos=0x{info['max_pos']:02x} max_neg=0x{info['max_neg']:02x}"
        )
        print("first:", info["first"])
        print("last :", info["last"])
        print()


if __name__ == "__main__":
    main()
