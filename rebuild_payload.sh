#!/usr/bin/env bash
# rebuild_payload.sh - Rebuild initramfs.cpio, Linux Image, and OpenSBI fw_payload.bin

set -euo pipefail
ROOT_DIR="/root/chipyard/fpga"
TOOLCHAIN_DIR="/root/chipyard/.oclaw-env/riscv-tools/bin"
export PATH="$TOOLCHAIN_DIR:$PATH"

LINUX_CROSS="$TOOLCHAIN_DIR/riscv64-unknown-linux-gnu-"
OPENSBI_CROSS="$TOOLCHAIN_DIR/riscv64-unknown-elf-"

INITRAMFS_DIR="$ROOT_DIR/linux-bringup/initramfs"
ROOTFS_DIR="$INITRAMFS_DIR/rootfs"
INITRAMFS_CPIO="$INITRAMFS_DIR/initramfs.cpio"
INITRAMFS_GZ="$INITRAMFS_DIR/initramfs.cpio.gz"
ROOTFS_MODULE_DIR="$ROOTFS_DIR/lib/modules"
PHASE25_SMOKE_SRC="$INITRAMFS_DIR/phase25_user_hci_smoke.c"
PHASE25_SMOKE_BIN="$ROOTFS_DIR/sbin/phase25_user_hci_smoke"
STAGE_MARK_SRC="$INITRAMFS_DIR/stage_mark.c"
STAGE_MARK_BIN="$ROOTFS_DIR/sbin/stage_mark"

KERNEL_DIR="/root/chipyard/software/firemarshal/boards/default/linux-clean"
LINUX_IMAGE="$KERNEL_DIR/arch/riscv/boot/Image"
CEVA_DRIVER_DIR="$ROOT_DIR/linux-bringup/kernel/ceva-bt52-driver"

OPENSBI_DIR="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi"
FW_PAYLOAD_FDT_ADDR="0x84000000"
FW_BIN="$OPENSBI_DIR/build/platform/generic/firmware/fw_payload.bin"

LEGACY_OUTPUT_DIR="$ROOT_DIR/linux-bringup/payload"
LEGACY_OUTPUT_BIN="$LEGACY_OUTPUT_DIR/fw_payload.bin"

JOBS="${JOBS:-$(nproc)}"

config_is_module() {
  local symbol="$1"
  grep -q "^${symbol}=m$" "$KERNEL_DIR/.config"
}

KERNEL_MODULE_TARGETS=()

if config_is_module CONFIG_CRYPTO_ECC; then
  KERNEL_MODULE_TARGETS+=(crypto/ecc.ko)
fi

if config_is_module CONFIG_CRYPTO_ECDH; then
  KERNEL_MODULE_TARGETS+=(crypto/ecdh_generic.ko)
fi

if config_is_module CONFIG_BT; then
  KERNEL_MODULE_TARGETS+=(net/bluetooth/bluetooth.ko)
fi

echo "[info] Rootfs dir        : $ROOTFS_DIR"
echo "[info] Initramfs cpio   : $INITRAMFS_CPIO"
echo "[info] Kernel dir       : $KERNEL_DIR"
echo "[info] Linux Image      : $LINUX_IMAGE"
echo "[info] Module dir       : $ROOTFS_MODULE_DIR"
echo "[info] CEVA driver dir  : $CEVA_DRIVER_DIR"
echo "[info] OpenSBI dir      : $OPENSBI_DIR"
echo "[info] OpenSBI fw bin   : $FW_BIN"
echo "[info] Jobs             : $JOBS"
echo ""

for tool in cpio gzip make; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Required tool not found: $tool" >&2
    exit 1
  fi
done

for compiler in "${LINUX_CROSS}gcc" "${OPENSBI_CROSS}gcc"; do
  if [[ ! -x "$compiler" ]]; then
    echo "[ERROR] Required compiler not found: $compiler" >&2
    exit 1
  fi
done

if [[ ! -d "$ROOTFS_DIR" ]]; then
  echo "[ERROR] Rootfs directory not found: $ROOTFS_DIR" >&2
  exit 1
fi

