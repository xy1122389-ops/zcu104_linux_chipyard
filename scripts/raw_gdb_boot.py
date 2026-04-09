#!/usr/bin/env python3
"""
Raw GDB Remote Protocol boot loader for RISC-V via J-Link.
Bypasses GDB client entirely - uses direct TCP socket to J-Link GDB Server.
"""
import socket, struct, time, os, sys, hashlib

# Force unbuffered output
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buffering=1)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buffering=1)

HOST = os.environ.get("JLINK_HOST", "172.19.128.1")
PORT = int(os.environ.get("JLINK_PORT", "12331"))

class GDBRemote:
    def __init__(self, host, port, timeout=30):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock = None
        self.noack = False
        self._connect()

    def _connect(self):
        """Connect with retries"""
        for attempt in range(1, 6):
            try:
                if self.sock:
                    try: self.sock.close()
                    except: pass
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.sock.settimeout(self.timeout)
                self.sock.connect((self.host, self.port))
                self.noack = False
                print(f"[conn] Connected on attempt {attempt}")
                return
            except Exception as e:
                print(f"[conn] Attempt {attempt} failed: {e}")
                if attempt < 5:
                    time.sleep(3)
        raise ConnectionError(f"Failed to connect after 5 attempts")

    def reconnect(self):
        """Reconnect after connection loss"""
        print("[conn] Reconnecting...")
        time.sleep(2)
        self._connect()
        self.init_connection()

    def _checksum(self, data):
        return sum(data) & 0xFF

    def send_packet(self, data):
        if isinstance(data, str):
            data = data.encode()
        cs = self._checksum(data)
        pkt = b'$' + data + b'#' + f'{cs:02x}'.encode()
        self.sock.send(pkt)

    def recv_packet(self, timeout=10):
        self.sock.settimeout(timeout)
        buf = b''
        try:
            # Read until we get a complete packet $...#xx
            while True:
                ch = self.sock.recv(1)
                if not ch:
                    raise ConnectionError("Connection closed")
                buf += ch
                if len(buf) >= 4 and buf[-3:][0:1] == b'#' and len(buf) > buf.index(b'$') + 3:
                    break
                if len(buf) > 65536:
                    break
        except socket.timeout:
            if buf:
                return buf.decode('latin-1')
            return None

        # Send ack
        if not self.noack:
            self.sock.send(b'+')

        # Parse: skip leading +/- and $
        start = buf.find(b'$')
        end = buf.rfind(b'#')
        if start >= 0 and end > start:
            payload = buf[start+1:end]
            return payload.decode('latin-1')
        return buf.decode('latin-1')

    def command(self, cmd, timeout=10, retries=2):
        for attempt in range(retries + 1):
            try:
                self.send_packet(cmd)
                return self.recv_packet(timeout)
            except (ConnectionResetError, ConnectionError, BrokenPipeError, OSError) as e:
                print(f"[cmd] Error on '{cmd[:30]}': {e}")
                if attempt < retries:
                    self.reconnect()
                else:
                    raise

    def init_connection(self):
        # Consume initial ack if any
        self.sock.settimeout(1)
        try:
            init = self.sock.recv(16)
            print(f"[init] got: {init}")
        except socket.timeout:
            pass
        self.sock.settimeout(10)

        # qSupported
        resp = self.command("qSupported:multiprocess+;swbreak+;hwbreak+")
        print(f"[init] qSupported: {resp}")

        # Enable NoAckMode if supported
        if resp and 'QStartNoAckMode+' in resp:
            r2 = self.command("QStartNoAckMode")
            if r2 and 'OK' in r2:
                self.noack = True
                # consume the ack for our ack
                try:
                    self.sock.recv(1)
                except:
                    pass
                print("[init] NoAckMode enabled")

    def halt(self):
        resp = self.command("monitor halt", timeout=10)
        # J-Link uses qRcmd for monitor commands
        # Actually need to use the Rcmd packet
        pass

    def monitor_cmd(self, cmd):
        """Send a J-Link monitor command via qRcmd"""
        hex_cmd = cmd.encode().hex()
        resp = self.command(f"qRcmd,{hex_cmd}", timeout=10)
        result = ""
        while resp:
            if resp.startswith('O'):
                # Output hex
                try:
                    result += bytes.fromhex(resp[1:]).decode('ascii', errors='replace')
                except:
                    result += resp
                resp = self.recv_packet(timeout=3)
            elif resp == 'OK':
                break
            else:
                result += resp
                break
        return result.strip()

    def read_registers(self):
        """Read all GPRs (g packet)"""
        resp = self.command("g", timeout=10)
        if resp and not resp.startswith('E'):
            # Parse hex register dump - each reg is 16 hex chars (8 bytes LE) for rv64
            regs = {}
            reg_names = ['zero','ra','sp','gp','tp','t0','t1','t2',
                        's0','s1','a0','a1','a2','a3','a4','a5',
                        'a6','a7','s2','s3','s4','s5','s6','s7',
                        's8','s9','s10','s11','t3','t4','t5','t6','pc']
            for i, name in enumerate(reg_names):
                offset = i * 16
                if offset + 16 <= len(resp):
                    hex_val = resp[offset:offset+16]
                    # Little-endian
                    val = int.from_bytes(bytes.fromhex(hex_val), 'little')
                    regs[name] = val
            return regs
        return None

    def write_register(self, regnum, value):
        """Write a single register (P packet)"""
        # Value in target byte order (little-endian), 8 bytes for rv64
        hex_val = value.to_bytes(8, 'little').hex()
        resp = self.command(f"P{regnum:x}={hex_val}", timeout=5)
        return resp and 'OK' in resp

    def read_memory(self, addr, length):
        """Read memory (m packet)"""
        resp = self.command(f"m{addr:x},{length:x}", timeout=10)
        if resp and not resp.startswith('E'):
            return bytes.fromhex(resp)
        return None

    def write_memory(self, addr, data):
        """Write memory (M packet)"""
        hex_data = data.hex()
        resp = self.command(f"M{addr:x},{len(data):x}:{hex_data}", timeout=30)
        return resp and 'OK' in resp

    def write_memory_binary(self, addr, data):
        """Write memory using X (binary) packet - faster for large writes"""
        # Escape special chars: } = 0x7d, # = 0x23, $ = 0x24, * = 0x2a
        escaped = bytearray()
        for b in data:
            if b in (0x7d, 0x23, 0x24, 0x2a):
                escaped.append(0x7d)
                escaped.append(b ^ 0x20)
            else:
                escaped.append(b)
        header = f"X{addr:x},{len(data):x}:".encode()
        pkt_data = header + bytes(escaped)
        cs = self._checksum(pkt_data)
        pkt = b'$' + pkt_data + b'#' + f'{cs:02x}'.encode()
        self.sock.send(pkt)
        resp = self.recv_packet(timeout=30)
        return resp and 'OK' in resp

    def set_hwbreak(self, addr):
        """Set hardware breakpoint (Z1 packet)"""
        resp = self.command(f"Z1,{addr:x},4", timeout=5)
        return resp and 'OK' in resp

    def remove_hwbreak(self, addr):
        """Remove hardware breakpoint (z1 packet)"""
        resp = self.command(f"z1,{addr:x},4", timeout=5)
        return resp and 'OK' in resp

    def continue_and_wait(self, timeout=600):
        """Continue execution and wait for stop reply"""
        self.send_packet("c")
        resp = self.recv_packet(timeout=timeout)
        return resp

    def step(self):
        """Single step"""
        self.send_packet("s")
        resp = self.recv_packet(timeout=10)
        return resp

    def write_csr(self, csr_num, value):
        """Write CSR via J-Link monitor command"""
        return self.monitor_cmd(f"WriteCSR 0x{csr_num:x} 0x{value:x}")

    def read_csr(self, csr_num):
        """Read CSR via J-Link monitor command"""
        return self.monitor_cmd(f"ReadCSR 0x{csr_num:x}")

    def close(self):
        try:
            self.command("D")  # Detach
        except:
            pass
        self.sock.close()


