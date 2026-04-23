package sifive.fpgashells.ip.xilinx.zcu104ps

import chisel3._
import chisel3.experimental.Analog
import freechips.rocketchip.util.ElaborationArtefacts
import org.chipsalliance.cde.config._

// ZCU104 Zynq UltraScale+ PS (zynq_ultra_ps_e)
// Two AXI slave ports exposed:
//   S_AXI_HP0_FPD (saxigp2) — 128-bit, DDR path
//   S_AXI_LPD    (saxigp6) — 32-bit,  LPD peripheral path (SDIO, UART, etc.)

// Raw AXI4 slave-side IO bundle for S_AXI_LPD (saxigp6), 32-bit data.
// Signal directions are from the PS (slave) perspective:
//   AW/W/AR channels: Input (slave receives)
//   B/R channels: Output (slave sends)
class ZCU104PSLPDBundle extends Bundle {
  // Write address channel
  val awid     = Input(UInt(6.W))
  val awaddr   = Input(UInt(49.W))
  val awlen    = Input(UInt(8.W))
  val awsize   = Input(UInt(3.W))
  val awburst  = Input(UInt(2.W))
  val awlock   = Input(UInt(1.W))
  val awcache  = Input(UInt(4.W))
  val awprot   = Input(UInt(3.W))
  val awqos    = Input(UInt(4.W))
  val awvalid  = Input(Bool())
  val awready  = Output(Bool())
  // Write data channel
  val wdata    = Input(UInt(32.W))
  val wstrb    = Input(UInt(4.W))
  val wlast    = Input(Bool())
  val wvalid   = Input(Bool())
  val wready   = Output(Bool())
  // Write response channel
  val bid      = Output(UInt(6.W))
  val bresp    = Output(UInt(2.W))
  val bvalid   = Output(Bool())
  val bready   = Input(Bool())
  // Read address channel
  val arid     = Input(UInt(6.W))
  val araddr   = Input(UInt(49.W))
  val arlen    = Input(UInt(8.W))
  val arsize   = Input(UInt(3.W))
  val arburst  = Input(UInt(2.W))
  val arlock   = Input(UInt(1.W))
  val arcache  = Input(UInt(4.W))
  val arprot   = Input(UInt(3.W))
  val arqos    = Input(UInt(4.W))
  val arvalid  = Input(Bool())
  val arready  = Output(Bool())
  // Read data channel
  val rid      = Output(UInt(6.W))
  val rdata    = Output(UInt(32.W))
  val rresp    = Output(UInt(2.W))
  val rlast    = Output(Bool())
  val rvalid   = Output(Bool())
  val rready   = Input(Bool())
}

class ZCU104PSIOBundle extends Bundle {
  // ========== S_AXI_HP0_FPD (saxigp2) — 128-bit, DDR path ==========
  val saxigp2_aruser  = Input(UInt(1.W))
  val saxigp2_awuser  = Input(UInt(1.W))
  // Write address channel
  val saxigp2_awid     = Input(UInt(6.W))
  val saxigp2_awaddr   = Input(UInt(49.W))
  val saxigp2_awlen    = Input(UInt(8.W))
  val saxigp2_awsize   = Input(UInt(3.W))
  val saxigp2_awburst  = Input(UInt(2.W))
  val saxigp2_awlock   = Input(UInt(1.W))
  val saxigp2_awcache  = Input(UInt(4.W))
  val saxigp2_awprot   = Input(UInt(3.W))
  val saxigp2_awqos    = Input(UInt(4.W))
  val saxigp2_awvalid  = Input(Bool())
  val saxigp2_awready  = Output(Bool())
  // Write data channel
  val saxigp2_wdata    = Input(UInt(128.W))
  val saxigp2_wstrb    = Input(UInt(16.W))
  val saxigp2_wlast    = Input(Bool())
  val saxigp2_wvalid   = Input(Bool())
  val saxigp2_wready   = Output(Bool())
  // Write response channel
  val saxigp2_bid      = Output(UInt(6.W))
  val saxigp2_bresp    = Output(UInt(2.W))
  val saxigp2_bvalid   = Output(Bool())
  val saxigp2_bready   = Input(Bool())
  // Read address channel
  val saxigp2_arid     = Input(UInt(6.W))
  val saxigp2_araddr   = Input(UInt(49.W))
  val saxigp2_arlen    = Input(UInt(8.W))
  val saxigp2_arsize   = Input(UInt(3.W))
  val saxigp2_arburst  = Input(UInt(2.W))
  val saxigp2_arlock   = Input(UInt(1.W))
  val saxigp2_arcache  = Input(UInt(4.W))
  val saxigp2_arprot   = Input(UInt(3.W))
  val saxigp2_arqos    = Input(UInt(4.W))
  val saxigp2_arvalid  = Input(Bool())
  val saxigp2_arready  = Output(Bool())
  // Read data channel
  val saxigp2_rid      = Output(UInt(6.W))
  val saxigp2_rdata    = Output(UInt(128.W))
  val saxigp2_rresp    = Output(UInt(2.W))
  val saxigp2_rlast    = Output(Bool())
  val saxigp2_rvalid   = Output(Bool())
  val saxigp2_rready   = Input(Bool())
  // Clock for HP0
  val saxihp0_fpd_aclk = Input(Clock())

