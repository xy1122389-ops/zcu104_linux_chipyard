#!/usr/bin/env bash
set -euo pipefail
#
# load_opensbi_linux_payload.sh
# Reliably load OpenSBI FW_PAYLOAD (with embedded Linux Image) + DTB
# into ZCU104 DDR via J-Link GDB, using chunked restore for stability.
#
# Prerequisites:
#   1. run_ps_ddr_init.sh already executed (stable bit loaded, DDR init done)
#   2. J-Link GDB server running on Windows host
#   3. fw_payload.bin built via build_opensbi_linux_payload.sh
#
# This script does NOT modify the stable baremetal default flow.
# It halts the CPU, loads firmware+DTB into DDR, then restarts at OpenSBI _start.
#

OPENSBI_BUILD=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware
FW_BIN="${OPENSBI_BUILD}/fw_payload.bin"
FW_ELF="${OPENSBI_BUILD}/fw_payload.elf"
DTB=/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb

FIRMWARE_ADDR=0x80000000
DTB_ADDR=0x82400000
LINUX_ENTRY=0x80200000                 # payload_bin inside fw_payload
CHUNK_SIZE=$((1 * 1024 * 1024))        # 1 MB per chunk

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
HOST="$(ip route | awk '/default/ {print $3; exit}')"
PORT=2331

# ---------- argument parsing ----------
VERIFY_ONLY=0
SKIP_LOAD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    HOST="$2"; shift 2 ;;
    --port)    PORT="$2"; shift 2 ;;
    --verify)  VERIFY_ONLY=1; shift ;;
    --skip-load) SKIP_LOAD=1; shift ;;
    *) echo "Usage: $0 [--host H] [--port P] [--verify] [--skip-load]" >&2; exit 1 ;;
  esac
done

# ---------- pre-flight checks ----------
for f in "$FW_BIN" "$FW_ELF" "$DTB"; do
  if [[ ! -f "$f" ]]; then
    echo "[error] File not found: $f" >&2
    echo "  Run: bash /root/chipyard/fpga/linux-bringup/scripts/build_opensbi_linux_payload.sh" >&2
    exit 2
  fi
done

if [[ ! -x "$GDB" ]]; then
  echo "[error] GDB not found: $GDB" >&2
  exit 2
fi

FW_SIZE=$(stat -c %s "$FW_BIN")
DTB_SIZE=$(stat -c %s "$DTB")
echo "[info] fw_payload.bin : $FW_BIN ($FW_SIZE bytes)"
echo "[info] DTB            : $DTB ($DTB_SIZE bytes)"
echo "[info] Firmware addr  : $FIRMWARE_ADDR"
echo "[info] DTB addr       : $DTB_ADDR"
echo "[info] Linux entry    : $LINUX_ENTRY (embedded in payload)"
echo "[info] GDB target     : $HOST:$PORT"
echo "[info] Chunk size     : $CHUNK_SIZE bytes"

# ---------- split fw_payload.bin into chunks ----------
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