def write_u32(gdb, addr, val):
    """Write a 32-bit value"""
    data = struct.pack('<I', val)
    return gdb.write_memory(addr, data)


def load_binary(gdb, filepath, base_addr, chunk_size=1024):
    """Load a binary file to memory via GDB remote protocol"""
    with open(filepath, 'rb') as f:
        data = f.read()

    total = len(data)
    written = 0
    t0 = time.time()

    for offset in range(0, total, chunk_size):
        chunk = data[offset:offset+chunk_size]
        addr = base_addr + offset
        if not gdb.write_memory(addr, chunk):
            print(f"[FAIL] write at 0x{addr:x} failed")
            return False
        written += len(chunk)
        if written % (256*1024) == 0 or written == total:
            elapsed = time.time() - t0
            rate = written / elapsed / 1024 if elapsed > 0 else 0
            pct = written * 100 // total
            print(f"[load] {written//1024}KB / {total//1024}KB ({pct}%) @ {rate:.1f} KB/s")

    elapsed = time.time() - t0
    print(f"[load] Complete: {total} bytes in {elapsed:.1f}s ({total/elapsed/1024:.1f} KB/s)")
    return True


def main():
    run_tag = os.environ.get("RUN_TAG", time.strftime("rawboot_%Y%m%d_%H%M%S"))
    run_secs = int(os.environ.get("KERNEL_RUN_SECS", "60"))
    die_catch = os.environ.get("DIE_CATCH", "1") == "1"

    payload_path = "/root/chipyard/fpga/linux-bringup/payload/fw_payload.bin"
    dtb_path = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"

    COPYBACK_ADDR = 0x81200000
    SUB_CHUNK = 256 * 1024

    print(f"[info] Run tag: {run_tag}")
    print(f"[info] Kernel run time: {run_secs}s")
    print(f"[info] DIE_CATCH: {die_catch}")

    # Connect
    gdb = GDBRemote(HOST, PORT, timeout=30)
    gdb.init_connection()

    # Halt
    print("\n=== Halt CPU ===")
    r = gdb.monitor_cmd("halt")
    print(f"[halt] {r}")
    time.sleep(0.5)

    regs = gdb.read_registers()
    if regs:
        print(f"[init] PC = 0x{regs.get('pc', 0):016x}")

    # Disable MMU
    print("[init] Disabling MMU (satp=0)")
    gdb.write_csr(0x180, 0)

    # Set dcsr
    gdb.write_csr(0x7b0, 0x4000F0C3)

    # === Phase 1: Write copyback routine ===
    print("\n=== Phase 1: Load payload with interleaved SBA + L2 copyback ===")

    # Write copyback routine (6 instructions)
    instrs = [
        (COPYBACK_ADDR + 0x00, 0x0000100f),  # fence.i
        (COPYBACK_ADDR + 0x04, 0x00053283),  # ld t0, 0(a0)
        (COPYBACK_ADDR + 0x08, 0x00553023),  # sd t0, 0(a0)
        (COPYBACK_ADDR + 0x0C, 0x04050513),  # addi a0, a0, 64
        (COPYBACK_ADDR + 0x10, 0xFEB54AE3),  # blt a0, a1, -12
        (COPYBACK_ADDR + 0x14, 0x00100073),  # ebreak
    ]
    for addr, val in instrs:
        write_u32(gdb, addr, val)

    # Copyback the routine itself
    print("[cb] Self-copying copyback routine...")
    gdb.write_register(10, COPYBACK_ADDR)      # a0
    gdb.write_register(11, COPYBACK_ADDR + 64)  # a1
    gdb.write_register(32, COPYBACK_ADDR)        # pc
    gdb.set_hwbreak(COPYBACK_ADDR + 0x14)
    resp = gdb.continue_and_wait(timeout=10)
    gdb.remove_hwbreak(COPYBACK_ADDR + 0x14)
    regs = gdb.read_registers()
    if regs:
        print(f"[cb] Done, PC=0x{regs['pc']:x} a0=0x{regs['a0']:x}")

    # Load payload in sub-chunks with interleaved copyback
    with open(payload_path, 'rb') as f:
        payload_data = f.read()

    base_addr = 0x80000000
    total = len(payload_data)
    total_sub = (total + SUB_CHUNK - 1) // SUB_CHUNK
    print(f"[load] Loading {total} bytes ({total//1024}KB) in {total_sub} sub-chunks of {SUB_CHUNK//1024}KB")

    t_global = time.time()
    first_copyback = True

    for sub_idx in range(total_sub):
        offset = sub_idx * SUB_CHUNK
        end = min(offset + SUB_CHUNK, total)
        chunk = payload_data[offset:end]
        mem_addr = base_addr + offset

        # Write via M packet (SBA)
        t0 = time.time()
        # Write in 1KB pieces for reliability
        for piece_off in range(0, len(chunk), 1024):
            piece = chunk[piece_off:piece_off+1024]
            if not gdb.write_memory(mem_addr + piece_off, piece):
                print(f"[FAIL] Write at 0x{mem_addr + piece_off:x}")
                return 1
        dt_write = time.time() - t0

        # Copyback to make dirty
        cb_end = (mem_addr + len(chunk) + 63) & ~63
        entry = COPYBACK_ADDR if first_copyback else COPYBACK_ADDR + 4
        first_copyback = False
        gdb.write_register(10, mem_addr)    # a0
        gdb.write_register(11, cb_end)      # a1
        gdb.write_register(32, entry)        # pc
        gdb.set_hwbreak(COPYBACK_ADDR + 0x14)
        t1 = time.time()
        resp = gdb.continue_and_wait(timeout=30)
        dt_cb = time.time() - t1
        gdb.remove_hwbreak(COPYBACK_ADDR + 0x14)

        if (sub_idx + 1) % 4 == 0 or sub_idx == total_sub - 1:
            elapsed = time.time() - t_global
            print(f"[load+cb] {sub_idx+1}/{total_sub}: 0x{mem_addr:08x}+{len(chunk)//1024}KB  SBA {dt_write:.1f}s  CB {dt_cb:.1f}s  total {elapsed:.0f}s")

    elapsed_total = time.time() - t_global
    print(f"[ok] Payload loaded+dirtied in {elapsed_total:.1f}s")

    # Load DTB
    print(f"\n[dtb] Loading DTB from {dtb_path}")
    with open(dtb_path, 'rb') as f:
        dtb_data = f.read()
    dtb_addr = 0x84000000
    for piece_off in range(0, len(dtb_data), 1024):
        piece = dtb_data[piece_off:piece_off+1024]
        gdb.write_memory(dtb_addr + piece_off, piece)

    # Copyback DTB
    dtb_end = (dtb_addr + len(dtb_data) + 63) & ~63
    gdb.write_register(10, dtb_addr)
    gdb.write_register(11, dtb_end)
    gdb.write_register(32, COPYBACK_ADDR + 4)
    gdb.set_hwbreak(COPYBACK_ADDR + 0x14)
    gdb.continue_and_wait(timeout=10)
    gdb.remove_hwbreak(COPYBACK_ADDR + 0x14)
    print(f"[dtb] Loaded {len(dtb_data)} bytes at 0x{dtb_addr:x}")

    # === Phase 2: Boot OpenSBI -> Linux _start ===
    print("\n=== Phase 2: Boot OpenSBI -> Linux _start ===")
    gdb.write_register(10, 0)           # a0 = hartid
    gdb.write_register(11, 0x84000000)  # a1 = dtb
    gdb.write_register(12, 0)           # a2 = 0
    gdb.write_register(32, 0x80000000)  # pc = OpenSBI entry

    # Set hbreak at mret (0x8000b1ca)
    MRET_ADDR = 0x8000b1ca
    gdb.set_hwbreak(MRET_ADDR)
    print("[boot] Running OpenSBI to mret...")
    resp = gdb.continue_and_wait(timeout=120)
    gdb.remove_hwbreak(MRET_ADDR)

    regs = gdb.read_registers()
    if regs:
        pc = regs['pc']
        print(f"[boot] Stopped at PC=0x{pc:x}")
        if pc != MRET_ADDR:
            print(f"[FAIL] Expected mret at 0x{MRET_ADDR:x}")
            gdb.close()
            return 1
    print("[OK] OpenSBI reached mret")

    # Fix a1 (OpenSBI may have modified it)
    gdb.write_register(11, 0x84000000)

    # Clear ebreakm/ebreaks in dcsr to prevent debug traps
    dcsr_out = gdb.read_csr(0x7b0)
    print(f"[dcsr] {dcsr_out}")

    # Set hbreak at Linux _start (0x80200000)
    gdb.set_hwbreak(0x80200000)
    print("[boot] Continuing from mret to Linux _start...")
    resp = gdb.continue_and_wait(timeout=30)
    gdb.remove_hwbreak(0x80200000)

    regs = gdb.read_registers()
    if regs:
        pc = regs['pc']
        print(f"[boot] Linux _start at PC=0x{pc:x}")

    # === Phase 3: Run kernel ===
    print(f"\n=== Phase 3: Run kernel for {run_secs}s (DIE_CATCH={die_catch}) ===")

    if die_catch:
        # Set hardware trigger on die_kernel_fault PA
        die_kf_pa = 0x8020687c
        die_kf_va = 0xffffffff8000687c
        print(f"[trigger] Setting mcontrol trigger on die_kernel_fault PA=0x{die_kf_pa:x}")

        # Clear triggers
        for i in range(2):
            gdb.write_csr(0x7a0, i)  # tselect
            gdb.write_csr(0x7a1, 0)  # tdata1
            gdb.write_csr(0x7a2, 0)  # tdata2

        # Set mcontrol: type=2, dmode=1, s=1, m=1, execute=1, action=1(debug)
        tdata1 = 0x2800000000001054
        gdb.write_csr(0x7a0, 0)           # tselect = 0
        gdb.write_csr(0x7a2, die_kf_pa)   # tdata2 = PA
        gdb.write_csr(0x7a1, tdata1)       # tdata1 = mcontrol

        # Verify
        td1 = gdb.read_csr(0x7a1)
        td2 = gdb.read_csr(0x7a2)
        print(f"[trigger] tdata1={td1}, tdata2={td2}")

    # Use monitor go instead of continue to avoid GDB state issues
    print(f"[run] Starting kernel via monitor go...")
    gdb.monitor_cmd("go")
    print(f"[run] Kernel is running, waiting {run_secs}s...")
    time.sleep(run_secs)

    print(f"[run] {run_secs}s elapsed, halting...")
    r = gdb.monitor_cmd("halt")
    print(f"[halt] {r}")
    time.sleep(2)

    # Read state
    regs = gdb.read_registers()
    if regs:
        pc = regs['pc']
        print(f"\n[stop] PC = 0x{pc:016x}")
        for name in ['ra','sp','gp','tp','t0','t1','t2','s0','s1',
                      'a0','a1','a2','a3','a4','a5','a6','a7',
                      's2','s3','s4','s5','s6','s7','s8','s9','s10','s11']:
            print(f"  {name:4s} = 0x{regs[name]:016x}")

    # Read CSRs
    print("\n[csrs]")
    for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143),
                      ("satp", 0x180), ("sstatus", 0x100),
                      ("mepc", 0x341), ("mcause", 0x342), ("mtval", 0x343),
                      ("mstatus", 0x300), ("medeleg", 0x302)]:
        val = gdb.read_csr(num)
        print(f"  {name:10s} = {val}")

    # Dump klog region
    print("\n[klog] Dumping kernel log buffer...")
    klog_file = f"/tmp/{run_tag}_klog.bin"
    # __log_buf PA = 0x80ed0060, dump 128KB around it
    klog_start = 0x80ED0000
    klog_end = 0x80F10000
    klog_data = bytearray()
    for addr in range(klog_start, klog_end, 4096):
        chunk = gdb.read_memory(addr, min(4096, klog_end - addr))
        if chunk:
            klog_data.extend(chunk)
        else:
            print(f"[klog] Read failed at 0x{addr:x}")
            break

    with open(klog_file, 'wb') as f:
        f.write(klog_data)
    print(f"[klog] Saved {len(klog_data)} bytes to {klog_file}")

    # Try to extract readable text from klog
    # printk records have level prefixes like \x01\x06 (SOH + level)
    text = klog_data.decode('ascii', errors='replace')
    # Find kernel boot messages
    lines = []
    for segment in text.split('\x00'):
        segment = segment.strip()
        if len(segment) > 10:
            # Clean control chars
            clean = ''.join(c if 32 <= ord(c) < 127 else ' ' for c in segment)
            clean = clean.strip()
            if clean and len(clean) > 5:
                lines.append(clean)

    if lines:
        print(f"\n[klog] Extracted {len(lines)} text segments:")
        for line in lines[:100]:
            print(f"  {line}")
    else:
        print("[klog] No readable text found in log buffer")

    # Check if at die_kernel_fault
    if regs and die_catch:
        pc = regs['pc']
        if pc == die_kf_va or pc == die_kf_pa:
            print("\n*** HIT die_kernel_fault! ***")
            print(f"  msg ptr (a0) = 0x{regs['a0']:x}")
            print(f"  fault addr (a1) = 0x{regs['a1']:x}")
            print(f"  pt_regs (a2) = 0x{regs['a2']:x}")

    # Read memory at crash point for diagnostics
    if regs:
        pc = regs['pc']
        print(f"\n[disasm] Memory at PC=0x{pc:x}:")
        mem = gdb.read_memory(pc & 0xFFFFFFFF if pc > 0xFFFFFFFF00000000 else pc, 32)
        if mem:
            for i in range(0, len(mem), 4):
                insn = struct.unpack_from('<I', mem, i)[0]
                print(f"  0x{(pc + i) & 0xFFFFFFFFFFFFFFFF:016x}: 0x{insn:08x}")

    # Save summary
    summary_file = f"/tmp/{run_tag}_summary.txt"
    with open(summary_file, 'w') as f:
        if regs:
            for name, val in regs.items():
                f.write(f"{name}=0x{val:016x}\n")
    print(f"\n[files] Summary: {summary_file}")
    print(f"[files] Klog: {klog_file}")

    gdb.close()
    print("\n[done] Boot complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
