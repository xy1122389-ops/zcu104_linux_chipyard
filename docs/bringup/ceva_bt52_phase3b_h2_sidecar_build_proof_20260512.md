# CEVA BT5.2 Phase 3B-H2 Sidecar Build Proof

## 1. Goal

H2 proves that the Phase 3B-H1 sidecar skeleton has a repeatable local build flow and does not require board, J-Link, Vivado, bitstream rebuild, payload rebuild, driver edits, RTL edits, or vendor runtime assets.

This is still a build-only proof. It is not a real controller proof and it does not claim that CEVA vendor runtime is running.

## 2. Inputs

- H1 sidecar skeleton directory: `sidecar/ceva_bt52_sidecar/`
- Build script: `scripts/build_ceva_sidecar.sh`
- Toolchain path prepended by the script: `/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin`
- Expected outputs: `build/sidecar.elf`, `build/sidecar.bin`, `build/sidecar.map`

## 3. Commands Run

```bash
chmod +x scripts/build_ceva_sidecar.sh
bash scripts/build_ceva_sidecar.sh
bash scripts/build_ceva_sidecar.sh
```

The script performs `make clean` before each build, so the two runs are independent clean builds.

## 4. Result

| Check | Result |
|---|---|
| Clean build run 1 | PASS |
| Clean build run 2 | PASS |
| `sidecar.elf` exists | PASS |
| `sidecar.bin` exists | PASS |
| `sidecar.map` exists | PASS |
| Repeatable SHA256 | PASS |
| Board/J-Link/Vivado/rebuild used | NO |

Binary evidence:

```text
sidecar.bin sha256 = 698c82e5b6f9185d414d1509445749366accc7c1d41bb67c9af8d9d267302f55
sidecar.bin size   = 296 bytes
```

## 5. Artifact Policy

The build products are generated artifacts and must not be committed:

- `sidecar/ceva_bt52_sidecar/build/sidecar.elf`
- `sidecar/ceva_bt52_sidecar/build/sidecar.bin`
- `sidecar/ceva_bt52_sidecar/build/sidecar.map`
- `sidecar/ceva_bt52_sidecar/build/sidecar.dump`
- object files under `sidecar/ceva_bt52_sidecar/build/`

Before committing H2, the build directory is cleaned and only source/script/documentation files are staged.

## 6. PASS / PARTIAL / BLOCKED

PASS: H2 build proof is complete. The sidecar skeleton can be rebuilt twice from clean state with an identical binary hash.

PARTIAL: None.

BLOCKED: None.

## 7. Next Safe Action

Proceed to Phase 3B-H3 only after creating a new safety checkpoint. H3 is the first phase that may use a light board/J-Link marker load proof, but it must first prove that the sidecar load address and marker address do not overwrite OpenSBI, Linux, DTB, initramfs, or existing stage markers.
