#!/usr/bin/env bash
set -euo pipefail

PAYLOAD_ELF=/root/chipyard/fpga/linux-bringup/payload/linux-chain/build/linux_chain.elf
PAYLOAD_BIN=/root/chipyard/fpga/linux-bringup/payload/linux-chain/build/linux_chain.bin
PAYLOAD_NM=/root/chipyard/fpga/linux-bringup/payload/linux-chain/build/linux_chain.nm
PAYLOAD_ADDR=0x80200000
PAYLOAD_SIZE=0x00200000
MANIFEST_ADDR=0x803df000
STACK_BASE=0x803e0000
STACK_TOP=0x80400000
KERNEL_ADDR=0x80400000
KERNEL_SIZE=0x02000000
DTB_ADDR=0x82400000
DTB_SIZE=0x00020000
BLOB_ADDR=0x83000000
BLOB_SIZE=0x04000000
MANIFEST_MAGIC=0x4c43484d4e465431
MANIFEST_VER=0x0000000000000001
FLAG_KERNEL_READY=1
FLAG_DTB_READY=2
FLAG_PAYLOAD_READY=4
FLAG_READY_TO_JUMP=8
FLAG_JUMP_ENABLED=16

KERNEL=""
DTB=""
PAYLOAD_BLOB=""
HOST="$(ip route | awk '/default/ {print $3; exit}')"
PORT=2331
GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
ENTRY=""
ENABLE_JUMP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kernel)
      KERNEL="$2"
      shift 2
      ;;
    --dtb)
      DTB="$2"
      shift 2
      ;;
    --payload)
      PAYLOAD_BLOB="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --entry)
      ENTRY="$2"
      shift 2
      ;;
    --enable-jump)
      ENABLE_JUMP=1
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

check_path() {
  local label="$1"
  local path="$2"
  if [[ -z "$path" ]]; then
    echo "[info] $label: not provided"
    return
  fi
  if [[ ! -f "$path" ]]; then
    echo "Error: $label not found: $path" >&2
    exit 2
  fi
  echo "[info] $label: $path"
}

echo "[info] Linux front-chain address plan"
printf '  payload ELF   : %s size=%s\n' "$PAYLOAD_ADDR" "$PAYLOAD_SIZE"
printf '  stack reserve : %s..%s\n' "$STACK_BASE" "$STACK_TOP"
printf '  kernel        : %s size=%s\n' "$KERNEL_ADDR" "$KERNEL_SIZE"
printf '  dtb           : %s size=%s\n' "$DTB_ADDR" "$DTB_SIZE"
printf '  payload blob  : %s size=%s\n' "$BLOB_ADDR" "$BLOB_SIZE"
echo

check_path "front-chain payload ELF" "$PAYLOAD_ELF"
check_path "front-chain payload BIN" "$PAYLOAD_BIN"
check_path "kernel" "$KERNEL"
check_path "dtb" "$DTB"
check_path "payload blob" "$PAYLOAD_BLOB"

check_size() {
  local label="$1"
  local path="$2"
  local max_size="$3"
  local size
  if [[ -z "$path" ]]; then
    return
  fi
  size=$(stat -c %s "$path")
  if (( size > max_size )); then
    echo "Error: $label too large ($size > $max_size)" >&2
    exit 3
  fi
  echo "[info] $label size: $size bytes"
}

check_size "front-chain payload BIN" "$PAYLOAD_BIN" $((PAYLOAD_SIZE))
check_size "kernel" "$KERNEL" $((KERNEL_SIZE))
check_size "dtb" "$DTB" $((DTB_SIZE))
check_size "payload blob" "$PAYLOAD_BLOB" $((BLOB_SIZE))

echo
echo "[info] Planned load order"
echo "  1. Ensure stable platform is initialized:"
echo "     bash /root/chipyard/fpga/scripts/run_ps_ddr_init.sh"
echo "  2. Load front-chain payload ELF to $PAYLOAD_ADDR"
echo "  3. Load payload blob to $BLOB_ADDR"
echo "  4. Load kernel to $KERNEL_ADDR"
echo "  5. Load dtb to $DTB_ADDR"
echo "  6. Halt at linux_*_marker observation points as needed"
echo "  7. Future step: replace placeholder with real jump to Linux entry"
echo

