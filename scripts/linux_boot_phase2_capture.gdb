# linux_boot_phase2_capture.gdb - Phase 2 capture session
# Reconnects after the launch window, halts the kernel, and dumps current-run evidence.

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

python
import os, gdb, time

host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = int(os.environ.get("JLINK_PORT", "3333"))
fw_elf = "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf"
vmlinux = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"

gdb.write(f"[capture] Connecting to J-Link {host}:{port}...\n")
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
gdb.write("[capture] Halted target\n")

if os.path.exists(fw_elf):
    try:
        gdb.execute(f"file {fw_elf}", to_string=True)
        gdb.write(f"[sym] fw_payload symbols loaded from {fw_elf}\n")
    except Exception as e:
        gdb.write(f"[sym] fw_payload load failed: {e}\n")

pc = gdb.parse_and_eval("(unsigned long long)$pc")
gdb.write(f"[state] PC = 0x{int(pc):016X}\n")
try:
    sym = gdb.execute(f"info symbol 0x{int(pc):X}", to_string=True).strip()
    gdb.write(f"[state] symbol = {sym}\n")
except Exception as e:
    gdb.write(f"[state] symbol lookup failed: {e}\n")

try:
    debug_stage = int(gdb.parse_and_eval("(unsigned long long)_debug_stage"))
    debug_value0 = int(gdb.parse_and_eval("(unsigned long long)_debug_value0"))
    debug_value1 = int(gdb.parse_and_eval("(unsigned long long)_debug_value1"))
    debug_value2 = int(gdb.parse_and_eval("(unsigned long long)_debug_value2"))
    debug_value3 = int(gdb.parse_and_eval("(unsigned long long)_debug_value3"))
    gdb.write(f"[opensbi] debug_stage=0x{debug_stage:016X} value0=0x{debug_value0:016X} value1=0x{debug_value1:016X} value2=0x{debug_value2:016X} value3=0x{debug_value3:016X}\n")
except Exception as e:
    gdb.write(f"[opensbi] debug marker read failed: {e}\n")

try:
    pmp_install_rc = int(gdb.parse_and_eval("(unsigned long long)_debug_pmp_install_rc"))
    pmpcfg0_snapshot = int(gdb.parse_and_eval("(unsigned long long)_debug_pmpcfg0_snapshot"))
    pmpaddr0_snapshot = int(gdb.parse_and_eval("(unsigned long long)_debug_pmpaddr0_snapshot"))
    pmpaddr1_snapshot = int(gdb.parse_and_eval("(unsigned long long)_debug_pmpaddr1_snapshot"))
    pmpaddr2_snapshot = int(gdb.parse_and_eval("(unsigned long long)_debug_pmpaddr2_snapshot"))
    gdb.write(f"[opensbi] pmp_install_rc=0x{pmp_install_rc:016X} pmpcfg0_snapshot=0x{pmpcfg0_snapshot:016X} pmpaddr0_snapshot=0x{pmpaddr0_snapshot:016X} pmpaddr1_snapshot=0x{pmpaddr1_snapshot:016X} pmpaddr2_snapshot=0x{pmpaddr2_snapshot:016X}\n")
except Exception as e:
    gdb.write(f"[opensbi] pmp snapshot read failed: {e}\n")

if os.path.exists(vmlinux):
    gdb.write(f"[sym] Loading vmlinux symbols from {vmlinux}...\n")
    try:
        gdb.execute(f"add-symbol-file {vmlinux} 0", to_string=True)
        gdb.write("[sym] vmlinux symbols loaded OK\n")
    except Exception as e:
        gdb.write(f"[sym] add-symbol-file failed: {e}, trying file...\n")
        try:
            gdb.execute(f"file {vmlinux}", to_string=True)
            gdb.write("[sym] vmlinux via file OK\n")
        except Exception as e2:
            gdb.write(f"[sym] vmlinux load failed: {e2}\n")
else:
    gdb.write(f"[sym] vmlinux not found at {vmlinux}\n")
end

echo [phase2] Step 6: Scan klog for CEVA BT5.2 evidence\n

python
import struct

def va_to_pa(va):
    return (int(va) + 0x100200000) & 0xFFFFFFFFFFFFFFFF

def dump_pa(path, pa, size):
    gdb.execute(f"dump binary memory {path} 0x{pa:X} 0x{(pa + size):X}")

def read_pa_u64(pa):
    tmp = f"/tmp/_phase2_rd_{pa:x}_u64.bin"
    try:
        dump_pa(tmp, pa, 8)
        with open(tmp, "rb") as fh:
            return struct.unpack("<Q", fh.read(8))[0]
    except Exception as e:
        gdb.write(f"[pa_read] Failed 0x{pa:X}: {e}\n")
        return None

