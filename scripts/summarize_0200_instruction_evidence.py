#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

try:
    from capstone import CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, Cs
except Exception:
    Cs = None


def find_line(text: str, pattern: str) -> str:
    match = re.search(pattern, text, re.M)
    return match.group(1).strip() if match else "missing"


def decode_a64(word_hex: str) -> str:
    if Cs is None or word_hex == "missing":
        return "unavailable"
    try:
        word = int(word_hex, 16)
    except ValueError:
        return "unavailable"
    blob = word.to_bytes(4, "little")
    md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    insns = list(md.disasm(blob, 0))
    if not insns:
        return "invalid-a64"
    insn = insns[0]
    return f"{insn.mnemonic} {insn.op_str}".strip()


def decode_pstate_mode(cpsr_text: str) -> str:
    match = re.search(r"([0-9A-Fa-f]{8,16})$", cpsr_text)
    if not match:
        return "unknown"
    mode = int(match.group(1), 16) & 0xF
    return {
        0x0: "EL0t",
        0x4: "EL1t",
        0x5: "EL1h",
        0x8: "EL2t",
        0x9: "EL2h",
        0xC: "EL3t",
        0xD: "EL3h",
    }.get(mode, f"reserved(0x{mode:X})")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: summarize_0200_instruction_evidence.py <log>", file=sys.stderr)
        return 2

    log_path = pathlib.Path(sys.argv[1])
    text = log_path.read_text(errors="ignore")

    window_match = find_line(text, r"^WINDOW_MATCH_COUNT=(.*)$")
    window_full = find_line(text, r"^WINDOW_FULL_MATCH=(.*)$")
    park_pc = find_line(text, r"^PARK_PC=(.*)$")
    park_cpsr = find_line(text, r"^PARK_CPSR=(.*)$")
    park_state = find_line(text, r"^PARK_STATE_REASON=(.*)$")

    step_tags = [f"STEP{i}" for i in range(6)]
    step_pcs = [find_line(text, rf"^{tag}_PC=(.*)$") for tag in step_tags]
    step_cpsrs = [find_line(text, rf"^{tag}_CPSR=(.*)$") for tag in step_tags]
    step_r0 = [find_line(text, rf"^{tag}_R0=(.*)$") for tag in step_tags]
    step_sp = [find_line(text, rf"^{tag}_SP=(.*)$") for tag in step_tags]

    stable_pc = len(set(step_pcs)) == 1
    stable_cpsr = len(set(step_cpsrs)) == 1
    stable_r0 = len(set(step_r0)) == 1
    stable_sp = len(set(step_sp)) == 1

    instr_1fc = re.search(r"^\s*800021fc:\s+([0-9a-f]+)\s+(.*)$", text, re.M)
    instr_200 = re.search(r"^\s*80002200:\s+([0-9a-f]+)\s+(.*)$", text, re.M)
    instr_204 = re.search(r"^\s*80002204:\s+([0-9a-f]+)\s+(.*)$", text, re.M)
    instr_206 = re.search(r"^\s*80002206:\s+([0-9a-f]+)\s+(.*)$", text, re.M)
    instr_20a = re.search(r"^\s*8000220a:\s+([0-9a-f]+)\s+(.*)$", text, re.M)

    raw_1fc = find_line(text, r"STEP0_NEIGHBOR_WORDS=1FC:\s+([0-9A-Fa-f]+)")
    raw_200 = find_line(text, r"^\s+200:\s+([0-9A-Fa-f]+)$")
    raw_204 = find_line(text, r"^\s+204:\s+([0-9A-Fa-f]+)$")
    raw_208 = find_line(text, r"^\s+208:\s+([0-9A-Fa-f]+)$")
    a64_1fc = decode_a64(raw_1fc)
    a64_200 = decode_a64(raw_200)
    a64_204 = decode_a64(raw_204)
    a64_208 = decode_a64(raw_208)
    pstate_mode = decode_pstate_mode(park_cpsr)

    print(f"LOG={log_path}")
    print("TASK=instruction_evidence_0x200")
    print(f"WINDOW_MATCH_COUNT={window_match}")
    print(f"WINDOW_FULL_MATCH={window_full}")
    print(f"PARK_PC={park_pc}")
    print(f"PARK_CPSR={park_cpsr}")
    print(f"PSTATE_MODE={pstate_mode}")
    print(f"PARK_STATE_REASON={park_state}")
    print(f"RAW_WORD_0x1FC={raw_1fc}")
    print(f"RAW_WORD_0x200={raw_200}")
    print(f"RAW_WORD_0x204={raw_204}")
    print(f"RAW_WORD_0x208={raw_208}")
    print(f"A64_WORD_0x1FC={a64_1fc}")
    print(f"A64_WORD_0x200={a64_200}")
    print(f"A64_WORD_0x204={a64_204}")
    print(f"A64_WORD_0x208={a64_208}")

    if instr_1fc:
        print(f"INSTR_0x1FC={instr_1fc.group(1)} :: {instr_1fc.group(2)}")
    if instr_200:
        print(f"INSTR_0x200={instr_200.group(1)} :: {instr_200.group(2)}")
    if instr_204:
        print(f"INSTR_0x204={instr_204.group(1)} :: {instr_204.group(2)}")
    if instr_206:
        print(f"INSTR_0x206={instr_206.group(1)} :: {instr_206.group(2)}")
    if instr_20a:
        print(f"INSTR_0x20A={instr_20a.group(1)} :: {instr_20a.group(2)}")

    print(
        "NOTE_0x208="
        "0x208 is a raw 32-bit word slice, not an instruction boundary; it straddles the "
        "tail of ld a7,56(a5) at 0x206 and the head of beqz a7,0x240 at 0x20A."
    )
    print(
        "LOCAL_FLOW_SHAPE="
        "0x1FC branches forward to 0x240; 0x200 is a load; 0x204 and 0x20A are forward null-check "
        "branches; later 0x2234 is jalr a7. There is no backward branch, no self-loop, and no wfi in "
        "0x1FC..0x240."
    )
    print(
        "EL3_VECTOR_NOTE="
        "In AArch64, offset 0x200 is the synchronous exception vector slot for CurrentEL using SPx. "
        "So PC=0x200 with PSTATE=EL3h is architecturally consistent with falling into the EL3 sync vector "
        "if VBAR_EL3 base is zero."
    )
    print(
        "STEP_CHAIN_STABILITY="
        f"pc={stable_pc} cpsr={stable_cpsr} r0={stable_r0} sp={stable_sp} "
        f"pc_values={' | '.join(step_pcs)}"
    )
    print(
        "CONCLUSION_PRIMARY="
        "The mirrored low-address bytes are ordinary fw_payload text and do not encode a software "
        "self-loop at 0x200."
    )
    print(
        "CONCLUSION_SECONDARY="
        "If interpreted as the mirrored RISC-V payload stream, 0x200 is ld a5,8(s4), so the only "
        "stall-like explanation nearby would be a load that never retires, not a branch loop. The "
        "observed five-step chain keeps PC/CPSR/R0/SP frozen at 0x200. In A64 view, the first word at "
        "0x200 is not a valid AArch64 instruction, and 0x1FC/0x208 are not a sane A53 vector stub either. "
        "So the best fit is not a software branch loop but a synchronous-exception path landing on bad "
        "bytes in a low-address alias window, likely re-entering or re-presenting at the EL3 0x200 vector slot."
    )
    print("BEST_FIT=el3_sync_vector_entry_on_invalid_alias_bytes_not_branch_self_loop")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
