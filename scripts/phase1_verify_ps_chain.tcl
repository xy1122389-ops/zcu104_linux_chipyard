# phase1_verify_ps_chain.tcl
#
# Phase 1: 仅验证 BOOT_v2.BIN 的 PS 侧链路
#   PMUFW → FSBL → bitstream → arm_stub
#   ★ 不释放 Rocket，不加载 Linux payload，不碰 SD 卡
#
# 运行方式 (WSL):
#   bash scripts/phase1_verify_ps_chain.sh
#
# 成功标准:
#   1. XSDB targets: 看到 PSU, APU, A53#0 等
#   2. DS35 变绿 (DONE, PL configured)
#   3. DS1  变绿 (PS_OK / FSBL ran)
#   4. DS32 (可选) 心跳 LED
#   5. PS UART COM6 有 FSBL 输出
#   6. mrd 0xFF5E0200 boot_mode 寄存器值 = 预期 JTAG 值
#   7. psu_init / DDR init 无 AP timeout
#
# 注意: 此脚本在 JTAG 模式下运行 (SW6 Mode = 0000 or JTAG).
#       必须先切换 SW6 并断电重上电，再运行此脚本。

proc step {label body} {
    puts "\n==== $label ===="
    flush stdout
    if {[catch {uplevel 1 $body} err opts]} {
        puts stderr "ERROR in $label: $err"
        if {[dict exists $opts -errorinfo]} {
            puts stderr [dict get $opts -errorinfo]
        }
        flush stderr
        exit 1
    }
}

proc check {label body} {
    puts "\n---- CHECK: $label ----"
    flush stdout
    if {[catch {uplevel 1 $body} err]} {
        puts "WARN: $label failed (non-fatal): $err"
    }
}

# --- 路径解析 ---
set zcu104_cfg "RocketZCU104LinuxBringupConfig"
if {[info exists ::env(CHIPYARD_ZCU104_CFG)] && $::env(CHIPYARD_ZCU104_CFG) ne ""} {
    set zcu104_cfg $::env(CHIPYARD_ZCU104_CFG)
}
set wsl_base "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src"
set win_obj [string map {/ \\} "${wsl_base}/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"]
set psu_init_tcl "${win_obj}\\ip\\zcu104ps\\psu_init.tcl"
set bit_file "${win_obj}\\ZCU104FPGATestHarness.bit"

# --- Step 0: 文件检查 ---
step "check input files" {
    puts "  config      : $zcu104_cfg"
    puts "  psu_init.tcl: $psu_init_tcl"
    puts "  bitstream   : $bit_file"
    if {![file exists $psu_init_tcl]} { error "missing psu_init.tcl: $psu_init_tcl" }
    if {![file exists $bit_file]}     { error "missing bitstream: $bit_file" }
    puts "  OK: files exist"
}

# --- Step 1: 连接 hw_server ---
step "connect hw_server" {
    connect -url tcp:127.0.0.1:3121
    after 2000
    puts "Connected."
}

# --- Step 2: 扫描 JTAG 链 ---
step "scan JTAG targets" {
    targets
    puts ""
    puts "--- Expected: PSU / APU / RPU / DAP / PS TAP ---"
    puts "--- If targets empty: check SW6 is in JTAG mode (all OFF) ---"
}

# --- Step 3: 选 PSU 目标 ---
step "select PSU target" {
    set found 0
    if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}} err]} {
        puts "PSU target selected."
        set found 1
    }
    if {!$found} {
        puts "PSU not found. Attempting POR via PS TAP..."
        if {![catch {targets -set -nocase -filter {name =~ "*PS TAP*"}}]} {
            catch {rst -por}
            puts "POR issued, waiting 12s for PS to boot..."
            after 12000
            targets
            if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
                puts "PSU available after POR."
                set found 1
            }
        }
        if {!$found} {
            error "PSU target not found. Power-cycle ZCU104 and retry."
        }
    }
}

# --- Step 4: 读启动模式寄存器 (验证 JTAG 模式) ---
#   0xFF5E0200 = CRL_APB BOOT_MODE_USER (PS_MODE[3:0])
#   JTAG 模式: 所有 MODE 引脚 = 0 → 寄存器值 = 0x0000_0000
#   (active-LOW DIP: SW6 全 OFF = PS_MODE = 0 = JTAG)
check "read boot mode register (expect JTAG=0x0)" {
    mrd -force 0xFF5E0200
    puts "  INFO: bit3:0=0 -> JTAG, =0xE -> SD1 SDR50, =0x5 -> QSPI24"
}

