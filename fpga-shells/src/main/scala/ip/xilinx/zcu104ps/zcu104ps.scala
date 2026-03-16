package sifive.fpgashells.ip.xilinx.zcu104ps

import chisel3._
import chisel3.experimental.Analog
import freechips.rocketchip.util.ElaborationArtefacts
import org.chipsalliance.cde.config._

// ZCU104 Zynq UltraScale+ PS (zynq_ultra_ps_e) AXI HP0 slave interface
// RISC-V core → TileLink → AXI4 → S_AXI_HP0_FPD → PS DDR4 (2GB)
// PS must be initialized first (FSBL initializes DDR), then PL design uses this path.

class ZCU104PSIOBundle extends Bundle {
  // AXI HP0 slave interface (64-bit, used for RISC-V memory access)
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
        CONFIG.PSU__USE__M_AXI_GP0 {0} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__USE__M_AXI_GP2 {0} \
        CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
        CONFIG.PSU__SD1__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__SD1__PERIPHERAL__IO {MIO 46 .. 51} \
        CONFIG.PSU__SD1__SLOT_TYPE {SD 2.0} \
        CONFIG.PSU__DDRC__MEMORY_TYPE {DDR 4} \
        CONFIG.PSU__DDRC__BUS_WIDTH {32 Bit} \
        CONFIG.PSU__DDRC__DDR4_ADDR_MAPPING {0} \
        CONFIG.PSU__DDRC__DEVICE_CAPACITY {8192 MBits} \
        CONFIG.PSU__DDRC__DRAM_WIDTH {16 Bits} \
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT {16} \
      ] [get_ips zcu104ps]
      generate_target all [get_ips zcu104ps]
    """
  )
}