echo "[info] Address summary"
printf '  manifest      : %s\n' "$MANIFEST_ADDR"
printf '  payload ELF   : %s\n' "$PAYLOAD_ADDR"
printf '  kernel        : %s\n' "$KERNEL_ADDR"
printf '  dtb           : %s\n' "$DTB_ADDR"
printf '  payload blob  : %s\n' "$BLOB_ADDR"
printf '  gdb server    : %s:%s\n' "$HOST" "$PORT"
printf '  jump enabled  : %s\n' "$ENABLE_JUMP"
echo

if [[ ! -x "$GDB" ]]; then
  echo "Error: GDB not found: $GDB" >&2
  exit 4
fi

if [[ -z "$KERNEL" || -z "$DTB" ]]; then
  echo "Error: --kernel and --dtb are required for real load." >&2
  exit 5
fi

TMPDIR_GDB=$(mktemp -d)
trap 'rm -rf "$TMPDIR_GDB"' EXIT
MANIFEST_BIN="$TMPDIR_GDB/linux_chain_manifest.bin"
GDB_CMDS="$TMPDIR_GDB/load_linux_chain.gdb"

PAYLOAD_SIZE_BYTES=0
if [[ -n "$PAYLOAD_BLOB" ]]; then
  PAYLOAD_SIZE_BYTES=$(stat -c %s "$PAYLOAD_BLOB")
fi
KERNEL_SIZE_BYTES=$(stat -c %s "$KERNEL")
DTB_SIZE_BYTES=$(stat -c %s "$DTB")

FLAGS=$((FLAG_KERNEL_READY | FLAG_DTB_READY | FLAG_READY_TO_JUMP))
if [[ -n "$PAYLOAD_BLOB" ]]; then
  FLAGS=$((FLAGS | FLAG_PAYLOAD_READY))
fi
if [[ -z "$ENTRY" ]]; then
  ENTRY="$KERNEL_ADDR"
fi
if (( ENABLE_JUMP )); then
  FLAGS=$((FLAGS | FLAG_JUMP_ENABLED))
fi

python3 - <<PY
import struct

manifest = struct.pack(
    "<10Q",
    int("${MANIFEST_MAGIC}", 16),
    int("${MANIFEST_VER}", 16),
    int("${FLAGS}"),
    int("${KERNEL_ADDR}", 16),
    int("${KERNEL_SIZE_BYTES}"),
    int("${DTB_ADDR}", 16),
    int("${DTB_SIZE_BYTES}"),
    int("${BLOB_ADDR}", 16),
    int("${PAYLOAD_SIZE_BYTES}"),
    int("${ENTRY}", 16),
)
with open("${MANIFEST_BIN}", "wb") as f:
    f.write(manifest)
PY

{
  echo "set pagination off"
  echo "set confirm off"
  echo "file ${PAYLOAD_ELF}"
  echo "target remote ${HOST}:${PORT}"
  echo "monitor halt"
  echo "restore ${PAYLOAD_BIN} binary ${PAYLOAD_ADDR}"
  echo "restore ${KERNEL} binary ${KERNEL_ADDR}"
  echo "restore ${DTB} binary ${DTB_ADDR}"
  if [[ -n "$PAYLOAD_BLOB" ]]; then
    echo "restore ${PAYLOAD_BLOB} binary ${BLOB_ADDR}"
  fi
  echo "restore ${MANIFEST_BIN} binary ${MANIFEST_ADDR}"
  echo "monitor halt"
  echo "x/10gx ${MANIFEST_ADDR}"
  echo "quit"
} > "$GDB_CMDS"

echo "[info] Loading files into target memory..."
"$GDB" -batch -x "$GDB_CMDS"

echo
echo "[info] Loaded front-chain payload BIN to ${PAYLOAD_ADDR}"
echo "[info] Loaded kernel to ${KERNEL_ADDR}"
echo "[info] Loaded dtb to ${DTB_ADDR}"
if [[ -n "$PAYLOAD_BLOB" ]]; then
  echo "[info] Loaded payload blob to ${BLOB_ADDR}"
else
  echo "[info] No payload blob provided"
fi
echo "[info] Loaded manifest to ${MANIFEST_ADDR}"
if (( ENABLE_JUMP )); then
  echo "[info] jump enabled in manifest; front-chain may take jump if all checks pass"
  echo "[info] jump entry address = ${ENTRY}"
else
  echo "[info] jump disabled in manifest; front-chain will report blocked reason and stay observable"
fi
