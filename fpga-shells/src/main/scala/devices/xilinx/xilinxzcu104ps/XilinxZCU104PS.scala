package sifive.fpgashells.devices.xilinx.xilinxzcu104ps

import chisel3._
import freechips.rocketchip.amba.axi4._
import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.subsystem._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.prci._
import freechips.rocketchip.tilelink._
import sifive.fpgashells.ip.xilinx.zcu104ps.zcu104ps

case class XilinxZCU104PSParams(
  address: Seq[AddressSet]
)

// Island: contains the zcu104ps black box and AXI node
// No external IO — all signals are internal to the PS block
class XilinxZCU104PSIsland(c: XilinxZCU104PSParams)(implicit p: Parameters)
    extends LazyModule with CrossesToOnlyOneClockDomain {
  val ranges = AddressRange.fromSets(c.address)
  require(ranges.size == 1, "PS DDR range must be contiguous")
  val offset = ranges.head.base
  val depth  = ranges.head.size
  val crossing = AsynchronousCrossing(8)

  val device = new MemoryDevice
  // AXI4 slave node: 128-bit wide (HP0 FPD native width), 6-bit IDs
  val node = AXI4SlaveNode(Seq(AXI4SlavePortParameters(
    slaves = Seq(AXI4SlaveParameters(
      address       = c.address,
      resources     = device.reg,
      regionType    = RegionType.UNCACHED,
      executable    = true,
      supportsWrite = TransferSizes(1, 256 * 16),
      supportsRead  = TransferSizes(1, 256 * 16))),
    beatBytes = 16)))  // 128-bit = 16 bytes

  lazy val module = new Impl
  class Impl extends LazyModuleImp(this) {
    // Export the PS-driven fabric reset line so the harness can release fabric reset.
    val pl_resetn0 = IO(Output(Bool()))
    val blackbox = Module(new zcu104ps)
    val (axi, _) = node.in(0)

    val awaddr = axi.aw.bits.addr - offset.U
    val araddr = axi.ar.bits.addr - offset.U

    // AXI HP0 clock = island clock (set externally via island.module.clock)
    blackbox.io.saxihp0_fpd_aclk := clock
    pl_resetn0                   := blackbox.io.pl_resetn0

    // Write address channel
    blackbox.io.saxigp2_awid    := axi.aw.bits.id
    blackbox.io.saxigp2_awaddr  := awaddr
    blackbox.io.saxigp2_awlen   := axi.aw.bits.len
    blackbox.io.saxigp2_awsize  := axi.aw.bits.size
    blackbox.io.saxigp2_awburst := axi.aw.bits.burst
    blackbox.io.saxigp2_awlock  := axi.aw.bits.lock
    blackbox.io.saxigp2_awcache := "b0011".U
    blackbox.io.saxigp2_awprot  := axi.aw.bits.prot
    blackbox.io.saxigp2_awqos   := axi.aw.bits.qos
    blackbox.io.saxigp2_awvalid := axi.aw.valid
    axi.aw.ready                := blackbox.io.saxigp2_awready

    // Write data channel
    blackbox.io.saxigp2_wdata   := axi.w.bits.data
    blackbox.io.saxigp2_wstrb   := axi.w.bits.strb
    blackbox.io.saxigp2_wlast   := axi.w.bits.last
    blackbox.io.saxigp2_wvalid  := axi.w.valid
    axi.w.ready                 := blackbox.io.saxigp2_wready

    // Write response channel
    blackbox.io.saxigp2_bready  := axi.b.ready
    axi.b.bits.id               := blackbox.io.saxigp2_bid
    axi.b.bits.resp             := blackbox.io.saxigp2_bresp
    axi.b.valid                 := blackbox.io.saxigp2_bvalid

    // Read address channel
    blackbox.io.saxigp2_arid    := axi.ar.bits.id
    blackbox.io.saxigp2_araddr  := araddr
    blackbox.io.saxigp2_arlen   := axi.ar.bits.len
    blackbox.io.saxigp2_arsize  := axi.ar.bits.size
    blackbox.io.saxigp2_arburst := axi.ar.bits.burst
    blackbox.io.saxigp2_arlock  := axi.ar.bits.lock
    blackbox.io.saxigp2_arcache := "b0011".U
    blackbox.io.saxigp2_arprot  := axi.ar.bits.prot
    blackbox.io.saxigp2_arqos   := axi.ar.bits.qos
    blackbox.io.saxigp2_arvalid := axi.ar.valid
    axi.ar.ready                := blackbox.io.saxigp2_arready

    // Read data channel
    blackbox.io.saxigp2_rready  := axi.r.ready
    axi.r.bits.id               := blackbox.io.saxigp2_rid
    axi.r.bits.data             := blackbox.io.saxigp2_rdata
    axi.r.bits.resp             := blackbox.io.saxigp2_rresp
    axi.r.bits.last             := blackbox.io.saxigp2_rlast
    axi.r.valid                 := blackbox.io.saxigp2_rvalid
  }
}

class XilinxZCU104PS(c: XilinxZCU104PSParams)(implicit p: Parameters) extends LazyModule {
  val ranges = AddressRange.fromSets(c.address)
  val depth  = ranges.head.size

  val buffer  = LazyModule(new TLBuffer)
  val toaxi4  = LazyModule(new TLToAXI4(adapterName = Some("mem")))
  val indexer = LazyModule(new AXI4IdIndexer(idBits = 6))
  val deint   = LazyModule(new AXI4Deinterleaver(p(CacheBlockBytes)))
  val yank    = LazyModule(new AXI4UserYanker)
  val island  = LazyModule(new XilinxZCU104PSIsland(c))

  val node: TLInwardNode =
    island.crossAXI4In(island.node) := yank.node := deint.node := indexer.node := toaxi4.node := buffer.node

  lazy val module = new Impl
  class Impl extends LazyModuleImp(this) {
    val pl_resetn0 = IO(Output(Bool()))

    // No external IO beyond the PS-driven reset release line.
    island.module.clock := clock
    island.module.reset := reset
    pl_resetn0          := island.module.pl_resetn0
  }
}
