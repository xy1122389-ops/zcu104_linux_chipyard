#!/usr/bin/env python3
from collections import defaultdict
from itertools import combinations, product


# Current observed classes from the completed probes.
# Labels are local shorthand only.
OBS = {
    0: "A0",
    1: "M",
    2: "M",
    3: "M",
    4: "D4",
    5: "M",
    6: "M",
    7: "M",
    8: "M",
    9: "M",
    10: "M",
    11: "M",
    12: "M",
    13: "M",
    14: "M",
    15: "D15",
    16: "M",
    17: "M",
    18: "M",
    19: "M",
    20: "D20",
    21: "M",
    22: "D22",
    23: "D23",
    24: "M",
    25: "M",
    26: "D4",
    27: "M",
    28: "D23",
    29: "D20",
    30: "M",
    31: "M",
    32: "D32",
    33: "D33",
    34: "M",
    35: "M",
    36: "M",
    37: "M",   # upload-only recovery pulled this back to main family
    38: "M",   # upload-only recovery pulled this back to main family
    39: "M",
    40: "M",
    41: "M",
    42: "M",
    43: "M",
    44: "M",
    45: "M",
    46: "M",
    47: "M",
    48: "M",
    49: "M",
    50: "D4",
    51: "M",
    52: "M",
    53: "M",
    54: "M",
    55: "M",
    56: "M",
    57: "M",
    # 58 intentionally omitted from rule search because rechecks diverged
    59: "M",
    60: "M",
    61: "M",
    62: "M",
    63: "D63",
}


def bits(v):
    return tuple((v >> i) & 1 for i in range(6))


def feature_bank(v):
    b = bits(v)
    return {
        "b0": b[0],
        "b1": b[1],
        "b2": b[2],
        "b3": b[3],
        "b4": b[4],
        "b5": b[5],
        "low2": v & 0x3,
        "low3": v & 0x7,
        "low4": v & 0xF,
        "low5": v & 0x1F,
        "mod2": v % 2,
        "mod4": v % 4,
        "mod8": v % 8,
        "mod16": v % 16,
        "popcnt5": bin(v & 0x1F).count("1"),
        "popcnt6": bin(v & 0x3F).count("1"),
    }


def partition_by(features, names):
    groups = defaultdict(list)
    for v in OBS:
        key = tuple(features[v][n] for n in names)
        groups[key].append(v)
    return {k: tuple(sorted(vs)) for k, vs in groups.items()}


def score_partition(groups):
    # Lower is better: penalize class mixing inside a bucket.
    score = 0
    details = []
    for key, values in groups.items():
        cls = defaultdict(list)
        for v in values:
            cls[OBS[v]].append(v)
        distinct = len(cls)
        if distinct > 1:
            score += distinct - 1
            details.append((key, {k: tuple(vs) for k, vs in cls.items()}))
    return score, details


def main():
    feats = {v: feature_bank(v) for v in OBS}
    feature_names = list(next(iter(feats.values())).keys())

    best = []
    for width in range(1, 4):
        for names in combinations(feature_names, width):
            groups = partition_by(feats, names)
            score, details = score_partition(groups)
            best.append((score, len(groups), names, details))

    best.sort(key=lambda x: (x[0], x[1], x[2]))
    print("BEST_PARTITIONS")
    for score, ngroups, names, details in best[:20]:
        print(f"score={score} groups={ngroups} features={names}")
        if details:
            for key, cls in details[:4]:
                print(f"  mixed key={key} classes={cls}")
        print()

    print("OBSERVED_CLASSES")
    by_class = defaultdict(list)
    for v, c in OBS.items():
        by_class[c].append(v)
    for c in sorted(by_class):
        print(c, by_class[c])


if __name__ == "__main__":
    main()
