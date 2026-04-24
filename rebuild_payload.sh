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

KERNEL_DIR="/root/chipyard/software/firemarshal/boards/default/linux-clean"
LINUX_IMAGE="$KERNEL_DIR/arch/riscv/boot/Image"

OPENSBI_DIR="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi"
FW_PAYLOAD_FDT_ADDR="0x84000000"
FW_BIN="$OPENSBI_DIR/build/platform/generic/firmware/fw_payload.bin"

LEGACY_OUTPUT_DIR="$ROOT_DIR/linux-bringup/payload"
LEGACY_OUTPUT_BIN="$LEGACY_OUTPUT_DIR/fw_payload.bin"

JOBS="${JOBS:-$(nproc)}"

echo "[info] Rootfs dir        : $ROOTFS_DIR"
echo "[info] Initramfs cpio   : $INITRAMFS_CPIO"
echo "[info] Kernel dir       : $KERNEL_DIR"
echo "[info] Linux Image      : $LINUX_IMAGE"
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

echo "[step 1/3] Repacking initramfs from rootfs"
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

echo "[step 2/3] Rebuilding Linux Image with embedded initramfs"
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

echo "[step 3/3] Rebuilding OpenSBI fw_payload.bin"
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
