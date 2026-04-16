package sifive.fpgashells.devices.xilinx.xilinxzcu104ps

import chisel3._
import chisel3.util._
import freechips.rocketchip.amba.axi4._
import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.subsystem._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.prci._
import freechips.rocketchip.tilelink._
import sifive.fpgashells.ip.xilinx.zcu104ps.{zcu104ps, ZCU104PSLPDBundle}

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
    // No external IO — PS black box has no PL-visible pins
    val blackbox = Module(new zcu104ps)
    val (axi, _) = node.in(0)

    val awaddr = axi.aw.bits.addr - offset.U
    val araddr = axi.ar.bits.addr - offset.U

    // AXI HP0 clock = island clock (set externally via island.module.clock)
    blackbox.io.saxihp0_fpd_aclk := clock

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

    // ========== S_AXI_LPD (saxigp6) — exposed as raw IO for external connection ==========
    // Directions: slave perspective (matching PS blackbox)
    val lpd = IO(new ZCU104PSLPDBundle)

    // LPD clock = island clock (same as HP0)
    blackbox.io.saxi_lpd_aclk  := clock

    // LPD Write address channel
    blackbox.io.saxigp6_awid    := lpd.awid
    blackbox.io.saxigp6_awaddr  := lpd.awaddr
    blackbox.io.saxigp6_awlen   := lpd.awlen
    blackbox.io.saxigp6_awsize  := lpd.awsize
    blackbox.io.saxigp6_awburst := lpd.awburst
    blackbox.io.saxigp6_awlock  := lpd.awlock
    blackbox.io.saxigp6_awcache := lpd.awcache
    blackbox.io.saxigp6_awprot  := lpd.awprot
    blackbox.io.saxigp6_awqos   := lpd.awqos
    blackbox.io.saxigp6_awvalid := lpd.awvalid
    lpd.awready                 := blackbox.io.saxigp6_awready

    // LPD Write data channel
    blackbox.io.saxigp6_wdata   := lpd.wdata
    blackbox.io.saxigp6_wstrb   := lpd.wstrb
    blackbox.io.saxigp6_wlast   := lpd.wlast
    blackbox.io.saxigp6_wvalid  := lpd.wvalid
    lpd.wready                  := blackbox.io.saxigp6_wready

    // LPD Write response channel
    blackbox.io.saxigp6_bready  := lpd.bready
    lpd.bid                     := blackbox.io.saxigp6_bid
    lpd.bresp                   := blackbox.io.saxigp6_bresp
    lpd.bvalid                  := blackbox.io.saxigp6_bvalid

    // LPD Read address channel
    blackbox.io.saxigp6_arid    := lpd.arid
    blackbox.io.saxigp6_araddr  := lpd.araddr
    blackbox.io.saxigp6_arlen   := lpd.arlen
    blackbox.io.saxigp6_arsize  := lpd.arsize
    blackbox.io.saxigp6_arburst := lpd.arburst
    blackbox.io.saxigp6_arlock  := lpd.arlock
    blackbox.io.saxigp6_arcache := lpd.arcache
    blackbox.io.saxigp6_arprot  := lpd.arprot
    blackbox.io.saxigp6_arqos   := lpd.arqos
    blackbox.io.saxigp6_arvalid := lpd.arvalid
    lpd.arready                 := blackbox.io.saxigp6_arready

    // LPD Read data channel
    blackbox.io.saxigp6_rready  := lpd.rready
    lpd.rid                     := blackbox.io.saxigp6_rid
    lpd.rdata                   := blackbox.io.saxigp6_rdata
    lpd.rresp                   := blackbox.io.saxigp6_rresp
    lpd.rlast                   := blackbox.io.saxigp6_rlast
    lpd.rvalid                  := blackbox.io.saxigp6_rvalid
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
    island.module.clock := clock
    island.module.reset := reset

    // Forward LPD IO from island for external connection
    val lpd = IO(new ZCU104PSLPDBundle)
    lpd <> island.module.lpd
  }
}