def read_pa_u32(pa):
    try:
        tmp = f"/tmp/_phase2_rd_{pa:x}_u32.bin"
        dump_pa(tmp, pa, 4)
        with open(tmp, "rb") as fh:
            return struct.unpack("<I", fh.read(4))[0]
    except Exception:
        return None

def nonzero_bytes(path):
    with open(path, "rb") as fh:
        return sum(1 for byte in fh.read() if byte != 0)

try:
    log_buf_sym_va = int(gdb.parse_and_eval("(unsigned long long)&log_buf"))
    log_buf_len_sym_va = int(gdb.parse_and_eval("(unsigned long long)&log_buf_len"))
    static_log_buf_sym_va = int(gdb.parse_and_eval("(unsigned long long)&__log_buf"))
    gdb.write(f"[klog] log_buf symbol VA=0x{log_buf_sym_va:016X}\n")
    gdb.write(f"[klog] log_buf_len symbol VA=0x{log_buf_len_sym_va:016X}\n")
    gdb.write(f"[klog] __log_buf symbol VA=0x{static_log_buf_sym_va:016X}\n")

    log_buf_sym_pa = va_to_pa(log_buf_sym_va)
    log_buf_len_sym_pa = va_to_pa(log_buf_len_sym_va)
    static_log_buf_sym_pa = va_to_pa(static_log_buf_sym_va)
    gdb.write(f"[klog] log_buf symbol PA=0x{log_buf_sym_pa:016X}\n")
    gdb.write(f"[klog] log_buf_len symbol PA=0x{log_buf_len_sym_pa:016X}\n")
    gdb.write(f"[klog] __log_buf symbol PA=0x{static_log_buf_sym_pa:016X}\n")
    log_buf_ptr_va = read_pa_u64(log_buf_sym_pa)
    if log_buf_ptr_va is None:
        raise Exception("Cannot read log_buf pointer from PA")
    gdb.write(f"[klog] log_buf pointer VA=0x{log_buf_ptr_va:016X}\n")

    log_buf_len = read_pa_u32(log_buf_len_sym_pa)
    if log_buf_len is None or log_buf_len == 0 or log_buf_len > 0x40000:
        log_buf_len = 0x20000
    gdb.write(f"[klog] log_buf_len={log_buf_len}\n")

    log_buf_pa = va_to_pa(log_buf_ptr_va)
    gdb.write(f"[klog] log buffer PA=0x{log_buf_pa:016X}\n")
    dump_size = min(131072, log_buf_len)
    dump_pa("/tmp/phase2_klog.bin", log_buf_pa, dump_size)
    gdb.write(f"[klog] Dumped {dump_size} bytes from runtime log_buf to /tmp/phase2_klog.bin\n")

    nz = nonzero_bytes("/tmp/phase2_klog.bin")
    gdb.write(f"[klog] runtime log_buf non-zero bytes={nz}\n")
    if nz == 0:
        gdb.write("[klog] runtime log_buf dump is all zero, retrying __log_buf fallback\n")
        dump_pa("/tmp/phase2_klog.bin", static_log_buf_sym_pa, dump_size)
        nz = nonzero_bytes("/tmp/phase2_klog.bin")
        gdb.write(f"[klog] __log_buf fallback non-zero bytes={nz}\n")
except Exception as e:
    gdb.write(f"[klog] Symbol-based klog read failed: {e}\n")
    try:
        dump_pa("/tmp/phase2_klog.bin", 0x80400000, 0x400000)
        gdb.write("[klog] Fallback dump done: 0x80400000-0x80800000 -> /tmp/phase2_klog.bin\n")
    except Exception as e2:
        gdb.write(f"[klog] Fallback dump also failed: {e2}\n")
end

shell echo "[klog check] Searching for CEVA BT5.2 strings:" && \
  strings /tmp/phase2_klog.bin 2>/dev/null | grep -E "ceva|hci0|bluetooth|CEVA|rw-dm|insmod|init:|BT" | head -30 || \
  echo "[klog check] No CEVA strings found"
shell echo "[klog check] Searching for userspace smoke strings:" && \
    strings /tmp/phase2_klog.bin 2>/dev/null | grep -E "PHASE25_USER_|running Phase 2.5 userspace HCI smoke|hci0 registered OK - CEVA BT5.2 controller READY|waiting for hci0|phase25_user_hci_smoke" | head -120 || \
    echo "[klog check] No userspace smoke strings found"
shell echo "[klog check] Searching for init-flow breadcrumbs:" && \
    strings /tmp/phase2_klog.bin 2>/dev/null | grep -E "PHASE25_INIT_|PHASE25_BEFORE_|PHASE25_AFTER_|PHASE25_HCI_WAIT_|PHASE25_BLUETOOTH_ERR|PHASE25_CEVA_ERR" | head -160 || \
    echo "[klog check] No init-flow breadcrumbs found"
