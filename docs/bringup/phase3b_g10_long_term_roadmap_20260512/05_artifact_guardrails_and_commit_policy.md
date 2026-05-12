# Artifact Guardrails And Commit Policy

## 1. Permanent guardrails

Do not commit:

- `generated-src/**`
- `target/**`
- `obj/**`
- `*.bit`
- `*.dcp`
- `*.elf`
- `*.bin`
- `*.dump`
- `fw_payload.bin`
- `initramfs.cpio`
- `initramfs.cpio.gz`
- `chipyard-zcu104-fedora.dtb`
- `chipyard-zcu104-fedora.dts`
- `run_ps_ddr_init.tcl`
- board logs and transient run logs
- vendor source/blob without explicit approval

## 2. Allowed G10 artifacts

Allowed in this phase:

- Markdown roadmap documents under `docs/bringup/phase3b_g10_long_term_roadmap_20260512/`.
- `/tmp/ceva_phase_docs.list` and `/tmp/g9_key_docs_excerpt.log` as temporary local audit files.
- `/tmp/g10_phase_doc_headings.log` as temporary local heading extraction.

Not allowed in this phase:

- payload rebuild output
- bitstream or DCP output
- J-Link logs from new runs
- sidecar source code
- driver changes
- RTL changes

## 3. Commit policy

No commit is made unless the user explicitly requests it after reviewing status.

If a future commit is requested, candidate commit material for G10 is limited to:

```text
docs/bringup/phase3b_g10_long_term_roadmap_20260512/*.md
```

Before any commit:

```bash
git status --short
git diff -- docs/bringup/phase3b_g10_long_term_roadmap_20260512
```

Then explicitly exclude any generated artifacts and protected files.

## 4. Dirty worktree policy

The worktree can contain user or prior-task changes. Do not revert them unless the user explicitly asks.

Protected current files:

- `linux-bringup/dtb/chipyard-zcu104-fedora.dtb`
- `linux-bringup/dtb/chipyard-zcu104-fedora.dts`
- `scripts/run_ps_ddr_init.tcl`

G10 docs must not modify those files.

## 5. Recovery if forbidden artifact appears

If forbidden artifact is untracked:

```bash
git status --short
rm <artifact>   # only when confirmed generated and not user-authored
```

If forbidden artifact is staged:

```bash
git restore --staged <artifact>
```

If forbidden artifact is tracked and modified by the user, do not revert. Report it in final status and ask for explicit instruction before changing it.

## 6. G10 final check

Use this check before reporting completion:
