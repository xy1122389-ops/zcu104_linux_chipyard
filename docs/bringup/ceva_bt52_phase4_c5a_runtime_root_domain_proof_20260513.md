# CEVA BT5.2 Phase4-C5a OpenSBI Validate/Marker Runtime Proof

## 1. Goal

Phase4-C5a turns the ad-hoc board check used during C5 development into a formal runtime proof step for the final no-map ownership model.

The proof confirms that OpenSBI entered the reserved-memory validation path, claimed the boot-owner marker, and did not create an overlapping root-domain carveout for Linux's `ceva_runtime_reserved@8fbe0000` region.

## 2. Proof Method

The checker can run against board state or against the accepted C6 proof log. In log mode it verifies the boot-owner marker, reserved start/size, Linux reserved-memory line, and the absence of active `mmode_resv*` overlap. In GDB mode it confirms the root-domain table remains unexpanded for the CEVA envelope.

The proof is expected to show:

- boot-owner marker claimed by OpenSBI;
- reserved start `0x8FBE0000` and size `0x00320000`;
- Linux reports `OF: reserved mem` for `ceva_runtime_reserved@8fbe0000`;
- no active `mmode_resv*` node overlaps the CEVA reserved envelope;
- root-domain carveout remains disabled and Linux no-map ownership is authoritative.

## 3. Checker

```bash
bash scripts/check_ceva_phase4c5_runtime_root_domain_proof.sh
```

Expected result in the current phase:

```text
P4C_OPENSBI_ROOT_DOMAIN_RUNTIME_PROOF=PASS
P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT=PASS
P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT_DISABLED=PASS
P4C_LINUX_NO_MAP_OWNS_RESERVED_MEMORY=PASS
P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS
```

## 4. What This Proves

This proof is stronger than the earlier breakpoint-only check.

It proves that:

- the reserved-memory validation path executes on hardware;
- OpenSBI claims the boot-owner marker for the published envelope;
- Linux owns the same range through no-map reserved memory;
- overlapping OpenSBI `mmode_resv*` carveout nodes are absent.

## 5. What This Still Does Not Prove

- It does not prove P4-D vendor build reproducibility.
- It does not prove P4-E driver lifecycle hardening.
- It does not prove sidecar runtime starts automatically.
- It does not replace P4-F interrupt/timer/power hardening.