NCHUNKS=$(( (FW_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
echo "[info] Splitting fw_payload.bin into $NCHUNKS chunks..."

for (( i=0; i<NCHUNKS; i++ )); do
  OFFSET=$(( i * CHUNK_SIZE ))
  dd if="$FW_BIN" of="$TMPDIR/chunk_$(printf '%03d' $i).bin" \
     bs="$CHUNK_SIZE" skip="$i" count=1 2>/dev/null
  CSIZE=$(stat -c %s "$TMPDIR/chunk_$(printf '%03d' $i).bin")
  CADDR=$(printf '0x%x' $(( 0x80000000 + OFFSET )))
  echo "  chunk $i: offset=$OFFSET size=$CSIZE addr=$CADDR"
done

# ---------- generate GDB command file ----------
GDB_CMDS="$TMPDIR/load_all.gdb"

{
  echo "set pagination off"
  echo "set confirm off"
  echo "set remotetimeout 60"
  echo "set breakpoint auto-hw off"
  echo "file $FW_ELF"
  echo "target remote $HOST:$PORT"
  echo "monitor reset"
  echo "shell sleep 1"
  echo "monitor halt"
  echo ""
  echo "# Zero breadcrumbs"
  echo "set {long long}0x800200d8 = 0"
  echo "set {long long}0x800200e0 = 0"
  echo "set {long long}0x800200e8 = 0"
  echo "set {long long}0x800200f0 = 0"
  echo "set {long long}0x800200f8 = 0"
  echo "set {long long}0x80020100 = 0"
  echo "set {long long}0x80020108 = 0"
  echo "set {long long}0x80020110 = 0"
  echo ""

  if (( !SKIP_LOAD )); then
    echo "# Load fw_payload.bin in $NCHUNKS chunks"
    for (( i=0; i<NCHUNKS; i++ )); do
      OFFSET=$(( i * CHUNK_SIZE ))
      CADDR=$(printf '0x%x' $(( 0x80000000 + OFFSET )))
      CHUNK_FILE="$TMPDIR/chunk_$(printf '%03d' $i).bin"
      echo "printf \"[load] chunk $i -> $CADDR\\n\""
      echo "restore $CHUNK_FILE binary $CADDR"
    done
    echo ""
    echo "# Load DTB"
    echo "printf \"[load] DTB -> $DTB_ADDR\\n\""
    echo "restore $DTB binary $DTB_ADDR"
    echo ""
  fi

  echo "# Verify OpenSBI _start"
  echo "printf \"[verify] OpenSBI @ 0x80000000: \""
  echo "x/1wx 0x80000000"
  echo ""
  echo "# Verify Linux Image header"
  echo "printf \"[verify] Linux Image @ 0x80200000: \""
  echo "x/2wx 0x80200000"
  echo ""
  echo "# Verify DTB magic"
  echo "printf \"[verify] DTB @ 0x82400000: \""
  echo "x/1wx 0x82400000"
  echo ""
  echo "# Set entry state: a0=hartid=0, a1=dtb, pc=OpenSBI _start"
  echo "set \$a0 = 0"
  echo "set \$a1 = 0x82400000"
  echo "set \$a2 = 0"
  echo "set \$pc = 0x80000000"
  echo ""
  echo "printf \"[done] Ready. pc=0x80000000 a0=0 a1=0x82400000\\n\""
  echo "printf \"[done] Now connect interactively and source opensbi_linux_observe.gdb\\n\""
  echo "printf \"[done] Or use walk_opensbi_to_linux for automated walkthrough\\n\""

  if (( VERIFY_ONLY )); then
    echo "detach"
  else
    echo "detach"
  fi
  echo "quit"
} > "$GDB_CMDS"

# ---------- execute ----------
echo ""
echo "[info] Starting GDB batch load..."
echo "================================================================"
"$GDB" -batch -x "$GDB_CMDS"
RET=$?
echo "================================================================"

if (( RET == 0 )); then
  echo ""
  echo "[success] Load complete."
  echo ""
  echo "Next steps:"
  echo "  1. Start interactive GDB:"
  echo "     /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb \\"
  echo "       /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf"
  echo ""
  echo "  2. In GDB, connect and load observe script:"
  echo "     source /root/chipyard/fpga/linux-bringup/scripts/opensbi_linux_observe.gdb"
  echo ""
  echo "  3. Verify memory:"
  echo "     pverify"
  echo ""
  echo "  4. Run automated walkthrough:"
  echo "     walk_opensbi_to_linux"
  echo ""
  echo "  5. Or step manually:"
  echo "     bmret         # run to mret"
  echo "     pmret         # dump pre-mret state (CSRs, PMP, regs)"
  echo "     stepi         # step into Linux"
  echo "     pkernel       # show where we landed"
  echo ""
else
  echo "[error] GDB batch exited with code $RET" >&2
  exit 3
fi