shell echo "[klog check] Searching for panic/error strings:" && \
    strings /tmp/phase2_klog.bin 2>/dev/null | grep -Ei "panic|Oops|BUG:|Unable to handle|Kernel panic|Segmentation fault|not found|Permission denied|No such file|can't execute|PHASE25_INIT_EXIT|PHASE25_BEFORE_SMOKE_EXEC|PHASE25_AFTER_SMOKE_EXEC|PHASE25_USER_SMOKE_TIMEOUT" | head -160 || \
    echo "[klog check] No panic/error strings found"
shell echo "[klog check] Linux boot strings:" && \
  strings /tmp/phase2_klog.bin 2>/dev/null | grep -E "Linux version|Freeing unused|Run /init|rescue-init|Kernel command" | head -10

echo [phase2] Step 6a: Read init stage marker\n

python
import struct

P3BD_TRACE_BASE = 0x8F000040
P3BD_TRACE_SIZE = 0xA0
P3BD_TRACE_SLOTS = [
    (0x8F000040, "P3BD_INIT_START"),
    (0x8F000048, "P3BD_INIT_SELFTEST_OFF"),
    (0x8F000050, "P3BD_INSMOD_START"),
    (0x8F000058, "P3BD_INSMOD_DONE"),
    (0x8F000060, "P3BD_WAIT_HCI0_START"),
    (0x8F000068, "P3BD_WAIT_HCI0_FOUND"),
    (0x8F000070, "P3BD_WAIT_HCI0_TIMEOUT"),
    (0x8F000078, "P3BD_USER_SMOKE_START"),
    (0x8F000080, "P3BD_USER_SMOKE_DONE"),
    (0x8F000088, "P3BD_USER_MAIN_START"),
    (0x8F000090, "P3BD_USER_SOCKET_START"),
    (0x8F000098, "P3BD_USER_SOCKET_OK"),
    (0x8F0000A0, "P3BD_USER_BIND_USER_OK"),
    (0x8F0000A8, "P3BD_USER_BIND_RAW_FALLBACK"),
    (0x8F0000B0, "P3BD_USER_SEND_RESET_START"),
    (0x8F0000B8, "P3BD_USER_SEND_RESET_OK"),
    (0x8F0000C0, "P3BD_USER_SEND_RESET_ERR"),
    (0x8F0000C8, "P3BD_USER_RECV_TIMEOUT"),
    (0x8F0000D0, "P3BD_USER_RECV_MALFORMED"),
    (0x8F0000D8, "P3BD_USER_RECV_VALID_RESET_CC"),
]

try:
    dump_pa("/tmp/phase2_stage_mark.bin", 0x8F000000, 8)
    with open("/tmp/phase2_stage_mark.bin", "rb") as fh:
        stage_mark = struct.unpack("<Q", fh.read(8))[0]
    gdb.write(f"[stage] init_stage_mark=0x{stage_mark:016X}\n")
except Exception as e:
    gdb.write(f"[stage] init_stage_mark read failed: {e}\n")

try:
    dump_pa("/tmp/phase2_p3bd_trace.bin", P3BD_TRACE_BASE, P3BD_TRACE_SIZE)
    with open("/tmp/phase2_p3bd_trace.bin", "rb") as fh:
        trace = fh.read()
    gdb.write("[p3bd] breadcrumb slots:\n")
    for slot_pa, label in P3BD_TRACE_SLOTS:
        offset = slot_pa - P3BD_TRACE_BASE
        value = struct.unpack_from("<Q", trace, offset)[0]
        gdb.write(f"[p3bd] {label}: {'SET' if value else 'MISSING'}")
        if value:
            gdb.write(f" value=0x{value:016X}")
        gdb.write("\n")
except Exception as e:
    gdb.write(f"[p3bd] breadcrumb dump failed: {e}\n")

BOOT_OWNER_MARKER_BASE = int(os.environ.get("CEVA_RUNTIME_BOOT_OWNER_MARKER_ADDR", "0x8FBE0000"), 0)
BOOT_OWNER_MARKER_SIZE = 0x1000
BOOT_OWNER_MAGIC = 0x4F5342494F574E52
BOOT_OWNER_STATE = 0x434C41494D454421
BOOT_OWNER_STAGING = 0x4F50454E53424921
BOOT_OWNER_HANDOFF = 0x4C494E585F434F4E

