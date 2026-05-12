# G10 Traceability Index

## 1. Input documents used

Collected phase docs list: `/tmp/ceva_phase_docs.list`

G9 key excerpt: `/tmp/g9_key_docs_excerpt.log`

Heading extraction: `/tmp/g10_phase_doc_headings.log`

The current G9 family establishes the active constraints for G10:

- G9 master plan: Route C now, Route B next.
- G9A: vendor runtime minimal asset boundary.
- G9B: dependency tree and baremetal sidecar feasibility.
- G9C: sidecar execution context decision.
- G9D/G9E: ingress/egress EM/SWINT bridge contracts.
- G9H: first patch is sidecar skeleton.
- G9J: 7-day execution schedule.
- G9K: forbidden actions and rollback.
- G9L: deep audit index.

## 2. Output documents

| File | Purpose |
|---|---|
| `00_g10_master_plan.md` | Long-term master plan and success definition. |
| `01_phase0a_to_phase3b_h15_matrix.md` | Full phase matrix from 0A to 3B-H15. |
| `02_architecture_roadmap.md` | Architecture/dataflow/workstream roadmap. |
| `03_execution_matrix_and_checklist.md` | Execution matrix and phase checklists. |
| `04_phase_gate_pass_fail_stop.md` | PASS/FAIL/STOP gate definitions. |
| `05_artifact_guardrails_and_commit_policy.md` | Commit and artifact guardrails. |
| `06_traceability_index.md` | This index and traceability map. |

## 3. Requirement coverage

| User requirement | Covered by |
|---|---|
| Phase 2.5 is synthetic smoke, not full Bluetooth success | `00_g10_master_plan.md`, `04_phase_gate_pass_fail_stop.md` |
| Root cause is missing CEVA consumer | `00_g10_master_plan.md`, `02_architecture_roadmap.md` |
| Do not write full Bluetooth stack | `00_g10_master_plan.md`, `02_architecture_roadmap.md` |
| Linux Host by Bluetooth core / BlueZ | `02_architecture_roadmap.md` |
| Controller by CEVA vendor runtime | `00_g10_master_plan.md`, `02_architecture_roadmap.md` |
| H4 is framing only | `00_g10_master_plan.md`, `02_architecture_roadmap.md` |
| Do not put vendor runtime in Linux kernel | `00_g10_master_plan.md`, `03_execution_matrix_and_checklist.md` |
| Do not create userspace fake controller | `00_g10_master_plan.md`, `04_phase_gate_pass_fail_stop.md` |
| Correct route is host shim -> bridge -> sidecar -> vendor runtime | `00_g10_master_plan.md`, `02_architecture_roadmap.md` |
| First long-term implementation is sidecar skeleton | `01_phase0a_to_phase3b_h15_matrix.md`, `03_execution_matrix_and_checklist.md` |

## 4. Next recommended action

Start Phase 3B-H1 only after reviewing this G10 document set. H1 should add sidecar skeleton source and marker constants; it should not modify driver, RTL, payload, DTB/DTS, Vivado inputs, or generated outputs.