// AXI4-to-PS-LPD bridge: accepts AXI4 from chip MMIO port,
// translates addresses, echoes diplomatic metadata, drives raw PS signals.
// Instantiated in the HarnessBinder, following the SimAXIMem pattern.
class ZCU104PSLPD(edge: AXI4EdgeParameters, addressOffset: BigInt)(implicit p: Parameters) extends LazyModule {
  val node = AXI4SlaveNode(Seq(edge.slave))
  val io_axi4 = InModuleBody { node.makeIOs() }

  lazy val module = new Impl
  class Impl extends LazyModuleImp(this) {
    val (axi, _) = node.in(0)

    // Raw output IO connecting to PS blackbox saxigp6 (Flipped: master perspective)
    val lpd = IO(Flipped(new ZCU104PSLPDBundle))

    // Address translation: Rocket 0x60xxxxxx → PS 0xFFxxxxxx
    // offset = 0x9F000000 so that 0x60000000 + 0x9F000000 = 0xFF000000
    val awaddr_translated = axi.aw.bits.addr + addressOffset.U
    val araddr_translated = axi.ar.bits.addr + addressOffset.U

    // ----- AW channel -----
    lpd.awid    := axi.aw.bits.id
    lpd.awaddr  := awaddr_translated
    lpd.awlen   := axi.aw.bits.len
    lpd.awsize  := axi.aw.bits.size
    lpd.awburst := axi.aw.bits.burst
    lpd.awlock  := axi.aw.bits.lock
    lpd.awcache := "b0010".U  // DEVICE_NON_BUFFERABLE for MMIO registers
    lpd.awprot  := axi.aw.bits.prot
    lpd.awqos   := axi.aw.bits.qos
    lpd.awvalid := axi.aw.valid
    axi.aw.ready := lpd.awready

    // ----- W channel -----
    lpd.wdata  := axi.w.bits.data
    lpd.wstrb  := axi.w.bits.strb
    lpd.wlast  := axi.w.bits.last
    lpd.wvalid := axi.w.valid
    axi.w.ready := lpd.wready

    // ----- B channel -----
    axi.b.bits.id   := lpd.bid
    axi.b.bits.resp := lpd.bresp
    axi.b.valid     := lpd.bvalid
    lpd.bready      := axi.b.ready

    // ----- AR channel -----
    lpd.arid    := axi.ar.bits.id
    lpd.araddr  := araddr_translated
    lpd.arlen   := axi.ar.bits.len
    lpd.arsize  := axi.ar.bits.size
    lpd.arburst := axi.ar.bits.burst
    lpd.arlock  := axi.ar.bits.lock
    lpd.arcache := "b0010".U  // DEVICE_NON_BUFFERABLE
    lpd.arprot  := axi.ar.bits.prot
    lpd.arqos   := axi.ar.bits.qos
    lpd.arvalid := axi.ar.valid
    axi.ar.ready := lpd.arready

    // ----- R channel -----
    axi.r.bits.id   := lpd.rid
    axi.r.bits.data := lpd.rdata
    axi.r.bits.resp := lpd.rresp
    axi.r.bits.last := lpd.rlast
    axi.r.valid     := lpd.rvalid
    lpd.rready      := axi.r.ready

    // ----- Echo field handling -----
    // TLToAXI4 adds echo fields to track TL source IDs through the AXI4 path.
    // The PS blackbox doesn't know about echo fields, so we queue them on
    // request and attach to response.
    val awEchoQ = Module(new Queue(chiselTypeOf(axi.aw.bits.echo), 8))
    awEchoQ.io.enq.valid := axi.aw.fire
    awEchoQ.io.enq.bits  := axi.aw.bits.echo
    awEchoQ.io.deq.ready := axi.b.fire
    axi.b.bits.echo      := awEchoQ.io.deq.bits

    val arEchoQ = Module(new Queue(chiselTypeOf(axi.ar.bits.echo), 8))
    arEchoQ.io.enq.valid := axi.ar.fire
    arEchoQ.io.enq.bits  := axi.ar.bits.echo
    arEchoQ.io.deq.ready := axi.r.fire && axi.r.bits.last
    axi.r.bits.echo      := arEchoQ.io.deq.bits
  }
}