try:
    dump_pa("/tmp/phase2_boot_owner_marker.bin", BOOT_OWNER_MARKER_BASE, BOOT_OWNER_MARKER_SIZE)
    with open("/tmp/phase2_boot_owner_marker.bin", "rb") as fh:
        marker_blob = fh.read()

    boot_owner_magic = struct.unpack_from("<Q", marker_blob, 0x88)[0]
    boot_owner_state = struct.unpack_from("<Q", marker_blob, 0x90)[0]
    boot_owner_staging = struct.unpack_from("<Q", marker_blob, 0x98)[0]
    reserved_start = struct.unpack_from("<Q", marker_blob, 0xA0)[0]
    reserved_size = struct.unpack_from("<Q", marker_blob, 0xA8)[0]
    linux_handoff = struct.unpack_from("<Q", marker_blob, 0xB0)[0]
    claimed = (boot_owner_magic == BOOT_OWNER_MAGIC and
               boot_owner_state == BOOT_OWNER_STATE and
               boot_owner_staging == BOOT_OWNER_STAGING and
               linux_handoff == BOOT_OWNER_HANDOFF)

    gdb.write(f"[boot-owner] claimed={'yes' if claimed else 'no'}\n")
    gdb.write(f"[boot-owner] magic=0x{boot_owner_magic:016X} state=0x{boot_owner_state:016X} staging=0x{boot_owner_staging:016X}\n")
    gdb.write(f"[boot-owner] reserved_start=0x{reserved_start:016X} reserved_size=0x{reserved_size:016X} linux_handoff=0x{linux_handoff:016X}\n")
except Exception as e:
    gdb.write(f"[boot-owner] marker dump failed: {e}\n")
    try:
        boot_owner_magic = int(gdb.parse_and_eval("(unsigned long long)_debug_boot_owner_magic"))
        boot_owner_state = int(gdb.parse_and_eval("(unsigned long long)_debug_boot_owner_state"))
        boot_owner_staging = int(gdb.parse_and_eval("(unsigned long long)_debug_boot_owner_staging"))
        reserved_start = int(gdb.parse_and_eval("(unsigned long long)_debug_boot_owner_reserved_start"))
        reserved_size = int(gdb.parse_and_eval("(unsigned long long)_debug_boot_owner_reserved_size"))
        linux_handoff = int(gdb.parse_and_eval("(unsigned long long)_debug_boot_owner_linux_handoff"))
        claimed = (boot_owner_magic == BOOT_OWNER_MAGIC and
                   boot_owner_state == BOOT_OWNER_STATE and
                   boot_owner_staging == BOOT_OWNER_STAGING and
                   linux_handoff == BOOT_OWNER_HANDOFF)

        if claimed:
            gdb.write("[boot-owner] source=opensbi-record-fallback\n")
        gdb.write(f"[boot-owner] claimed={'yes' if claimed else 'no'}\n")
        gdb.write(f"[boot-owner] magic=0x{boot_owner_magic:016X} state=0x{boot_owner_state:016X} staging=0x{boot_owner_staging:016X}\n")
        gdb.write(f"[boot-owner] reserved_start=0x{reserved_start:016X} reserved_size=0x{reserved_size:016X} linux_handoff=0x{linux_handoff:016X}\n")
    except Exception as fallback_e:
        gdb.write(f"[boot-owner] opensbi fallback failed: {fallback_e}\n")
end

echo [phase2] Step 6b: Scan Phase 2.5 DDR evidence\n

python
PHASE25_EVID_BASE = 0x8FF00000
PHASE25_EVID_SIZE = 0x100

try:
    dump_pa("/tmp/phase2_phase25_evidence.bin", PHASE25_EVID_BASE, PHASE25_EVID_SIZE)
    gdb.write(f"[phase25] Dumped DDR evidence 0x{PHASE25_EVID_BASE:08X}-0x{PHASE25_EVID_BASE + PHASE25_EVID_SIZE:08X} to /tmp/phase2_phase25_evidence.bin\n")
except Exception as e:
    gdb.write(f"[phase25] DDR evidence dump failed: {e}\n")
end

shell echo "[phase25] DDR evidence strings:" && \
    strings /tmp/phase2_phase25_evidence.bin 2>/dev/null | grep -E "CEVA_PHASE25|HCI_RESET|READ_LOCAL_VERSION" | head -20 || \
    echo "[phase25] No DDR evidence strings found"

echo [phase2] Step 7: Check CEVA hardware registers\n