if [[ ! -f "$ROOTFS_DIR/init" ]]; then
  echo "[ERROR] Missing init entrypoint: $ROOTFS_DIR/init" >&2
  exit 1
fi

if [[ ! -f "$KERNEL_DIR/.config" ]]; then
  echo "[ERROR] Missing kernel config: $KERNEL_DIR/.config" >&2
  exit 1
fi

if [[ ! -d "$CEVA_DRIVER_DIR" ]]; then
  echo "[ERROR] Missing CEVA driver dir: $CEVA_DRIVER_DIR" >&2
  exit 1
fi

configured_initramfs=$(grep '^CONFIG_INITRAMFS_SOURCE=' "$KERNEL_DIR/.config" | cut -d'=' -f2- | tr -d '"')
if [[ "$configured_initramfs" != "$INITRAMFS_CPIO" ]]; then
  echo "[ERROR] Kernel CONFIG_INITRAMFS_SOURCE mismatch:" >&2
  echo "        expected: $INITRAMFS_CPIO" >&2
  echo "        actual  : $configured_initramfs" >&2
  exit 1
fi

tmp_cpio=$(mktemp "$INITRAMFS_DIR/.initramfs.cpio.tmp.XXXXXX")
tmp_gz=$(mktemp "$INITRAMFS_DIR/.initramfs.cpio.gz.tmp.XXXXXX")
trap 'rm -f "$tmp_cpio" "$tmp_gz"' EXIT

echo "[step 1/4] Rebuilding Phase 2 kernel modules"
make -C "$KERNEL_DIR" \
  ARCH=riscv \
  CROSS_COMPILE="$LINUX_CROSS" \
  -j"$JOBS" \
  modules_prepare