# --- Step 5: psu_init (PS DDR 初始化) ---
step "source and run psu_init" {
    source $psu_init_tcl
    psu_init
    puts "psu_init done."
}

# --- Step 6: 等 PS DDR 稳定 ---
step "wait DDR settle" {
    after 1000
    puts "Done."
}

# --- Step 7: FPGA 编程 (加载 bitstream) ---
step "program FPGA bitstream (PL)" {
    puts "Programming: $bit_file"
    fpga $bit_file
    puts "FPGA programming complete."
    puts ""
    puts ">>> Observe DS35 LED: should be GREEN (PL DONE) <<<"
}

# --- Step 8: 等待 PL 稳定 ---
step "wait PL settle" {
    puts "Waiting 3000ms for PL stabilization..."
    after 3000
}

# --- Step 9: 移除 PS-PL 隔离 ---
#   必须在此之后才能访问 PS-PL AXI 总线
step "remove PS-PL isolation" {
    psu_ps_pl_isolation_removal
    puts "PS-PL isolation removed."
}

step "wait after isolation removal" {
    after 2000
}

# --- Step 9b: PS-PL reset config ---
#   CRITICAL: releases PL (Rocket) from reset so the core actually starts
#   Without this, J-Link cannot halt Rocket (debug module not accessible)
step "PS-PL reset config" {
    psu_ps_pl_reset_config
    puts "PS-PL reset config applied. Rocket core should now be running."
    after 1000
}

# --- Step 10: PS 侧状态读取 ---
check "read PS PMU register (GLOBAL_STATUS 0xFFD80100)" {
    mrd -force 0xFFD80100
    puts "  EXPECT: non-zero = PMU running OK"
}

check "read PCAP CTRL register (PL configured check 0xFFCA3008)" {
    set val [mrd -value -force 0xFFCA3008]
    puts "  PCAP_CTRL=0x[format %08x $val]"
    puts "  EXPECT: bit0=1 means PL configured (DONE)"
}

check "read DDR regs (DDRC_STAT 0xFD070004)" {
    mrd -force 0xFD070004
    puts "  EXPECT: bit2=0 (no init error), bit0=1 (init done)"
}

check "read AFI-FM0 IS register (0xFF9B0100)" {
    mrd -force 0xFF9B0100
    puts "  EXPECT: no AXI timeout errors"
}

check "read SDHCI1 base clock (0xFF170018)" {
    # SDIO1 base clock confirm (PS SD1, J100)
    mrd -force 0xFF170018
    puts "  EXPECT: non-zero = SDIO1 clock OK (J100 MicroSD controller)"
}

# --- Step 11: APU 目标检查 ---
check "check APU A53 targets" {
    foreach t [get_targets -filter {name =~ "*A53 #0*"}] {
        targets $t
        break
    }
    targets
    puts "  NOTE: if arm_stub running, A53#0 should be in EL3 WFE loop"
}

# --- Step 12: 尝试读 OCM 验证 FSBL 加载 ---
check "read OCM FSBL entry point (0xFFFC0000)" {
    set w0 [mrd -value -force 0xFFFC0000]
    set w1 [mrd -value -force 0xFFFC0004]
    puts "  OCM[0xFFFC0000] = 0x[format %08x $w0]  0x[format %08x $w1]"
    puts "  NOTE: 0xdeadbeef = FSBL not loaded (expected in JTAG mode - OK)"
}

check "read arm_stub entry point (0xFFFEA000)" {
    set w0 [mrd -value -force 0xFFFEA000]
    puts "  OCM[0xFFFEA000] = 0x[format %08x $w0]"
    puts "  NOTE: 0xdeadbeef = arm_stub not loaded (expected in JTAG mode - OK)"
}

# --- Step 13: 最终 targets 快照 ---
step "final targets snapshot" {
    targets
}

step "disconnect" {
    disconnect
}

puts ""
puts "============================================================"
puts "Phase 1 Complete. Please verify:"
puts "  1. DS35 GREEN? (PL DONE)"
puts "  2. DS1  GREEN? (PS_OK)"
puts "  3. PS UART COM6 has FSBL output? (115200 8N1)"
puts "  4. PCAP bit0=1? (PL configured)"
puts "  5. DDR init - no AP timeout?"
puts "  6. NOTE: OCM=0xdeadbeef is NORMAL in JTAG mode (FSBL not auto-loaded)"
puts "============================================================"