python
CEVA_BASE = 0x65000000
EM_BASE   = 0x65010000
DM_RWDMCNTL_ADDR = CEVA_BASE + 0x0000
DM_INTCNTL1_ADDR = CEVA_BASE + 0x0018
DM_INTACK1_ADDR = CEVA_BASE + 0x0020
DM_ACTFIFOSTAT_ADDR = CEVA_BASE + 0x0024
DM_ETPTR_ADDR = CEVA_BASE + 0x002C
EM_PHASE25_MARK_MAGIC_ADDR = EM_BASE + 0x1000
EM_PHASE25_MARK_BITS_ADDR = EM_BASE + 0x4000
EM_PHASE25_MARK_AUX_ADDR = EM_BASE + 0xFFFC
EM_PHASE25_MARK_MAGIC = 0x50323521
EM_P3BD_MARK_MAGIC = 0x50334244
EM_CMD_FLAG_WORD = 72
EM_EVT_FLAG_WORD = 73
EM_CMD_READY = 0xA5A5A5A5
EM_EVT_READY = 0x5A5A5A5A

PHASE25_MARK_PROBE_REACHED = 1 << 0
PHASE25_MARK_OPEN_REACHED = 1 << 1
PHASE25_MARK_SELFTEST_START = 1 << 2
PHASE25_MARK_SEND_RESET_SEEN = 1 << 3
PHASE25_MARK_SEND_READ_LOCAL_VERSION = 1 << 4
PHASE25_MARK_HCI_RESET_PASS = 1 << 5
PHASE25_MARK_READ_LOCAL_VERSION_PASS = 1 << 6
PHASE25_MARK_SELFTEST_PASS = 1 << 7
PHASE25_MARK_HCI_RESET_FAIL = 1 << 8
PHASE25_MARK_READ_LOCAL_VERSION_FAIL = 1 << 9
PHASE25_MARK_SELFTEST_FAIL = 1 << 10
P3BD_MARK_DRV_PROBE_START = 1 << 0
P3BD_MARK_DRV_HCI_REGISTER_OK = 1 << 1
P3BD_MARK_DRV_OPEN_START = 1 << 2
P3BD_MARK_DRV_OPEN_OK = 1 << 3
P3BD_MARK_DRV_SEND_ENTER = 1 << 4
P3BD_MARK_DRV_SEND_RESET_SEEN = 1 << 5
P3BD_MARK_DRV_EM_CMD_WRITTEN = 1 << 6
P3BD_MARK_DRV_SWINT_TRIGGERED = 1 << 7
P3BD_MARK_DRV_IRQ_ENTER = 1 << 8
P3BD_MARK_DRV_EM_EVT_READY = 1 << 9
P3BD_MARK_DRV_RX_WORK_ENTER = 1 << 10
P3BD_MARK_DRV_HCI_RECV_DONE = 1 << 11

def r32(addr):
    try:
        v = int(gdb.parse_and_eval(f"*(unsigned int*){addr}"))
        return v
    except:
        return 0xDEADBEEF

def fmt_intstat1(value):
    bit_names = {
        0: "CLKN",
        1: "SLP",
        2: "CRYPT",
        3: "SWINT",
        4: "FINETGT",
        5: "TSTGT1",
        6: "TSTGT2",
        7: "TSTGT3",
    }
    names = [name for bit, name in bit_names.items() if value & (1 << bit)]
    return ",".join(names) if names else "none"

def dump_em_range(start_word, end_word, label):
    gdb.write(f"[hw] {label} words {start_word}..{end_word}:\n")
    for word in range(start_word, end_word + 1):
        value = r32(EM_BASE + word * 4)
        suffix = ""
        if word == EM_CMD_FLAG_WORD:
            if value == EM_CMD_READY:
                suffix = " (cmd-ready SET)"
            elif value == 0:
                suffix = " (cmd-ready CLEAR)"
        elif word == EM_EVT_FLAG_WORD:
            if value == EM_EVT_READY:
                suffix = " (evt-ready SET)"
            elif value == 0:
                suffix = " (evt-ready CLEAR)"
        gdb.write(f"[hw]   EM[{word:03d}] = 0x{value:08X}{suffix}\n")

dm_rwdmcntl = r32(DM_RWDMCNTL_ADDR)
dm_ver  = r32(CEVA_BASE + 0x0004)
dm_stat = r32(CEVA_BASE + 0x000C)
dm_intcntl1 = r32(DM_INTCNTL1_ADDR)
dm_stat1 = r32(CEVA_BASE + 0x001C)
dm_intack1 = r32(DM_INTACK1_ADDR)
dm_actfifostat = r32(DM_ACTFIFOSTAT_ADDR)
dm_etptr = r32(DM_ETPTR_ADDR)
dm_debug_add_max = r32(CEVA_BASE + 0x0058)
dm_debug_add_min = r32(CEVA_BASE + 0x005C)
bt_cntl = r32(CEVA_BASE + 0x0800)
em_w0   = r32(EM_BASE)
em_w64  = r32(EM_BASE + 0x100)
em_cmd_flag = r32(EM_BASE + EM_CMD_FLAG_WORD * 4)
em_evt_flag = r32(EM_BASE + EM_EVT_FLAG_WORD * 4)
em_cmd_shadow_magic = r32(EM_BASE + 0x110)
em_cmd_shadow_bits = r32(EM_BASE + 0x114)
em_cmd_shadow_aux = r32(EM_BASE + 0x118)
em_evt_w0 = r32(EM_BASE + 0x180)
em_evt_w1 = r32(EM_BASE + 0x184)
em_evt_w2 = r32(EM_BASE + 0x188)
em_evt_w3 = r32(EM_BASE + 0x18C)
em_evt_shadow_magic = r32(EM_BASE + 0x190)
em_evt_shadow_bits = r32(EM_BASE + 0x194)
em_evt_shadow_aux = r32(EM_BASE + 0x198)
em_p25_magic = r32(EM_PHASE25_MARK_MAGIC_ADDR)
em_p25_bits = r32(EM_PHASE25_MARK_BITS_ADDR)
em_p25_aux = r32(EM_PHASE25_MARK_AUX_ADDR)

