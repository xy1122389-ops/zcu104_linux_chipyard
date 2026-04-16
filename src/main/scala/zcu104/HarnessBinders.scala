package chipyard.fpga.zcu104

import chisel3._

import org.chipsalliance.cde.config.Parameters
import org.chipsalliance.diplomacy.nodes.{HeterogeneousBag}
import freechips.rocketchip.amba.axi4.AXI4Parameters
import freechips.rocketchip.tilelink.{TLBundle}

import sifive.blocks.devices.uart.{UARTPortIO}
import sifive.blocks.devices.spi.{SPIPortIO}

import chipyard._
import chipyard.harness._
import chipyard.iobinders._

/*** UART0 (console) ***/
class WithUART extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: UARTPort, chipId: Int) if port.uartNo == 0 => {
    th.zcu104Outer.io_uart_bb.bundle <> port.io
  }
})

/*** UART1 (SLIP networking) ***/
class WithUART1 extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: UARTPort, chipId: Int) if port.uartNo == 1 => {
    th.zcu104Outer.io_uart1_bb.bundle <> port.io
  }
})

/*** GPIO LED ***/
class WithLEDGPIO extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: GPIOPinsPort, chipId: Int) if port.gpioId == 0 => {
    // GPIO bit 0 drives DS39 through gpio_led_2_ls on A5.
    val ledDrive = port.io.pins(0).o.oe && port.io.pins(0).o.oval
    th.gpio_led_2_ls_drive := ledDrive
    port.io.pins(0).i.ival := ledDrive
    port.io.pins(0).i.po.foreach(_ := false.B)
  }
})

/*** SPI/SD ***/
class WithSPISDCard extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: SPIPort, chipId: Int) => {
    th.zcu104Outer.io_spi_bb.bundle <> port.io
  }
})

/*** PS DDR Memory (via AXI HP0) ***/
class WithPSDDRMem extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: TLMemPort, chipId: Int) => {
    th.zcu104Outer.ddrClient.foreach { case (_, client) =>
      val bundles = client.out.map(_._1)
      val ddrClientBundle = Wire(new HeterogeneousBag(bundles.map(_.cloneType)))
      bundles.zip(ddrClientBundle).foreach { case (bundle, io) => bundle <> io }
      ddrClientBundle <> port.io
    }
  }
})

/*** JTAG ***/
class WithJTAG extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: JTAGPort, chipId: Int) => {
    val jtag_io = th.zcu104Outer.jtagPlacedOverlay.overlayOutput.jtag.getWrappedValue
    port.io.TCK := jtag_io.TCK
    port.io.TMS := jtag_io.TMS
    port.io.TDI := jtag_io.TDI
    port.io.reset.foreach(_ := th.referenceReset)
    jtag_io.TDO.data    := port.io.TDO
    jtag_io.TDO.driven  := true.B
    jtag_io.srst_n      := DontCare
  }
})

/*** PS LPD MMIO (via S_AXI_LPD / saxigp6) — A2 path to PS SDIO/J100 ***/
class WithPSLPDMem extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: AXI4MMIOPort, chipId: Int) => {
    th.zcu104Outer.ddrClient.foreach { case (ps, _) =>
      val lpd = ps.module.lpd   // ZCU104PSLPDBundle (slave perspective)
      val axi = port.io.bits    // AXI4Bundle (master perspective)

      // Address translation: Rocket 0x60xxxxxx → PS 0xFFxxxxxx (add 0x9F000000)
      val addrOffset = BigInt("9F000000", 16).U(49.W)

      // ----- AW channel -----
      lpd.awid    := axi.aw.bits.id
      lpd.awaddr  := axi.aw.bits.addr + addrOffset
      lpd.awlen   := axi.aw.bits.len
      lpd.awsize  := axi.aw.bits.size
      lpd.awburst := axi.aw.bits.burst
      lpd.awlock  := axi.aw.bits.lock
      lpd.awcache := "b0010".U   // DEVICE_NON_BUFFERABLE
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

      // ----- AR channel -----
      lpd.arid    := axi.ar.bits.id
      lpd.araddr  := axi.ar.bits.addr + addrOffset
      lpd.arlen   := axi.ar.bits.len
      lpd.arsize  := axi.ar.bits.size
      lpd.arburst := axi.ar.bits.burst
      lpd.arlock  := axi.ar.bits.lock
      lpd.arcache := "b0010".U   // DEVICE_NON_BUFFERABLE
      lpd.arprot  := axi.ar.bits.prot
      lpd.arqos   := axi.ar.bits.qos
      lpd.arvalid := axi.ar.valid
      axi.ar.ready := lpd.arready

      // ----- B channel (response) -----
      axi.b.bits.id   := lpd.bid
      axi.b.bits.resp := lpd.bresp
      axi.b.valid     := lpd.bvalid
      lpd.bready      := axi.b.ready

      // ----- R channel (response) -----
      axi.r.bits.id   := lpd.rid
      axi.r.bits.data := lpd.rdata
      axi.r.bits.resp := lpd.rresp
      axi.r.bits.last := lpd.rlast
      axi.r.valid     := lpd.rvalid
      lpd.rready      := axi.r.ready

      // ----- Echo field handling -----
      // TLToAXI4 puts echo metadata on AW/AR that MUST be returned on B/R.
      // PS blackbox doesn't know about echo fields, so we queue and replay.
      val awEchoQ = Module(new chisel3.util.Queue(chisel3.reflect.DataMirror.internal.chiselTypeClone(axi.aw.bits.echo), 8))
      awEchoQ.io.enq.valid := axi.aw.fire
      awEchoQ.io.enq.bits  := axi.aw.bits.echo
      awEchoQ.io.deq.ready := axi.b.fire
      axi.b.bits.echo      := awEchoQ.io.deq.bits

      val arEchoQ = Module(new chisel3.util.Queue(chisel3.reflect.DataMirror.internal.chiselTypeClone(axi.ar.bits.echo), 8))
      arEchoQ.io.enq.valid := axi.ar.fire
      arEchoQ.io.enq.bits  := axi.ar.bits.echo
      arEchoQ.io.deq.ready := axi.r.fire && axi.r.bits.last
      axi.r.bits.echo      := arEchoQ.io.deq.bits
    }
  }
})

/*** Tie off AXI4 MMIO without instantiating the default SimAXIMem ***/
class WithTiedOffAXI4MMIO extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: AXI4MMIOPort, chipId: Int) => {
    val axi = port.io.bits

    // Keep the port present in the design, but prevent Chipyard's default
    // WithSimAXIMMIO binder from synthesizing a large backing memory.
    axi.aw.ready := false.B
    axi.w.ready := false.B
    axi.ar.ready := false.B

    axi.b.valid := false.B
    axi.b.bits.id := 0.U.asTypeOf(axi.b.bits.id)
    axi.b.bits.resp := AXI4Parameters.RESP_DECERR
    axi.b.bits.echo := 0.U.asTypeOf(axi.b.bits.echo)

    axi.r.valid := false.B
    axi.r.bits.id := 0.U.asTypeOf(axi.r.bits.id)
    axi.r.bits.data := 0.U
    axi.r.bits.resp := AXI4Parameters.RESP_DECERR
    axi.r.bits.last := true.B
    axi.r.bits.echo := 0.U.asTypeOf(axi.r.bits.echo)
  }
})
