#!/usr/bin/env bash
set -euo pipefail
#
# load_opensbi_linux_payload.sh
# Reliably load OpenSBI FW_PAYLOAD (with embedded Linux Image) + DTB
# into ZCU104 DDR via J-Link Commander, using 64KB chunked loadbin.
#
# Prerequisites:
#   1. run_ps_ddr_init.sh already executed (stable bit loaded, DDR init done)
#   2. WSL can invoke Windows SEGGER tools via powershell.exe
#   3. fw_payload.bin built via build_opensbi_linux_payload.sh
#
# This is the stable load path for Linux bring-up. It stops the J-Link GDB
# server, performs chunked loadbin writes with JLink.exe, then restarts the
# GDB server and verifies the three key addresses.
#

OPENSBI_BUILD=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware
FW_BIN="${OPENSBI_BUILD}/fw_payload.bin"
FW_ELF="${OPENSBI_BUILD}/fw_payload.elf"
DTB=/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb

FIRMWARE_ADDR=0x80000000
DTB_ADDR=0x82400000
LINUX_ENTRY=0x80200000                 # payload_bin inside fw_payload
CHUNK_SIZE=$((64 * 1024))              # 64 KB per chunk

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
HOST="$(ip route | awk '/default/ {print $3; exit}')"
PORT=2331
JLINK_USB_SERIAL="${JLINK_USB_SERIAL:-601012542}"
JLINK_SPEED="${JLINK_SPEED:-1000}"
JLINK_IRLEN="${JLINK_IRLEN:-5}"
JLINK_EXE='C:\Program Files\SEGGER\JLink\JLink.exe'
JLINK_GDB_SERVER='C:\Program Files\SEGGER\JLink\JLinkGDBServerCL.exe'

# ---------- argument parsing ----------
VERIFY_ONLY=0
SKIP_LOAD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    HOST="$2"; shift 2 ;;
    --port)    PORT="$2"; shift 2 ;;
    --verify)  VERIFY_ONLY=1; shift ;;
    --skip-load) SKIP_LOAD=1; shift ;;
    --serial)  JLINK_USB_SERIAL="$2"; shift 2 ;;
    --speed)   JLINK_SPEED="$2"; shift 2 ;;
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

if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "[error] powershell.exe not available from WSL" >&2
  exit 2
fi

if ! command -v wslpath >/dev/null 2>&1; then
  echo "[error] wslpath not available" >&2
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
echo "[info] J-Link serial  : $JLINK_USB_SERIAL"
echo "[info] J-Link speed   : $JLINK_SPEED kHz"

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

# ---------- helpers ----------
check_jlink() {
  if timeout 5 bash -c "echo >/dev/tcp/$HOST/$PORT" 2>/dev/null; then
    return 0
  fi
  return 1
}

restart_jlink_gdb_server() {
  powershell.exe -NoProfile -Command "Stop-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue" >/dev/null 2>&1 || true
  sleep 2
  powershell.exe -NoProfile -Command "Start-Process -FilePath '$JLINK_GDB_SERVER' -ArgumentList '-select','USB=$JLINK_USB_SERIAL','-device','RISC-V','-endian','little','-if','JTAG','-speed','$JLINK_SPEED','-ir','$JLINK_IRLEN','-LocalhostOnly','0','-port','$PORT' -WindowStyle Hidden" >/dev/null 2>&1
  sleep 7
}

# ---------- generate J-Link command file ----------
JLINK_CMDS="$TMPDIR/load_all.jlink"
DTB_WIN=$(wslpath -w "$DTB")

{
  echo "device RISC-V"
  echo "if JTAG"
  echo "speed $JLINK_SPEED"
  echo "JTAGConf 0,0"
  echo "connect"

  if (( !SKIP_LOAD )); then
    for (( i=0; i<NCHUNKS; i++ )); do
      OFFSET=$(( i * CHUNK_SIZE ))
      CADDR=$(printf '0x%x' $(( 0x80000000 + OFFSET )))
      CHUNK_FILE="$TMPDIR/chunk_$(printf '%03d' $i).bin"
      CHUNK_WIN=$(wslpath -w "$CHUNK_FILE")
      echo "loadbin $CHUNK_WIN, $CADDR"
    done
    echo "loadbin $DTB_WIN, $DTB_ADDR"
  fi
  echo "q"
} > "$JLINK_CMDS"

# ---------- perform stable J-Link load ----------
if (( !SKIP_LOAD )); then
  JLINK_CMDS_WIN=$(wslpath -w "$JLINK_CMDS")
  echo ""
  echo "[info] Stopping J-Link GDB server and running J-Link Commander load..."
  powershell.exe -NoProfile -Command "Stop-Process -Name JLinkGDBServerCL,JLink -ErrorAction SilentlyContinue" >/dev/null 2>&1 || true
  sleep 2
  powershell.exe -NoProfile -Command "& '$JLINK_EXE' -CommandFile '$JLINK_CMDS_WIN'"
  echo "[info] J-Link Commander load complete. Restarting GDB server..."
  restart_jlink_gdb_server
elif ! check_jlink; then
  echo "[info] --skip-load requested; starting J-Link GDB server for verification..."
  restart_jlink_gdb_server
fi

# ---------- verify key addresses via GDB ----------
EXPECT_OPENSBI=$(od -A n -t x4 -N 4 "$FW_BIN" | tr -d ' ')
EXPECT_LINUX=$(od -A n -t x4 -N 4 -j $((0x200000)) "$FW_BIN" | tr -d ' ')
EXPECT_DTB=$(od -A n -t x4 -N 4 "$DTB" | tr -d ' ')

VERIFY_GDB="$TMPDIR/verify.gdb"
{
  echo "set pagination off"
  echo "set confirm off"
  echo "set breakpoint auto-hw off"
  echo "target remote $HOST:$PORT"
  echo "monitor halt"
  echo "printf \"[verify] expect OpenSBI 0x$EXPECT_OPENSBI\\n\""
  echo "x/1wx 0x80000000"
  echo "printf \"[verify] expect Linux   0x$EXPECT_LINUX\\n\""
  echo "x/2wx 0x80200000"
  echo "printf \"[verify] expect DTB     0x$EXPECT_DTB\\n\""
  echo "x/1wx 0x82400000"
  echo "quit"
} > "$VERIFY_GDB"

# ---------- execute ----------
echo ""
echo "[info] Starting post-load verification..."
echo "================================================================"
"$GDB" -batch -x "$VERIFY_GDB"
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
  echo "  3. Restore semantic early state:"
  echo "     restoreopensbiearly"
  echo ""
  echo "  4. Verify memory:"
  echo "     pverify"
  echo ""
  echo "  5. Run automated walkthrough:"
  echo "     walk_opensbi_to_linux"
  echo ""
  echo "  6. Or step manually:"
  echo "     bmret         # run to mret"
  echo "     pmret         # dump pre-mret state (CSRs, PMP, regs)"
  echo "     stepi         # step into Linux"
  echo "     pkernel       # show where we landed"
  echo ""
else
  echo "[error] GDB batch exited with code $RET" >&2
  exit 3
fi