gdb.write(f"\n[hw] DM_VERSION  = 0x{dm_ver:08X}\n")
gdb.write(f"[hw] DM_RWDMCNTL = 0x{dm_rwdmcntl:08X}\n")
gdb.write(f"[hw] DM_INTSTAT0 = 0x{dm_stat:08X}\n")
gdb.write(f"[hw] DM_INTCNTL1 = 0x{dm_intcntl1:08X}\n")
gdb.write(f"[hw] DM_INTSTAT1 = 0x{dm_stat1:08X} (bits={fmt_intstat1(dm_stat1)})\n")
gdb.write(f"[hw] DM_INTACK1  = 0x{dm_intack1:08X}\n")
gdb.write(f"[hw] DM_ACTFIFOSTAT = 0x{dm_actfifostat:08X}\n")
gdb.write(f"[hw] DM_ETPTR    = 0x{dm_etptr:08X}\n")
gdb.write(f"[hw] DEBUGADDMAX = 0x{dm_debug_add_max:08X}\n")
gdb.write(f"[hw] DEBUGADDMIN = 0x{dm_debug_add_min:08X}\n")
gdb.write(f"[hw] BT_RWBTCNTL = 0x{bt_cntl:08X} (bit8=RWBTEN: {'SET' if bt_cntl & 0x100 else 'CLEAR'})\n")
gdb.write(f"[hw] EM[0]       = 0x{em_w0:08X}\n")
gdb.write(f"[hw] EM[64]      = 0x{em_w64:08X} (cmd buf)\n")
gdb.write(f"[hw] EM[72]      = 0x{em_cmd_flag:08X} (cmd-ready flag)\n")
gdb.write(f"[hw] EM[73]      = 0x{em_evt_flag:08X} (evt-ready flag)\n")
gdb.write(f"[hw] EM[68]      = 0x{em_cmd_shadow_magic:08X} (cmd shadow magic)\n")
gdb.write(f"[hw] EM[69]      = 0x{em_cmd_shadow_bits:08X} (cmd shadow bits)\n")
gdb.write(f"[hw] EM[70]      = 0x{em_cmd_shadow_aux:08X} (cmd shadow aux)\n")
gdb.write(f"[hw] EM[96]      = 0x{em_evt_w0:08X} (evt buf[0])\n")
gdb.write(f"[hw] EM[97]      = 0x{em_evt_w1:08X} (evt buf[1])\n")
gdb.write(f"[hw] EM[98]      = 0x{em_evt_w2:08X} (evt buf[2])\n")
gdb.write(f"[hw] EM[99]      = 0x{em_evt_w3:08X} (evt buf[3])\n")
gdb.write(f"[hw] EM[100]     = 0x{em_evt_shadow_magic:08X} (evt shadow magic)\n")
gdb.write(f"[hw] EM[101]     = 0x{em_evt_shadow_bits:08X} (evt shadow bits)\n")
gdb.write(f"[hw] EM[102]     = 0x{em_evt_shadow_aux:08X} (evt shadow aux)\n")
gdb.write(f"[hw] EM[P25 magic@0x1000] = 0x{em_p25_magic:08X}\n")
gdb.write(f"[hw] EM[P25 bits@0x4000]  = 0x{em_p25_bits:08X}\n")
gdb.write(f"[hw] EM[P25 aux@0xFFFC]   = 0x{em_p25_aux:08X}\n")
dump_em_range(64, 72, "EM command window")
dump_em_range(88, 120, "EM event search window")

