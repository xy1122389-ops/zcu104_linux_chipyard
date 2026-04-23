# v12 Klog Analysis — Linux Boot on ZCU104 Rocket SoC

## Boot Status: SUCCESS (kernel boots to userspace)

| Milestone | Status | Details |
|-----------|--------|---------|
| OpenSBI | OK | SBI v1.0, ID=0x1, hart_count=1 |
| earlycon | OK | sifive0 @ 0x64000000 |
| Memory | OK | 2044596K/2097152K (2GB DDR) |
| Page tables | OK | swapper_pg_dir 70 non-zero L2 entries |
| UART | OK | ttySIF0 @ 0x64000000, irq=3, base_baud=3125000 |
| SPI controller | OK | sifive_spi 64001000, irq=4, cs=1, fifo=8, clk=50MHz |
| mmc_spi probe | OK | spi0.0, no DMA, polling CD |
| SD card detect | FAIL | get_cd=-38 (ENOSYS, polling) |
| CMD0 (go_idle) | FAIL | 8 attempts, ALL timeout (err=-110) |
| CMD8 (if_cond) | FAIL | 1 attempt, timeout |
| CMD55 (app_cmd) | FAIL | 4 attempts, timeout |
| CMD1 (send_op_cond) | FAIL | 1 attempt, timeout |
| /init | OK | rescue-init runs, waits for /dev/mmcblk0p1 |

## Root Cause: SD Card Not Responding

ALL SPI RX data is 0xFF — MISO line stuck high. The card never drives MISO.

    cmd0 tx: ff 40 00 00 00 00 95 ff ff ff ...   (correct CMD0 + CRC=0x95)
    cmd0 rx: ff ff ff ff ff ff ff ff ff ff ...   (1009 bytes, ALL 0xFF)

### RTL Signal Mapping (SDIOOverlay.scala — VERIFIED CORRECT)

The overlay does RTL-level signal crossover to map SiFive SPI controller signals
to the Digilent Pmod MicroSD pinout:

| SPI Controller | RTL remaps to | FPGA Pin | PMOD0 Pin | SD Card Function |
|----------------|---------------|----------|-----------|-----------------|
| spi_clk (SCK) | io.spi_clk | H7 | Pin 4 (IO3) | SCK |
| CS (cs[0]) | io.spi_dat(3) | G8 | Pin 1 (IO0) | CS# |
| DQ0 out (MOSI) | io.spi_cs | H8 | Pin 2 (IO1) | MOSI/DI |
| DQ1 in (MISO) | io.spi_dat(0) | G7 | Pin 3 (IO2) | MISO/DO |
| DQ1 (unused) | io.spi_dat(1) | L10 | PMOD1 (parked) | n/a |
| DQ2 (unused) | io.spi_dat(2) | M10 | PMOD1 (parked) | n/a |

RTL crossover code (SDIOOverlay.scala):
    UIntToAnalog(sd_spi_sck, io.spi_clk, true.B)              // SCK -> H7
    UIntToAnalog(sd_spi_cs, io.spi_dat(3), true.B)             // CS -> G8
    UIntToAnalog(sd_spi_dq_o(0), io.spi_cs, true.B)            // MOSI -> H8
    sd_spi_dq_i(1) := AnalogToUInt(io.spi_dat(0)).asBool       // MISO <- G7

Pin mapping designed for Pmod MicroSD (Pin1=CS, Pin2=MOSI, Pin3=MISO, Pin4=SCK)
plugged directly into PMOD0 top row. MAPPING IS CORRECT.

### Possible Causes (ordered by likelihood)

1. No SD card inserted in the Pmod MicroSD adapter
2. Pmod MicroSD adapter not plugged in or on wrong header
3. Adapter on wrong Pmod header — must be PMOD0 top row (J87, H7/H8/G7/G8)
4. Power not supplied to SD card — Pmod VCC/GND pins
5. SD card incompatible or dead

### SPI Register State (from EXP-AUDIT)

| Register | Value | Meaning |
|----------|-------|---------|
| SCKMODE | 0x3 | Mode 3 (CPOL=1, CPHA=1) |
| SCKDIV | 0x18 | div=25, 50MHz/(2x25)=1MHz (initseq) |
| CSID | 0x0 | Chip select 0 |
| CSDEF | 0x1 | CS active low |
| CSMODE | 0x2 (active) / 0x0 (idle) | HOLD during xfer, AUTO between |
| FMT | 0x00080000 | 8 bits, MSB first, single SPI |
| FCTRL | 0x0 | No flash control |
| DELAY0 | 0x00010001 | cssck=1, sckcs=1 |
| DELAY1 | 0x00000001 | intercs=0, interxfr=1 |

CMD0 speed: 400000 Hz (correct for SD init)

### Init Sequence Analysis

1. initseq sends 1016 bytes with CS low at 1MHz -> wakeup clocks (>74 required)
2. Then 10 bytes readback
3. CS goes high, sets cs_high mode
4. 18 bytes with CS high (CSDEF=0x0 inverted -> CS high) -> 144+ clock warmup
5. CS restored to normal
6. CMD0 sent with CS low at 400KHz -> ALL responses 0xFF

The init sequence is correct per SD SPI spec. Problem is purely that no card responds.

## Kernel Memory Layout (verified)

    page_offset     = 0xffffffd800000000
    virt_addr       = 0xffffffff80000000
    phys_addr       = 0x0000000080200000
    size            = 0x0000000000f2a000 (15.16 MB, 7 megapages)
    va_pa_offset    = 0xffffffd780000000
    va_krnl_pa_off  = 0xfffffffeffe00000

## Log Metadata

- log_buf = 0xffffffff80edc190 (= __log_buf, not reallocated)
- log_buf_len = 0x20000 (128 KB)
- desc_ring_count_bits = 0xc (4096 entries)
- Non-zero klog bytes: 17,151 / 131,072

## Next Steps

1. Verify SD card is physically inserted in the Pmod MicroSD adapter
2. Verify adapter is on correct PMOD header (PMOD0 top row, J87)
3. Try with ILA - probe MOSI/MISO/SCK/CS signals at FPGA pins
4. Verify SD card works in another reader