if (( ${#KERNEL_MODULE_TARGETS[@]} > 0 )); then
  make -C "$KERNEL_DIR" \
    ARCH=riscv \
    CROSS_COMPILE="$LINUX_CROSS" \
    -j"$JOBS" \
    "${KERNEL_MODULE_TARGETS[@]}"
else
  echo "[info] No in-tree kernel modules configured as =m for Phase 2 rootfs sync"
fi

echo "[step 1.1/4] Rebuilding external CEVA BT module"
make -C "$CEVA_DRIVER_DIR" clean >/dev/null 2>&1 || true
make -C "$CEVA_DRIVER_DIR" \
  ARCH=riscv \
  CROSS_COMPILE="$LINUX_CROSS" \
  KDIR_RISCV="$KERNEL_DIR"

echo "[step 1.2/4] Syncing modules into initramfs rootfs"
mkdir -p "$ROOTFS_MODULE_DIR"
rm -f "$ROOTFS_MODULE_DIR"/*.ko

copy_module() {
  local src="$1"
  if [[ ! -f "$src" ]]; then
    echo "[ERROR] Required module not found: $src" >&2
    exit 1
  fi
  cp "$src" "$ROOTFS_MODULE_DIR/"
  echo "      copied: $(basename "$src")"
}

if config_is_module CONFIG_CRYPTO_ECC; then
  copy_module "$KERNEL_DIR/crypto/ecc.ko"
else
  echo "      builtin-or-absent: ecc.ko"
fi

if config_is_module CONFIG_CRYPTO_ECDH; then
  copy_module "$KERNEL_DIR/crypto/ecdh_generic.ko"
else
  echo "      builtin-or-absent: ecdh_generic.ko"
fi

if config_is_module CONFIG_BT; then
  copy_module "$KERNEL_DIR/net/bluetooth/bluetooth.ko"
else
  echo "      builtin-or-absent: bluetooth.ko"
fi
copy_module "$CEVA_DRIVER_DIR/ceva_bt52.ko"

echo "[step 1.3/4] Building Phase 2.5 userspace HCI smoke"
if [[ ! -f "$PHASE25_SMOKE_SRC" ]]; then
  echo "[ERROR] Missing userspace smoke source: $PHASE25_SMOKE_SRC" >&2
  exit 1
fi

"${LINUX_CROSS}gcc" \
  -O2 \
  -static \
  -Wall \
  -Wextra \
  -o "$PHASE25_SMOKE_BIN" \
  "$PHASE25_SMOKE_SRC"

chmod 0755 "$PHASE25_SMOKE_BIN"
echo "      built: $(basename "$PHASE25_SMOKE_BIN")"

echo "[step 1.4/4] Building initramfs stage_mark helper"
if [[ ! -f "$STAGE_MARK_SRC" ]]; then
  echo "[ERROR] Missing stage_mark source: $STAGE_MARK_SRC" >&2
  exit 1
fi

"${LINUX_CROSS}gcc" \
  -Os \
  -static \
  -nostdlib \
  -nostartfiles \
  -no-pie \
  -Wl,-e,_start \
  -o "$STAGE_MARK_BIN" \
  "$STAGE_MARK_SRC"

chmod 0755 "$STAGE_MARK_BIN"
echo "      built: $(basename "$STAGE_MARK_BIN")"

echo "[ok] initramfs rootfs module set refreshed"
find "$ROOTFS_MODULE_DIR" -maxdepth 1 -type f -name '*.ko' | sort | sed 's/^/      /'

echo "[step 2/4] Repacking initramfs from rootfs"
(
  cd "$ROOTFS_DIR"
  find . \
    \( -name '*.bak*' -o -name '*~' -o -name '*.swp' -o -name '*.tmp' \) -prune -o \
    -print | LC_ALL=C sort | cpio -o -H newc --quiet > "$tmp_cpio"
)
gzip -n -c "$tmp_cpio" > "$tmp_gz"
mv "$tmp_cpio" "$INITRAMFS_CPIO"
mv "$tmp_gz" "$INITRAMFS_GZ"

echo "[ok] initramfs updated"
echo "      entries: $(cpio -it < "$INITRAMFS_CPIO" 2>/dev/null | wc -l)"
echo "      size   : $(stat -c %s "$INITRAMFS_CPIO") bytes"
echo "      mtime  : $(stat -c %y "$INITRAMFS_CPIO")"

echo "[step 3/4] Rebuilding Linux Image with embedded initramfs"
make -C "$KERNEL_DIR" \
  ARCH=riscv \
  CROSS_COMPILE="$LINUX_CROSS" \
  -j"$JOBS" \
  Image

if [[ ! -f "$LINUX_IMAGE" ]]; then
  echo "[ERROR] Linux Image not generated: $LINUX_IMAGE" >&2
  exit 1
fi

echo "[ok] Linux Image rebuilt"
echo "      size   : $(stat -c %s "$LINUX_IMAGE") bytes"
echo "      mtime  : $(stat -c %y "$LINUX_IMAGE")"

echo "[step 4/4] Rebuilding OpenSBI fw_payload.bin"
make -C "$OPENSBI_DIR" clean >/dev/null 2>&1 || true
CROSS_COMPILE="$OPENSBI_CROSS" \
make -C "$OPENSBI_DIR" \
  PLATFORM=generic \
  CONFIG_SERIAL_SEMIHOSTING=n \
  FW_PAYLOAD=y \
  FW_PAYLOAD_PATH="$LINUX_IMAGE" \
  FW_PAYLOAD_FDT_ADDR="$FW_PAYLOAD_FDT_ADDR" \
  -j"$JOBS"

if [[ ! -f "$FW_BIN" ]]; then
  echo "[ERROR] fw_payload.bin not generated: $FW_BIN" >&2
  exit 1
fi

mkdir -p "$LEGACY_OUTPUT_DIR"
cp "$FW_BIN" "$LEGACY_OUTPUT_BIN"

echo "[ok] OpenSBI payload rebuilt"
echo "      size   : $(stat -c %s "$FW_BIN") bytes"
echo "      mtime  : $(stat -c %y "$FW_BIN")"
echo "      mirror : $LEGACY_OUTPUT_BIN"

echo ""
echo "[done] Rebuild complete"
echo "       1. initramfs.cpio matches $ROOTFS_DIR"
echo "       2. Image embeds the updated initramfs"
echo "       3. fw_payload.bin now wraps the rebuilt Image"
