# Validation Plan — A2 Route (PS SDIO via S_AXI_LPD)

## Pre-boot Smoke Test

### Step 1: Program FPGA
```raw
# Via XSDB or Vivado Hardware Manager
connect
targets -set -filter {name =~ "xczu*"}
fpga -file ZCU104FPGATestHarness.bit
```

### Step 2: Run psu_init
```raw
# XSDB
source psu_init.tcl
psu_init
after 1000
```

### Step 3: GDB Manual Register Read (KEY SMOKE TEST)
```gdb
# Connect to Rocket via J-Link / OpenOCD
target remote :3333

# Read SDHCI version register at 0x60170000 + 0xFE (SDHCI_HOST_VERSION)
# Expected: non-zero, non-0xFFFFFFFF value
# Arasan SDHCI 8.9a should return vendor_version | spec_version
x/1w 0x601700FC

# Read SDHCI capabilities register
x/1w 0x60170040
```

**PASS criteria**: Non-zero, non-0xFFFFFFFF response → S_AXI_LPD path works
**FAIL indicators**:
- All-zero → XPPU blocking access (check psu_init XPPU config)
- 0xFFFFFFFF or bus error → Address decode or AXI wiring issue
- Hang → AXI handshake stuck (check ready/valid signals)

## Boot Test

### Step 4: Load fw_payload.bin + DTB via GDB
```gdb
# Load OpenSBI + Linux payload
restore fw_payload.bin binary 0x80000000
# Load DTB
restore chipyard-zcu104-linux-slip.dtb binary 0x84000000
# Set PC to OpenSBI entry
set $pc = 0x80000000
continue
```

### Step 5: Monitor dmesg (SAME GDB session — do NOT halt repeatedly)
```gdb
# After ~10-20 seconds, halt once
^C
# Dump kernel log
set $log_buf = *(unsigned long *)&log_buf
set $log_buf_len = *(unsigned int *)&log_buf_len
dump binary memory /tmp/klog.bin $log_buf ($log_buf + $log_buf_len)
```

### Step 6: Check sdhci-arasan probe in dmesg
```bash
strings /tmp/klog.bin | grep -i -E 'sdhci|mmc|arasan|sdio'
```

**Expected output** (success):
```raw
sdhci-arasan 60170000.sdhci: Got CD GPIO
mmc0: SDHCI controller on 60170000.sdhci [60170000.sdhci] using ADMA
mmc0: new high speed SDHC card ...
mmcblk0: mmc0:xxxx SDXXX 29.7 GiB
 mmcblk0: p1
```

**Expected output** (partial — no SD card):
```raw
sdhci-arasan 60170000.sdhci: ...
mmc0: SDHCI controller on 60170000.sdhci ...
# No card detect messages — OK if no card inserted
```

**Failure modes**:
- `OF: /soc/sdhci@60170000: no of_get_address translation` → DTS reg wrong
- No sdhci/arasan messages at all → Driver not compiled in or reg mismatch
- `sdhci-arasan: probe failed` → AXI path broken or SDIO1 not enabled in PS

## Known Risks
1. **XPPU**: PS may block PL access to LPD peripherals. If Step 3 fails, need to configure XPPU in psu_init.
2. **Clock**: SDIO1 clock may not be enabled. Check CRL_APB registers (0xFF5E0000 region).
3. **MIO pins**: SDIO1 MIO pins (MIO46-51 for J100) must be configured in PS settings. Current TCL relies on Vivado defaults. May need explicit `PSU__SD1__PERIPHERAL__ENABLE {1}`.
4. **Echo field FIFO**: Our manual echo handling uses depth-8 queues. If Rocket issues >8 outstanding requests, FIFO overflow → AXI deadlock.
