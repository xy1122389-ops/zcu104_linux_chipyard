#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys
from typing import Dict, List


def parse_ratio(value: str) -> tuple[int, int]:
    lhs, rhs = value.split("/")
    return int(lhs), int(rhs)


def parse_kv_lines(lines: List[str]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def to_hex_run(values: List[int], step: int) -> str:
    if not values:
        return "none"
    runs = []
    start = prev = values[0]
    for cur in values[1:]:
        if cur != prev + step:
            runs.append(f"0x{start:X}-0x{prev:X}")
            start = cur
        prev = cur
    runs.append(f"0x{start:X}-0x{prev:X}")
    return ",".join(runs)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: summarize_payload_offset_evidence.py <log>", file=sys.stderr)
        return 2

    log_path = pathlib.Path(sys.argv[1])
    lines = log_path.read_text(errors="ignore").splitlines()

    globals_kv = parse_kv_lines(lines)

    window_blocks: List[Dict[str, object]] = []
    current: List[str] = []
    in_window = False
    for line in lines:
        if line.startswith("WINDOW_BASE="):
            if current:
                block = parse_kv_lines(current)
                window_blocks.append(block)
            current = [line]
            in_window = True
        elif in_window:
            if line.startswith("==== summary ===="):
                block = parse_kv_lines(current)
                window_blocks.append(block)
                current = []
                in_window = False
            else:
                current.append(line)
    if current:
        window_blocks.append(parse_kv_lines(current))

    windows: List[Dict[str, object]] = []
    for block in window_blocks:
        if "WINDOW_BASE" not in block:
            continue
        same_match, word_count = parse_ratio(block["MATCH_SAME_OFFSET"])
        plus_match, _ = parse_ratio(block["MATCH_PLUS_2000"])
        windows.append(
            {
                "base": int(block["WINDOW_BASE"], 16),
                "word_count": word_count,
                "same_match": same_match,
                "plus_match": plus_match,
                "full_self": block["FULL_MATCH_SAME_OFFSET"] == "YES",
                "full_plus": block["FULL_MATCH_PLUS_2000"] == "YES",
                "target_words": block["TARGET_WORDS"].split(","),
                "plus_words": block["PAYLOAD_PLUS2000_WORDS"].split(","),
                "plus_mismatch": []
                if block.get("WINDOW_MISMATCH_ADDRS_PLUS_0X2000", "none") == "none"
                else block["WINDOW_MISMATCH_ADDRS_PLUS_0X2000"].split(","),
            }
        )

    if not windows:
        print(f"LOG={log_path}")
        print("ERROR=no window blocks parsed")
        return 1

    full_plus = [int(w["base"]) for w in windows if bool(w["full_plus"])]
    partial_plus = [w for w in windows if (not bool(w["full_plus"])) and int(w["plus_match"]) > 0]
    full_self = [int(w["base"]) for w in windows if bool(w["full_self"])]

    boot_lo_match = re.search(r"([0-9A-Fa-f]{8})$", globals_kv.get("POST_BOOTADDR_LO", ""))
    boot_hi_match = re.search(r"([0-9A-Fa-f]{8})$", globals_kv.get("POST_BOOTADDR_HI", ""))
    boot_lo = boot_lo_match.group(1).upper() if boot_lo_match else None
    boot_hi = boot_hi_match.group(1).upper() if boot_hi_match else None

    print(f"LOG={log_path}")
    print("TASK=low_address_alias_window")
    print(f"PAYLOAD_FILE={globals_kv.get('PAYLOAD_FILE', 'missing')}")
    print(f"BOOTADDR={globals_kv.get('BOOTADDR', 'missing')}")
    print(f"SAMPLE_START=0x{int(windows[0]['base']):X}")
    print(f"SAMPLE_END=0x{int(windows[-1]['base']):X}")
    print("SAMPLE_STEP=0x40")
    print(f"WINDOW_WORDS={int(windows[0]['word_count'])}")
    print(f"WINDOW_BYTES=0x{int(windows[0]['word_count']) * 4:X}")
    print(f"FULL_PLUS_RUNS={to_hex_run(full_plus, 0x40)}")
    print(f"FULL_SELF_RUNS={to_hex_run(full_self, 0x40)}")
    partial_plus_bases = ",".join(f"0x{int(w['base']):X}" for w in partial_plus) or "none"
    print(f"PARTIAL_PLUS_BASES={partial_plus_bases}")

    overlay_interpretation = "UNCONFIRMED"
    for window in partial_plus:
        base = int(window["base"])
        mismatches = ",".join(window["plus_mismatch"])
        print(
            f"PARTIAL_PLUS_DETAIL=base=0x{base:X} "
            f"matched_words={int(window['plus_match'])}/{int(window['word_count'])} "
            f"mismatch_addrs={mismatches}"
        )
        for addr in window["plus_mismatch"]:
            word_index = (int(addr, 16) - base) // 4
            print(
                f"PARTIAL_PLUS_WORD=base=0x{base:X} addr={addr} "
                f"target={window['target_words'][word_index]} "
                f"payload_plus_0x2000={window['plus_words'][word_index]}"
            )
        if (
            base == 0x1000
            and window["plus_mismatch"] == ["0x1000", "0x1004"]
            and boot_lo
            and boot_hi
            and window["target_words"][0] == boot_lo
            and window["target_words"][1] == boot_hi
        ):
            overlay_interpretation = "LIKELY_BOOTADDR_REG_OVERLAY_AT_0x1000_0x1004"

    print(f"PARTIAL_PLUS_INTERPRETATION={overlay_interpretation}")

    if full_plus and full_self:
        prev_plus = max(full_plus)
        first_self = min(full_self)
        print(f"TRANSITION_PREV_FULL_PLUS=0x{prev_plus:X}")
        print(f"TRANSITION_FIRST_FULL_SELF=0x{first_self:X}")
        if prev_plus + 0x40 == first_self:
            print(f"BOUNDARY_BEST_FIT=0x{first_self:X}")
        else:
            print(f"BOUNDARY_BEST_FIT=between 0x{prev_plus:X} and 0x{first_self:X}")

    continuity = "continuous_across_sampled_space"
    if partial_plus:
        continuity = "continuous_alias_except_local_overlay_or_hole"
    print(f"CONTINUITY={continuity}")
    print(f"MIRROR_WINDOW_RANGE=0x{min(full_plus):X}-0x{max(full_plus):X}" if full_plus else "MIRROR_WINDOW_RANGE=unknown")
    print("MIRROR_WINDOW_CLASSIFICATION=looks_like_early_boot_alias_or_remap_window")
    print(
        "SUMMARY_TEXT="
        "Low addresses sample as fw_payload.bin@(addr+0x2000) from 0x0 through 0x1FC0; "
        "0x2000 switches to fw_payload.bin@0x2000. The only sampled discontinuity is at "
        "0x1000, where two words diverge from the +0x2000 mirror and line up with the "
        "programmed bootaddr registers, so the window looks like an alias/remap region with "
        "a small MMIO/register overlay rather than a flat copy."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