evt_bytes = b''.join(word.to_bytes(4, 'little') for word in [em_evt_w0, em_evt_w1, em_evt_w2, em_evt_w3])
evt_pkt_ok = len(evt_bytes) >= 7 and evt_bytes[0] == 0x04 and evt_bytes[1] == 0x0E
evt_opcode = (evt_bytes[4] | (evt_bytes[5] << 8)) if evt_pkt_ok else 0
evt_status = evt_bytes[6] if evt_pkt_ok else 0xFF
evt_shadow_present = em_evt_shadow_magic == EM_PHASE25_MARK_MAGIC
cmd_shadow_present = em_cmd_shadow_magic == EM_PHASE25_MARK_MAGIC

try:
    with open("/tmp/phase2_klog.bin", "rb") as fh:
        klog_text = fh.read().decode("latin1", errors="ignore")
except Exception:
    klog_text = ""

try:
    with open("/tmp/phase2_phase25_evidence.bin", "rb") as fh:
        phase25_text = fh.read().decode("latin1", errors="ignore")
except Exception:
    phase25_text = ""

hci0_registered = (
    "registered as hci0" in klog_text or
    "hci0 registered OK" in klog_text
)
phase25_reset_pass = "CEVA_PHASE25_HCI_RESET_PASS" in phase25_text
phase25_version_pass = "CEVA_PHASE25_READ_LOCAL_VERSION_PASS" in phase25_text
phase25_selftest_pass = "CEVA_PHASE25_SELFTEST_PASS" in phase25_text
phase25_markers_present = em_p25_magic == EM_PHASE25_MARK_MAGIC
p3bd_markers_present = em_p25_magic == EM_P3BD_MARK_MAGIC
if evt_shadow_present:
    if em_evt_shadow_bits & PHASE25_MARK_HCI_RESET_PASS:
        phase25_reset_pass = True
    if em_evt_shadow_bits & PHASE25_MARK_READ_LOCAL_VERSION_PASS:
        phase25_version_pass = True
    if em_evt_shadow_bits & PHASE25_MARK_SELFTEST_PASS:
        phase25_selftest_pass = True
if cmd_shadow_present:
    if em_cmd_shadow_bits & PHASE25_MARK_HCI_RESET_PASS:
        phase25_reset_pass = True
    if em_cmd_shadow_bits & PHASE25_MARK_READ_LOCAL_VERSION_PASS:
        phase25_version_pass = True
    if em_cmd_shadow_bits & PHASE25_MARK_SELFTEST_PASS:
        phase25_selftest_pass = True

pass_count = 0
total_checks = 4

gdb.write("\n=== Phase 2 PASS/FAIL Criteria ===\n")

if dm_ver != 0xFFFFFFFF and dm_ver != 0xDEADBEEF:
    gdb.write(f"CHECK 1: DM_VERSION=0x{dm_ver:08X} - PASS (CEVA accessible)\n")
    pass_count += 1
else:
    gdb.write(f"CHECK 1: DM_VERSION=0x{dm_ver:08X} - FAIL (not accessible)\n")

if bt_cntl & 0x100:
    gdb.write("CHECK 2: BT_RWBTCNTL bit8 SET - PASS (driver called open())\n")
    pass_count += 1
else:
    gdb.write("CHECK 2: BT_RWBTCNTL bit8 CLEAR - FAIL/WARN (driver open not called)\n")

if em_w0 != 0xFFFFFFFF and em_w0 != 0xDEADBEEF:
    gdb.write(f"CHECK 3: EM[0]=0x{em_w0:08X} - PASS (EM MMIO accessible)\n")
    pass_count += 1
else:
    gdb.write(f"CHECK 3: EM[0]=0x{em_w0:08X} - SKIP (EM MMIO needs Phase 1A bitstream)\n")
    total_checks -= 1

if hci0_registered:
    gdb.write("CHECK 4: hci0 registration found in klog - PASS\n")
    pass_count += 1
else:
    gdb.write("CHECK 4: hci0 registration missing in klog - FAIL\n")

gdb.write("\n=== Phase 2.5 Evidence ===\n")
if evt_pkt_ok:
    gdb.write(f"CEVA_PHASE25_LAST_EVENT: code=0x{evt_bytes[1]:02X} opcode=0x{evt_opcode:04X} status=0x{evt_status:02X}\n")
else:
    gdb.write("CEVA_PHASE25_LAST_EVENT: MISSING\n")
if cmd_shadow_present:
    gdb.write(f"CEVA_PHASE25_CMD_SHADOW: PRESENT bits=0x{em_cmd_shadow_bits:08X}\n")
else:
    gdb.write("CEVA_PHASE25_CMD_SHADOW: MISSING\n")
if evt_shadow_present:
    gdb.write(f"CEVA_PHASE25_EVT_SHADOW: PRESENT bits=0x{em_evt_shadow_bits:08X}\n")
else:
    gdb.write("CEVA_PHASE25_EVT_SHADOW: MISSING\n")
