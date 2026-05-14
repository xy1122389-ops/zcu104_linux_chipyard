# CEVA BT5.2 Phase5-C Service Lifecycle Soak

## 1. Scope

Phase5-C extends the current single-endpoint baseline into a repeated service lifecycle soak.

This phase reuses the proven service-managed hci0 Reset and Read Local Version path from Phase5-A, then repeats it across multiple rounds to validate stability of the current hci0 plus bluetoothd entry path.

This phase does not claim RF, scan, pair, or connect success.

bluetoothd managing hci0 is treated as a BlueZ entry point only. It does not mean complete BlueZ user-scenario success.

## 2. Goal

The goal of Phase5-C is to prove that the current service lifecycle path is repeatable across multiple rounds without introducing Bluetooth RF or user-flow claims.

Each round must validate at least:

- hci0 appears
- bluetoothd or the service-managed path starts
- ceva_bt_open: OK appears
- HCI Reset passes
- Read Local Version passes
- smoke passes
- boot-owner marker exists
- no panic, Oops, BUG, or segmentation fault appears
- no CEVA fail or Phase25 fail appears
- log and observability bundle are generated successfully

## 3. Runner And Checker

Executable entries:

```text
scripts/run_ceva_phase5c_service_lifecycle_soak.sh
scripts/check_ceva_phase5c_service_lifecycle_soak.sh
```

Default behavior:

- SOAK_ROUNDS=3
- each round calls the existing Phase5-A live refresh runner
- each round writes an independent log directory
- each round writes an independent observability bundle
- the runner emits a summary file for the checker

The checker reads the summary file, validates each round independently, and fails the phase if any round fails.

## 4. PASS Conditions

A Phase5-C PASS requires all attempted rounds to pass.

Required PASS surface:

```text
P5C_SERVICE_LIFECYCLE_SOAK=PASS
P5C_HCI0_REPEATED=PASS
P5C_BLUETOOTHD_MANAGED_HCI0=PASS
P5C_HCI_RESET_RLV_REPEATED=PASS
P5C_DRIVER_OPEN_CLOSE_RESTART=PASS
P5C_LOG_BUNDLE_REPEATABLE=PASS
P5C_SCAN_PAIR_CONNECT=DEFERRED
P5C_RF_PHY_PROOF=DEFERRED
```

## 5. FAIL Conditions

Phase5-C must fail if any of the following is true:

- any round log or bundle is missing
- any round fails the existing Phase5-A contract
- any round is marked FAIL, PARTIAL, or BLOCKED_BY_JLINK
- hci0, ceva_bt_open: OK, Reset PASS, RLV PASS, smoke PASS, or boot-owner marker is missing in any round
- panic, Oops, BUG, segmentation fault, CEVA fail, or Phase25 fail appears in any round
- the result is described as RF, scan, pair, connect, or PHY success

If hardware or J-Link stability prevents a full soak, the runner may still produce a summary with a non-PASS status for evidence capture, but that is not a Phase5-C PASS.

## 6. Current Claim Boundary

Allowed:

- repeated hci0 service lifecycle validation
- repeated bluetoothd-managed entry-path validation
- repeated HCI Reset and Read Local Version validation
- repeated proof-log and observability-bundle generation

Forbidden:

- RF success claim
- scan, pair, or connect claim
- Bluetooth PHY proof claim
- complete BlueZ user-scenario success claim

## 7. Relationship To Phase5 Current Entry

The Phase5 current contract remains anchored on P5-A and P5-B.

When a valid Phase5-C summary is present, the current entry may include P5-C PASS output and advance the stage marker.

When no Phase5-C summary is present, the current entry must keep the existing P5-A plus P5-B PASS surface and report P5-C as deferred.

## 8. Likely Next Steps

Possible next phases after Phase5-C are:

- Phase5-D: service restart, fault-recovery, or negative-path handling around the same single-endpoint baseline
- Phase5-E: longer-horizon soak, crash-bundle hardening, or restart-observability expansion

These future steps must preserve the same no-RF, no-scan, no-pair, and no-connect claim boundary unless a later phase explicitly changes scope.

## 9. Full Soak Baseline Closure

The current full-soak baseline was closed with the following successful run:

```text
run_tag=phase5c_fullsoak_after_jlink_20260514_210043
summary=reports/phase5c_fullsoak_after_jlink_20260514_210043/SUMMARY.txt
overall_status=PASS
attempted_rounds=3
successful_rounds=3
```

Per-round result:

- Round 1: PASS on first attempt
- Round 2: PASS on first attempt
- Round 3: first attempt blocked by J-Link server, per-round reinit executed, second attempt PASS

This means the current Phase5-C runner has a validated per-round J-Link recovery path, and that path was exercised in a real soak PASS rather than only in a synthetic retry flow.

## 10. Evidence And Verification

Retained proof evidence for the successful baseline is stored under:

```text
reports/phase5c_fullsoak_after_jlink_20260514_210043/
```

The retained report contains:

- the top-level Phase5-C summary
- one observability bundle per round
- one proof_run.log per round
- one bundle summary per round with proof log SHA256

Verification completed for this baseline:

- Phase5-C checker PASS
- Phase5 current contract PASS
- round_1 run.log and proof_run.log SHA256 identical
- round_2 run.log and proof_run.log SHA256 identical
- round_3 run.log and proof_run.log SHA256 identical

This baseline still does not claim RF, scan, pair, connect, PHY proof, or complete BlueZ user-scenario success.
