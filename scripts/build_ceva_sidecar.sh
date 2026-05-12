#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIDECAR_DIR="${ROOT_DIR}/sidecar/ceva_bt52_sidecar"
TOOLCHAIN_PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin"

export PATH="${TOOLCHAIN_PATH}:${PATH}"

command -v riscv64-unknown-elf-gcc >/dev/null
command -v riscv64-unknown-elf-objcopy >/dev/null
command -v riscv64-unknown-elf-objdump >/dev/null

make -C "${SIDECAR_DIR}" clean
make -C "${SIDECAR_DIR}"

test -s "${SIDECAR_DIR}/build/sidecar.elf"
test -s "${SIDECAR_DIR}/build/sidecar.bin"
test -s "${SIDECAR_DIR}/build/sidecar.map"

sha256sum "${SIDECAR_DIR}/build/sidecar.bin"
riscv64-unknown-elf-size "${SIDECAR_DIR}/build/sidecar.elf"