if phase25_markers_present:
    gdb.write(f"CEVA_PHASE25_MARKERS: PRESENT bits=0x{em_p25_bits:08X}\n")
    gdb.write(f"CEVA_PHASE25_PROBE_REACHED: {'SET' if em_p25_bits & PHASE25_MARK_PROBE_REACHED else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_OPEN_REACHED: {'SET' if em_p25_bits & PHASE25_MARK_OPEN_REACHED else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_SELFTEST_START: {'SET' if em_p25_bits & PHASE25_MARK_SELFTEST_START else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_SEND_RESET_SEEN: {'SET' if em_p25_bits & PHASE25_MARK_SEND_RESET_SEEN else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_SEND_READ_LOCAL_VERSION_SEEN: {'SET' if em_p25_bits & PHASE25_MARK_SEND_READ_LOCAL_VERSION else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_HCI_RESET_PASS: {'PASS' if em_p25_bits & PHASE25_MARK_HCI_RESET_PASS else ('PASS' if phase25_reset_pass else 'MISSING')}\n")
    gdb.write(f"CEVA_PHASE25_READ_LOCAL_VERSION_PASS: {'PASS' if em_p25_bits & PHASE25_MARK_READ_LOCAL_VERSION_PASS else ('PASS' if phase25_version_pass else 'MISSING')}\n")
    gdb.write(f"CEVA_PHASE25_SELFTEST_PASS: {'PASS' if em_p25_bits & PHASE25_MARK_SELFTEST_PASS else ('PASS' if phase25_selftest_pass else 'MISSING')}\n")
    gdb.write(f"CEVA_PHASE25_HCI_RESET_FAIL: {'SET' if em_p25_bits & PHASE25_MARK_HCI_RESET_FAIL else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_READ_LOCAL_VERSION_FAIL: {'SET' if em_p25_bits & PHASE25_MARK_READ_LOCAL_VERSION_FAIL else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_SELFTEST_FAIL: {'SET' if em_p25_bits & PHASE25_MARK_SELFTEST_FAIL else 'MISSING'}\n")
else:
    gdb.write("CEVA_PHASE25_MARKERS: MISSING\n")
    gdb.write(f"CEVA_PHASE25_HCI_RESET_PASS: {'PASS' if phase25_reset_pass else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_READ_LOCAL_VERSION_PASS: {'PASS' if phase25_version_pass else 'MISSING'}\n")
    gdb.write(f"CEVA_PHASE25_SELFTEST_PASS: {'PASS' if phase25_selftest_pass else 'MISSING'}\n")

if p3bd_markers_present:
    gdb.write(f"P3BD_DRV_MARKERS: PRESENT bits=0x{em_p25_bits:08X} aux=0x{em_p25_aux:08X}\n")
    gdb.write(f"P3BD_DRV_PROBE_START: {'SET' if em_p25_bits & P3BD_MARK_DRV_PROBE_START else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_HCI_REGISTER_OK: {'SET' if em_p25_bits & P3BD_MARK_DRV_HCI_REGISTER_OK else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_OPEN_START: {'SET' if em_p25_bits & P3BD_MARK_DRV_OPEN_START else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_OPEN_OK: {'SET' if em_p25_bits & P3BD_MARK_DRV_OPEN_OK else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_SEND_ENTER: {'SET' if em_p25_bits & P3BD_MARK_DRV_SEND_ENTER else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_SEND_RESET_SEEN: {'SET' if em_p25_bits & P3BD_MARK_DRV_SEND_RESET_SEEN else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_EM_CMD_WRITTEN: {'SET' if em_p25_bits & P3BD_MARK_DRV_EM_CMD_WRITTEN else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_SWINT_TRIGGERED: {'SET' if em_p25_bits & P3BD_MARK_DRV_SWINT_TRIGGERED else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_IRQ_ENTER: {'SET' if em_p25_bits & P3BD_MARK_DRV_IRQ_ENTER else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_EM_EVT_READY: {'SET' if em_p25_bits & P3BD_MARK_DRV_EM_EVT_READY else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_RX_WORK_ENTER: {'SET' if em_p25_bits & P3BD_MARK_DRV_RX_WORK_ENTER else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_HCI_RECV_DONE: {'SET' if em_p25_bits & P3BD_MARK_DRV_HCI_RECV_DONE else 'MISSING'}\n")
    gdb.write(f"P3BD_DRV_LAST_OPCODE: 0x{em_p25_aux & 0xFFFF:04X}\n")
else:
    gdb.write("P3BD_DRV_MARKERS: MISSING\n")

gdb.write(f"\n[result] {pass_count}/{total_checks} hardware checks PASS\n")
gdb.write("Phase 2 PASS requires: DM accessible + hci0 in klog\n")
end

detach
quit
