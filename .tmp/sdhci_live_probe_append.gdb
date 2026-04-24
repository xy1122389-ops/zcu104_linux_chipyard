python
import gdb, os, time, subprocess, struct, re

RUN_TAG = os.environ.get('RUN_TAG', time.strftime('liveprobe_%Y%m%d_%H%M%S'))
BASE = 0x60170000
VMLINUX = '/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux'
NM = '/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm'
SYMBOL_CACHE = None

def load_symbols():
    global SYMBOL_CACHE
    if SYMBOL_CACHE is None:
        text = subprocess.check_output([NM, '-n', VMLINUX], text=True)
        SYMBOL_CACHE = {}
        for line in text.splitlines():
            parts = line.split()
            if len(parts) == 3:
                try:
                    SYMBOL_CACHE[parts[2]] = int(parts[0], 16)
                except ValueError:
                    pass
    return SYMBOL_CACHE

def lookup_symbol(name):
    return load_symbols().get(name)

def kernel_va_to_pa(addr):
    if addr is None:
        return None
    if 0xffffffd800000000 <= addr < 0xffffffd900000000:
        return addr - 0xffffffd800000000 + 0x80000000
    if addr >= 0xffffffff80000000:
        return (addr - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    return addr

def dump_pa(path, pa, size):
    gdb.execute(f'dump binary memory {path} 0x{pa:x} 0x{pa + size:x}', to_string=True)

def read_pa_u32(pa):
    tmp = f'/tmp/_liveprobe_{RUN_TAG}_{pa:x}_u32.bin'
    dump_pa(tmp, pa, 4)
    with open(tmp, 'rb') as f:
        return struct.unpack('<I', f.read(4))[0]

def read_pa_u64(pa):
    tmp = f'/tmp/_liveprobe_{RUN_TAG}_{pa:x}_u64.bin'
    dump_pa(tmp, pa, 8)
    with open(tmp, 'rb') as f:
        return struct.unpack('<Q', f.read(8))[0]

def get_log_buf_info():
    log_buf_len_va = lookup_symbol('log_buf_len')
    log_buf_va_va = lookup_symbol('log_buf')
    if log_buf_len_va is None or log_buf_va_va is None:
        raise gdb.GdbError('log_buf/log_buf_len symbols missing')
    log_buf_len_pa = kernel_va_to_pa(log_buf_len_va)
    log_buf_ptr_pa = kernel_va_to_pa(log_buf_va_va)
    log_len = read_pa_u32(log_buf_len_pa)
    log_buf_ptr = read_pa_u64(log_buf_ptr_pa)
    log_pa = kernel_va_to_pa(log_buf_ptr)
    return log_pa, log_len

def read_monitor_u32(addr):
    out = gdb.execute(f'monitor ReadU32 0x{addr:x}', to_string=True)
    match = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
    if not match:
        raise gdb.GdbError(f'Could not parse ReadU32 output for 0x{addr:x}: {out.strip()}')
    return int(match.group(1), 16)

def ps_snapshot(tag):
    vals = {
        'SDIO_CLK_CTRL': read_monitor_u32(0xFF18030C),
        'CTRL_REG_SD': read_monitor_u32(0xFF180310),
        'SD_CONFIG_REG1': read_monitor_u32(0xFF18031C),
        'SD_CONFIG_REG2': read_monitor_u32(0xFF180320),
        'SDIO1_REF_CTRL': read_monitor_u32(0xFF5E0070),
        'RST_LPD_IOU2': read_monitor_u32(0xFF5E0238),
    }
    gdb.write(f'\n[ps-snap:{tag}]\n')
    for key, value in vals.items():
        gdb.write(f'  {key}=0x{value:08x}\n')

def controller_snapshot(tag):
    def r8(off):
        return int(gdb.parse_and_eval(f'*(unsigned char*)0x{BASE + off:x}'))
    def r16(off):
        return int(gdb.parse_and_eval(f'*(unsigned short*)0x{BASE + off:x}'))
    def r32(off):
        return int(gdb.parse_and_eval(f'*(unsigned int*)0x{BASE + off:x}'))
    vals = {
        'CLOCK_CONTROL': r16(0x2C),
        'POWER_CONTROL': r8(0x29),
        'SOFTWARE_RESET': r8(0x2F),
        'PRESENT_STATE': r32(0x24),
        'HOST_CONTROL': r8(0x28),
        'HOST_CONTROL2': r16(0x3E),
        'INT_STATUS': r32(0x30),
        'INT_ENABLE': r32(0x34),
        'SIGNAL_ENABLE': r32(0x38),
        'CAPABILITIES': r32(0x40),
        'CAPABILITIES_1': r32(0x44),
        'TRANSFER_MODE': r16(0x0C),
        'COMMAND': r16(0x0E),
        'ARGUMENT': r32(0x08),
        'RESPONSE0': r32(0x10),
    }
    pc = int(gdb.parse_and_eval('$pc')) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f'\n[sdhci-snap:{tag}] pc=0x{pc:016x}\n')
    for k, v in vals.items():
        width = 2 if k in ('POWER_CONTROL', 'SOFTWARE_RESET', 'HOST_CONTROL') else 4 if k in ('CLOCK_CONTROL','HOST_CONTROL2','TRANSFER_MODE','COMMAND') else 8
        if width == 2:
            gdb.write(f'  {k}=0x{v:02x}\n')
        elif width == 4:
            gdb.write(f'  {k}=0x{v:04x}\n')
        else:
            gdb.write(f'  {k}=0x{v:08x}\n')

log_pa, log_len = get_log_buf_info()
gdb.write(f'\n[liveprobe] log_pa=0x{log_pa:x} log_len=0x{log_len:x}\n')
post_done = False
for i in range(1, 81):
    gdb.execute('monitor go')
    time.sleep(0.05)
    gdb.execute('monitor halt')
    snap = f'/tmp/klog_{RUN_TAG}_probe{i:02d}.bin'
    dump_pa(snap, log_pa, log_len)
    data = open(snap, 'rb').read().decode('ascii', errors='ignore')
    has_controller = 'SDHCI controller on 60170000.sdhci' in data
    has_cmd52_send = 'sdhci_send_command CMD52' in data
    has_cmd52_timeout = 'cmd_irq_error cmd=52' in data
    pc = int(gdb.parse_and_eval('$pc')) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f'[probe {i:02d}] pc=0x{pc:016x} controller={int(has_controller)} cmd52_send={int(has_cmd52_send)} cmd52_timeout={int(has_cmd52_timeout)}\n')
    if has_cmd52_timeout and not post_done:
        controller_snapshot('post_cmd52_timeout')
        try:
            ps_snapshot('post_cmd52_timeout')
        except Exception as ps_err:
            gdb.write(f'[ps-snap:post_cmd52_timeout] FAILED: {ps_err}\n')
        post_done = True
        break
if not post_done:
    gdb.write('[liveprobe] post_cmd52_timeout snapshot not captured\n')
end
quit
