#!/usr/bin/env python3
"""Compare SBA readback against original payload, with SBA read-bug analysis."""

import sys, os

ORIG = "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin"
READBACK = "/tmp/payload_readback.bin"

def main():
    if not os.path.exists(READBACK):
        print(f"ERROR: {READBACK} not found. Run sba_write_verify.gdb first.")
        sys.exit(1)

    orig = open(ORIG, "rb").read()
    rb = open(READBACK, "rb").read()

    print(f"Original : {len(orig):>12d} bytes  ({ORIG})")
    print(f"Readback : {len(rb):>12d} bytes  ({READBACK})")

    if len(orig) != len(rb):
        print(f"WARNING: size mismatch (diff = {len(rb) - len(orig):+d} bytes)")

    min_len = min(len(orig), len(rb))
    diffs = []
    for i in range(min_len):
        if orig[i] != rb[i]:
            diffs.append(i)

    print(f"\nTotal byte differences: {len(diffs)} / {min_len}")

    if not diffs:
        print("\n*** MATCH — SBA write is clean, payload in DDR is bit-exact ***")
        print("Conclusion: crash is NOT caused by payload corruption.")
        print("Next step: Phase 1 — restore best kernel config and analyze real crash.")
        return

    # Show first 30 diffs with context
    print(f"\nFirst {min(30, len(diffs))} differences:")
    print(f"{'Offset':>12s}  {'Orig':>6s}  {'Readback':>8s}  Context (orig)")
    for d in diffs[:30]:
        ctx_start = max(0, d - 2)
        ctx_end = min(min_len, d + 3)
        ctx_orig = orig[ctx_start:ctx_end].hex(' ')
        ctx_rb = rb[ctx_start:ctx_end].hex(' ')
        print(f"  0x{d:08x}  0x{orig[d]:02x}    0x{rb[d]:02x}      orig[{ctx_start:#x}:{ctx_end:#x}]={ctx_orig}")
        print(f"  {'':12s}  {'':6s}  {'':8s}  rb  [{ctx_start:#x}:{ctx_end:#x}]={ctx_rb}")

    if len(diffs) > 30:
        print(f"  ... and {len(diffs) - 30} more differences")

    # Analyze: is this the known SBA read bug (last 2 bytes of each "line" repeated)?
    # The SBA read bug causes the last 2 bytes of each ~N-byte chunk to be duplicated.
    # Check if diffs cluster at specific intervals.
    print("\n--- Pattern analysis ---")

    # Check if diffs are periodic
    if len(diffs) >= 4:
        intervals = [diffs[i+1] - diffs[i] for i in range(min(50, len(diffs) - 1))]
        from collections import Counter
        ic = Counter(intervals)
        print(f"Interval distribution (top 5): {ic.most_common(5)}")

        # Check the "2-byte tail repeat" pattern:
        # At each diff position, does readback[d] == readback[d-2]?
        tail_repeat_count = 0
        for d in diffs[:100]:
            if d >= 2 and rb[d] == rb[d-2]:
                tail_repeat_count += 1
        print(f"Tail-repeat pattern (rb[d]==rb[d-2]): {tail_repeat_count}/{min(100, len(diffs))} diffs match")

        if tail_repeat_count > 0.7 * min(100, len(diffs)):
            print("\n*** HIGH CONFIDENCE: This is the SBA READ bug (2-byte tail repeat) ***")
            print("The SBA write is likely CORRECT — differences are caused by SBA read corruption.")
            print("Next step: Cross-verify with XSDB mrd -bin to confirm.")
        else:
            print("\n*** Differences do NOT match the known SBA read bug pattern ***")
            print("This may indicate genuine SBA WRITE corruption.")
            print("Next step: Cross-verify with XSDB mrd -bin via DAP path.")

    # Distribution across the file
    print(f"\nDiff distribution across file:")
    BUCKET = 1 * 1024 * 1024  # 1 MB buckets
    buckets = {}
    for d in diffs:
        b = d // BUCKET
        buckets[b] = buckets.get(b, 0) + 1
    for b in sorted(buckets):
        print(f"  {b}MB - {b+1}MB: {buckets[b]} diffs")

if __name__ == "__main__":
    main()
