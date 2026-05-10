# Phase 0E-D Post-Freeze Outer Workspace Audit

## Goal

Audit remaining dirty state in `/root/chipyard` after Phase 0E-D baseline freeze and inner cleanup.

This report does not delete, restore, commit, or push anything.

## Baseline

- Outer repo: `/root/chipyard`
- Inner repo: `/root/chipyard/fpga`
- Outer baseline HEAD: `232f6dec`
- Outer baseline tag: `phase0e-d-dm-sw-irq-repeated-pass-20260509`
- Outer branch: `main`
- Inner baseline HEAD: `2a43a70`
- Inner baseline tag: `phase0e-d-dm-sw-irq-repeated-pass-20260509`
- Inner repo status after second cleanup: clean (`git status --short | wc -l = 0`)

## Important Rule

Do not use the outer repo's view to delete files under `fpga/`.

Reason: `/root/chipyard/fpga` is an independent nested Git repository. A file may look untracked from the outer repo but be tracked in the inner repo.

## Status Files

Generated audit files:

```text
/tmp/phase0e_outer_full_status_after_cleanup.txt
/tmp/phase0e_outer_tracked_modified.txt
/tmp/phase0e_outer_untracked.txt
/tmp/phase0e_outer_artifact_like.txt
/tmp/phase0e_outer_source_config_like.txt
/tmp/phase0e_outer_fpga_related.txt
```

## Snapshot

Outer repo snapshot at audit time:

- Total `git status --short` lines: `782`
- Tracked modified lines: `497`
- Untracked lines: `252`
- Artifact-like lines: `3`
- Source/config-like lines: `779`
- Outer `fpga/`-prefixed lines: `289`

## Count Interpretation

These counts are not all from one disjoint partition:

- `tracked modified` and `untracked` are status buckets derived from the first two status columns.
- `artifact-like` and `source/config-like` are path-pattern buckets derived from the whole status listing.
- `fpga/`-prefixed entries overlap both previous views.

Also, `497 + 252 != 782`.

The remaining `33` lines are other status forms, primarily nested/submodule-style dirty markers such as `m generators/...`, which are neither plain tracked-modified nor untracked lines.

## Artifact-Like Paths

Only three outer status entries matched the audit's artifact-like regex:

```text
?? fpga/.tmp/
?? fpga/scripts/mwr_offset_test.bin
?? fpga/scripts/mwr_small_test.bin
```

Audit conclusion for these three paths:

1. `fpga/.tmp/` sits under the nested `fpga` repository and should only be reviewed from the inner repo context.
2. `fpga/scripts/mwr_offset_test.bin` looks untracked from the outer repo, but the corresponding inner-repo path `scripts/mwr_offset_test.bin` is tracked in `/root/chipyard/fpga`.
3. `fpga/scripts/mwr_small_test.bin` looks untracked from the outer repo, but the corresponding inner-repo path `scripts/mwr_small_test.bin` is tracked in `/root/chipyard/fpga`.

Therefore, none of these paths should be deleted based on the outer repo view alone.

## Source/Config-Like Majority

The overwhelming majority of outer dirty state is source/config-like rather than obvious generated output:

- `779` lines matched the source/config-like bucket.
- These span top-level repo metadata, docs, workflows, configuration files, Scala/Verilog sources, and many nested `fpga/` paths.

This means the outer repo is not in a state where blanket artifact cleanup would be safe.

## Nested `fpga/` View

The outer repo currently sees `289` entries under `fpga/`.

The first part of that list includes both tracked modifications and outer-level untracked views of files that belong to the nested repo, for example:

```text
 M fpga/.gitignore
 M fpga/Makefile
 M fpga/scripts/run_impl_bitstream.tcl
 M fpga/src/main/resources/vcu118/sdboot/linker/sdboot.elf.lds
 ?? fpga/.Xil/
 ?? fpga/.codex
 ?? fpga/.github/
 ?? fpga/.tmp/
 ?? fpga/docs/
 ?? fpga/linux-bringup/
 ?? fpga/logs/
 ?? fpga/scripts/ceva_phase0e_c15_baremetal_probe_read.sh
```

Interpretation:

1. Outer `fpga/` status is heavily polluted by the fact that `fpga` is a nested repository.
2. Outer `?? fpga/...` is not sufficient evidence that a path is disposable.
3. Any future cleanup inside `fpga/` must be driven from `/root/chipyard/fpga`, not from `/root/chipyard`.

## Audit Decision

No cleanup action was taken in this audit.

Recommended rule going forward:

1. Treat `/root/chipyard/fpga` as the authority for anything under `fpga/`.
2. Treat outer-repo `fpga/` untracked entries as informational only.
3. Review outer non-`fpga/` source/config changes separately before any future cleanup.

## Conclusion

The outer repo still has a very large dirty surface (`782` lines), but only `3` lines look artifact-like by simple path matching, and all three live under the nested `fpga/` tree.

Because two of those paths are tracked by the inner repo and the third also belongs to the nested repo namespace, the safe conclusion is:

- do not delete anything under `fpga/` from the outer repo view
- treat the current outer audit as classification only
- keep cleanup authority for nested content inside `/root/chipyard/fpga`