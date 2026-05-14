# CEVA BT5.2 Phase4-C5 OpenSBI Reserved-Memory Validate/Marker Decision

## 1. Goal

Phase4-C5 upgrades the Phase4-C4 OpenSBI consumption hook into the final ownership decision used by P4-C6.

The selected action is intentionally narrow: Linux owns the CEVA envelope through `no-map` reserved memory, while OpenSBI validates the DT node and claims the boot-owner marker before Linux handoff. OpenSBI root-domain carveout is disabled because it creates overlapping `mmode_resv*` nodes for the same Linux reserved-memory range on this target.

## 2. What This Phase Does

- keeps the Phase4-C3 DTS reserved-memory stub unchanged;
- keeps the Phase4-C4 FDT validation path unchanged;
- keeps the OpenSBI `generic_domains_init()` validate path active;
- claims the boot-owner marker from OpenSBI after DT contract validation;
- freezes the OpenSBI policy metadata as Linux no-map ownership plus validate/marker only.

## 3. What This Phase Does Not Do

- It does not start sidecar runtime.
- It does not re-enable OpenSBI root-domain carveout.
- It does not create `mmode_resv*` nodes for the CEVA envelope.
- It does not replace the later C6 board-level Linux proof.

## 4. Contract

```text
CEVA_OPENSBI_CARVEOUT_POLICY=LINUX_NO_MAP_OWNS_RESERVED_RANGE
CEVA_OPENSBI_CARVEOUT_FLAGS=NONE_VALIDATE_AND_MARKER_ONLY
CEVA_OPENSBI_CARVEOUT_ACTIVE=0
```

## 5. Checker

```bash
bash scripts/check_ceva_phase4c5_opensbi_root_domain_carveout.sh
```

Expected result in the current phase:

```text
P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT=PASS
P4C_OPENSBI_ROOT_DOMAIN_CARVEOUT_DISABLED=PASS
P4C_LINUX_NO_MAP_OWNS_RESERVED_MEMORY=PASS
P4C_RUNTIME_RELEASE_FROM_OPENSBI=PASS
```

## 6. Why This Matters

Before this phase, OpenSBI only validated that the DTS stub matched the published contract. During bringup, an active root-domain carveout was tested and rejected because it overlapped Linux's `ceva_runtime_reserved@8fbe0000` node.

The final C5 policy is therefore explicit: OpenSBI validates and marks ownership, while Linux no-map reserved memory is the sole owner of the range exposed to Linux. Runtime boot validation is completed by C6.