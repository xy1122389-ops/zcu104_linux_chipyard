#!/usr/bin/env python3
from dataclasses import dataclass


TAP_TLR = "TLR"
TAP_RTI = "RTI"
TAP_SELDR = "SELDR"
TAP_CAPDR = "CAPDR"
TAP_SHDR = "SHDR"
TAP_EX1DR = "EX1DR"
TAP_PADR = "PADR"
TAP_EX2DR = "EX2DR"
TAP_UPDR = "UPDR"
TAP_SELIR = "SELIR"
TAP_CAPIR = "CAPIR"
TAP_SHIR = "SHIR"
TAP_EX1IR = "EX1IR"
TAP_PAIR = "PAIR"
TAP_EX2IR = "EX2IR"
TAP_UPIR = "UPIR"


def next_state(state: str, tms: int) -> str:
    if state == TAP_TLR:
        return TAP_TLR if tms else TAP_RTI
    if state == TAP_RTI:
        return TAP_SELDR if tms else TAP_RTI
    if state == TAP_SELDR:
        return TAP_SELIR if tms else TAP_CAPDR
    if state == TAP_CAPDR:
        return TAP_EX1DR if tms else TAP_SHDR
    if state == TAP_SHDR:
        return TAP_EX1DR if tms else TAP_SHDR
    if state == TAP_EX1DR:
        return TAP_UPDR if tms else TAP_PADR
    if state == TAP_PADR:
        return TAP_EX2DR if tms else TAP_PADR
    if state == TAP_EX2DR:
        return TAP_UPDR if tms else TAP_SHDR
    if state == TAP_UPDR:
        return TAP_SELDR if tms else TAP_RTI
    if state == TAP_SELIR:
        return TAP_TLR if tms else TAP_CAPIR
    if state == TAP_CAPIR:
        return TAP_EX1IR if tms else TAP_SHIR
    if state == TAP_SHIR:
        return TAP_EX1IR if tms else TAP_SHIR
    if state == TAP_EX1IR:
        return TAP_UPIR if tms else TAP_PAIR
    if state == TAP_PAIR:
        return TAP_EX2IR if tms else TAP_PAIR
    if state == TAP_EX2IR:
        return TAP_UPIR if tms else TAP_SHIR
    if state == TAP_UPIR:
        return TAP_SELDR if tms else TAP_RTI
    raise ValueError(state)


@dataclass
class TunnelResult:
    tms_by_rising: list
    states: list
    shifted_ir_bits: list
    shifted_dr_bits: list
    final_ir: int


def simulate_tunnel(packet_bits_lsb_first):
    shift_counter = 0
    pos_counter = 0
    neg_counter = 0
    tdi_reg = 0
    state = TAP_RTI
    shifted_ir = []
    shifted_dr = []
    ir_reg = 0x01  # assume capture-ir loads ...00001
    tms_seq = []
    states = [state]

    for tdi in packet_bits_lsb_first:
        prev_state = state
        # posedge bookkeeping
        if 1 <= pos_counter <= 7:
            shift_counter = ((tdi & 1) << 6) | (shift_counter >> 1)
        if pos_counter == 0:
            tdi_reg = 0 if tdi else 1

        # tms as seen on this rising edge comes from current neg_counter
        if neg_counter == 4:
            tms = tdi_reg
        elif neg_counter == 5:
            tms = 1
        elif neg_counter == shift_counter + 7 or neg_counter == shift_counter + 8:
            tms = 1
        else:
            tms = 0

        # sample into inner TAP
        state = next_state(state, tms)
        if state == TAP_CAPIR:
            ir_reg = 0x01
        # JTAG TAP semantics: the first TCK cycle that enters SHIFT_IR/SHIFT_DR
        # does not yet shift new TDI data into the scan register.
        if state == TAP_SHIR and prev_state == TAP_SHIR:
            shifted_ir.append(tdi)
            ir_reg = ((tdi & 1) << 4) | (ir_reg >> 1)
        elif state == TAP_SHDR and prev_state == TAP_SHDR:
            shifted_dr.append(tdi)
        tms_seq.append(tms)
        states.append(state)

        # counters update after edges
        pos_counter += 1
        neg_counter += 1

    return TunnelResult(tms_seq, states, shifted_ir, shifted_dr, ir_reg)


def packet_mode0(select_bit, width7, payload_bits, trailing3=0):
    bits = [select_bit & 1]
    bits += [(width7 >> i) & 1 for i in range(7)]
    bits += payload_bits
    bits += [(trailing3 >> i) & 1 for i in range(3)]
    return bits


def bits_of_value(value, width):
    return [(value >> i) & 1 for i in range(width)]


def main():
    tests = [
        ("IR select dmi=0x11", packet_mode0(0, 0x05, bits_of_value(0x11, 5))),
        ("IR select dtmcs=0x10", packet_mode0(0, 0x05, bits_of_value(0x10, 5))),
        ("DR dtmcs", packet_mode0(1, 0x20, bits_of_value(0, 33))),
        ("DR dmi-read-0x11", packet_mode0(1, 0x29, bits_of_value(0x4400000001, 42))),
    ]
    for name, bits in tests:
        r = simulate_tunnel(bits)
        print(f"=== {name} ===")
        print("rising_tms:", "".join(str(x) for x in r.tms_by_rising))
        print("states:", " ".join(r.states[:15]), "...")
        print("shifted_ir_bits:", "".join(str(b) for b in r.shifted_ir_bits))
        print("shifted_dr_bits_prefix:", "".join(str(b) for b in r.shifted_dr_bits[:32]))
        print("final_ir: 0x%02x" % r.final_ir)


if __name__ == "__main__":
    main()
