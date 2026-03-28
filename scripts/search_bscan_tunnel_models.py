#!/usr/bin/env python3
from dataclasses import dataclass
from itertools import product

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


def bits_of_value(value, width):
    return [(value >> i) & 1 for i in range(width)]


@dataclass(frozen=True)
class Model:
    capture_lo: int
    capture_hi: int
    tms_select_idx: int
    tms_force1_idx: int
    exit_a_off: int
    exit_b_off: int
    invert_select: bool
    shift_on_entry: bool


def simulate(packet_bits_lsb_first, model: Model):
    shift_counter = 0
    pos_counter = 0
    neg_counter = 0
    tdi_reg = 0
    state = TAP_RTI
    ir_reg = 0x01

    for tdi in packet_bits_lsb_first:
        prev_state = state
        if model.capture_lo <= pos_counter <= model.capture_hi:
            shift_counter = ((tdi & 1) << 6) | (shift_counter >> 1)
        if pos_counter == 0:
            tdi_reg = (0 if tdi else 1) if model.invert_select else (tdi & 1)

        if neg_counter == model.tms_select_idx:
            tms = tdi_reg
        elif neg_counter == model.tms_force1_idx:
            tms = 1
        elif neg_counter == shift_counter + model.exit_a_off or neg_counter == shift_counter + model.exit_b_off:
            tms = 1
        else:
            tms = 0

        state = next_state(state, tms)
        if state == TAP_CAPIR:
            ir_reg = 0x01

        shift_cond = state == TAP_SHIR and (model.shift_on_entry or prev_state == TAP_SHIR)
        if shift_cond:
            ir_reg = ((tdi & 1) << 4) | (ir_reg >> 1)

        pos_counter += 1
        neg_counter += 1

    return ir_reg


def mode0(widthfield, payloadlen, payload):
    return [0] + bits_of_value(widthfield, 7) + bits_of_value(payload, payloadlen) + bits_of_value(0, 3)


def mode1(widthfield, payloadlen, payload):
    return bits_of_value(0, 3) + bits_of_value(payload, payloadlen) + bits_of_value(widthfield, 7) + bits_of_value(0, 1)


def main():
    tests = {
        "m0_w5_l5": mode0(5, 5, 0x10),
        "m0_w6_l5": mode0(6, 5, 0x10),
        "m0_w8_l5": mode0(8, 5, 0x10),
        "m0_w5_l6": mode0(5, 6, 0x10),
        "m0_w5_l7": mode0(5, 7, 0x10),
        "m1_w5_l5": mode1(5, 5, 0x10),
        "m1_w5_l6": mode1(5, 6, 0x10),
        "m1_w5_l7": mode1(5, 7, 0x10),
    }

    matches = []
    for vals in product(
        range(0, 3),          # capture_lo
        range(5, 9),          # capture_hi
        range(3, 7),          # tms_select_idx
        range(4, 8),          # tms_force1_idx
        range(6, 10),         # exit_a_off
        range(7, 11),         # exit_b_off
        (True, False),        # invert_select
        (True, False),        # shift_on_entry
    ):
        model = Model(*vals)
        if model.capture_hi < model.capture_lo:
            continue
        if model.exit_b_off < model.exit_a_off:
            continue
        r = {k: simulate(v, model) for k, v in tests.items()}

        if not (r["m0_w5_l5"] == r["m0_w6_l5"] == r["m0_w8_l5"]):
            continue
        if r["m0_w5_l6"] == r["m0_w5_l5"]:
            continue
        if r["m0_w5_l7"] == r["m0_w5_l5"]:
            continue
        if r["m1_w5_l5"] != r["m0_w5_l5"]:
            continue
        if r["m1_w5_l6"] != r["m0_w5_l6"]:
            continue
        if r["m1_w5_l7"] != r["m0_w5_l7"]:
            continue
        matches.append((model, r))

    print(f"matches={len(matches)}")
    for model, r in matches[:40]:
        print(model)
        for k in sorted(r):
            print(f"  {k} -> 0x{r[k]:x}")


if __name__ == "__main__":
    main()