  // ========== S_AXI_LPD (saxigp6) — 32-bit, LPD peripheral path ==========
  val saxigp6_aruser  = Input(UInt(1.W))
  val saxigp6_awuser  = Input(UInt(1.W))
  // Write address channel
  val saxigp6_awid     = Input(UInt(6.W))
  val saxigp6_awaddr   = Input(UInt(49.W))
  val saxigp6_awlen    = Input(UInt(8.W))
  val saxigp6_awsize   = Input(UInt(3.W))
  val saxigp6_awburst  = Input(UInt(2.W))
  val saxigp6_awlock   = Input(UInt(1.W))
  val saxigp6_awcache  = Input(UInt(4.W))
  val saxigp6_awprot   = Input(UInt(3.W))
  val saxigp6_awqos    = Input(UInt(4.W))
  val saxigp6_awvalid  = Input(Bool())
  val saxigp6_awready  = Output(Bool())
  // Write data channel
  val saxigp6_wdata    = Input(UInt(32.W))
  val saxigp6_wstrb    = Input(UInt(4.W))
  val saxigp6_wlast    = Input(Bool())
  val saxigp6_wvalid   = Input(Bool())
  val saxigp6_wready   = Output(Bool())
  // Write response channel
  val saxigp6_bid      = Output(UInt(6.W))
  val saxigp6_bresp    = Output(UInt(2.W))
  val saxigp6_bvalid   = Output(Bool())
  val saxigp6_bready   = Input(Bool())
  // Read address channel
  val saxigp6_arid     = Input(UInt(6.W))
  val saxigp6_araddr   = Input(UInt(49.W))
  val saxigp6_arlen    = Input(UInt(8.W))
  val saxigp6_arsize   = Input(UInt(3.W))
  val saxigp6_arburst  = Input(UInt(2.W))
  val saxigp6_arlock   = Input(UInt(1.W))
  val saxigp6_arcache  = Input(UInt(4.W))
  val saxigp6_arprot   = Input(UInt(3.W))
  val saxigp6_arqos    = Input(UInt(4.W))
  val saxigp6_arvalid  = Input(Bool())
  val saxigp6_arready  = Output(Bool())
  // Read data channel
  val saxigp6_rid      = Output(UInt(6.W))
  val saxigp6_rdata    = Output(UInt(32.W))
  val saxigp6_rresp    = Output(UInt(2.W))
  val saxigp6_rlast    = Output(Bool())
  val saxigp6_rvalid   = Output(Bool())
  val saxigp6_rready   = Input(Bool())
  // Clock for LPD
  val saxi_lpd_aclk    = Input(Clock())
}

// Black box wrapping zynq_ultra_ps_e with only AXI HP0 exposed
class zcu104ps(implicit val p: Parameters) extends BlackBox {
  val io = IO(new ZCU104PSIOBundle)

  ElaborationArtefacts.add(
    "zcu104ps.vivado.tcl",
    """
      create_ip -vendor xilinx.com -library ip -name zynq_ultra_ps_e \
        -module_name zcu104ps -dir $ipdir -force
      set_property -dict [list \
        CONFIG.PSU_BANK_0_IO_STANDARD {LVCMOS18} \
        CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
        CONFIG.PSU__FPGA_PL0_ENABLE {1} \
        CONFIG.PSU__USE__S_AXI_GP2 {1} \
        CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
        CONFIG.PSU__USE__S_AXI_GP6 {1} \
        CONFIG.PSU__SAXIGP6__DATA_WIDTH {32} \
        CONFIG.PSU__USE__M_AXI_GP0 {0} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__USE__M_AXI_GP2 {0} \
        CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
        CONFIG.PSU__SD1__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__SD1__PERIPHERAL__IO {MIO 46 .. 51} \
        CONFIG.PSU__SD1__SLOT_TYPE {SD 2.0} \
        CONFIG.PSU__DDRC__MEMORY_TYPE {DDR 4} \
        CONFIG.PSU__DDRC__BUS_WIDTH {64 Bit} \
        CONFIG.PSU__DDRC__DDR4_ADDR_MAPPING {0} \
        CONFIG.PSU__DDRC__DEVICE_CAPACITY {4096 MBits} \
        CONFIG.PSU__DDRC__DRAM_WIDTH {16 Bits} \
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT {15} \
        CONFIG.PSU__DDRC__BG_ADDR_COUNT {1} \
        CONFIG.PSU__DDRC__RANK_ADDR_COUNT {0} \
      ] [get_ips zcu104ps]
      generate_target all [get_ips zcu104ps]
    """
  )
}
