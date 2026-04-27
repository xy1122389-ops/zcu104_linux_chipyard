package chipyard.fpga.zcu104

import chisel3._
import chisel3.util._

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
    // GPIO bit 0 → DS39 (gpio_led_2_ls, A5)
    val led39Drive = port.io.pins(0).o.oe && port.io.pins(0).o.oval
    th.gpio_led_2_ls_drive := led39Drive
    port.io.pins(0).i.ival := led39Drive
    port.io.pins(0).i.po.foreach(_ := false.B)

    // GPIO bit 1 → DS40 (gpio_led_3_ls, B5)
    if (port.io.pins.length > 1) {
      val led40Drive = port.io.pins(1).o.oe && port.io.pins(1).o.oval
      th.gpio_led_3_ls_drive := led40Drive
      port.io.pins(1).i.ival := led40Drive
      port.io.pins(1).i.po.foreach(_ := false.B)
    }
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
      val psMMIOProt  = (AXI4Parameters.PROT_PRIVILEGED | AXI4Parameters.PROT_INSECURE)
      val readTimeoutCycles  = 1024.U
      val writeTimeoutCycles = 1024.U

      val arBurstSupported = axi.ar.bits.burst === AXI4Parameters.BURST_INCR
      val awBurstSupported = axi.aw.bits.burst === AXI4Parameters.BURST_INCR
      val arSizeSupported  = axi.ar.bits.size <= 2.U
      val awSizeSupported  = axi.aw.bits.size <= 2.U

      val readInFlight  = RegInit(false.B)
      val readWatchdog  = RegInit(0.U(16.W))
      val readAddr      = RegInit(0.U(49.W))
      val readSize      = RegInit(0.U(3.W))
      val readLen       = RegInit(0.U(8.W))
      val readBurst     = RegInit(0.U(2.W))
      val readResp      = RegInit(0.U(2.W))
      val arSeen        = RegInit(false.B)
      val rSeen         = RegInit(false.B)

      val writeInFlight = RegInit(false.B)
      val writeWatchdog = RegInit(0.U(16.W))
      val writeAddr     = RegInit(0.U(49.W))
      val writeSize     = RegInit(0.U(3.W))
      val writeLen      = RegInit(0.U(8.W))
      val writeBurst    = RegInit(0.U(2.W))
      val writeStrb     = RegInit(0.U(4.W))
      val writeResp     = RegInit(0.U(2.W))

      val timeoutSeen          = RegInit(false.B)
      val unsupportedSizeSeen  = RegInit(false.B)
      val unsupportedBurstSeen = RegInit(false.B)

      when (axi.ar.fire) {
        printf("[pslpd] AR addr=0x%x size=%d len=%d burst=%d prot_in=0x%x cache_in=0x%x id=%d\n",
          axi.ar.bits.addr + addrOffset, axi.ar.bits.size, axi.ar.bits.len, axi.ar.bits.burst,
          axi.ar.bits.prot, axi.ar.bits.cache, axi.ar.bits.id)
        assert(!readInFlight, "[pslpd] multiple read requests in flight")
        assert(axi.ar.bits.len === 0.U, "[pslpd] unsupported ARLEN for PS-LPD MMIO")
        assert(arBurstSupported, "[pslpd] unsupported ARBURST for PS-LPD MMIO")
        assert(arSizeSupported, "[pslpd] unsupported ARSIZE for PS-LPD MMIO")
        readInFlight := true.B
        readWatchdog := 0.U
        readAddr := axi.ar.bits.addr + addrOffset
        readSize := axi.ar.bits.size
        readLen := axi.ar.bits.len
        readBurst := axi.ar.bits.burst
        arSeen := true.B
        when (!arSizeSupported) { unsupportedSizeSeen := true.B }
        when (!arBurstSupported) { unsupportedBurstSeen := true.B }
      }.elsewhen(readInFlight && !(axi.r.fire && axi.r.bits.last)) {
        readWatchdog := readWatchdog + 1.U
      }

      when (axi.r.fire) {
        printf("[pslpd] R addr=0x%x data=0x%x resp=%d last=%d id=%d\n",
          readAddr, axi.r.bits.data, axi.r.bits.resp, axi.r.bits.last, axi.r.bits.id)
        readResp := axi.r.bits.resp
        rSeen := true.B
      }

      when (readInFlight) {
        when (readWatchdog === readTimeoutCycles - 1.U) { timeoutSeen := true.B }
        assert(readWatchdog =/= readTimeoutCycles, "[pslpd] read request did not complete in time")
      }
      when (axi.r.valid) {
        assert(readInFlight, "[pslpd] stray read response without matching request")
      }
      when (axi.r.fire && axi.r.bits.last) {
        readInFlight := false.B
      }

      when (axi.aw.fire) {
        printf("[pslpd] AW addr=0x%x size=%d len=%d burst=%d prot_in=0x%x cache_in=0x%x id=%d\n",
          axi.aw.bits.addr + addrOffset, axi.aw.bits.size, axi.aw.bits.len, axi.aw.bits.burst,
          axi.aw.bits.prot, axi.aw.bits.cache, axi.aw.bits.id)
        assert(!writeInFlight, "[pslpd] multiple write requests in flight")
        assert(axi.aw.bits.len === 0.U, "[pslpd] unsupported AWLEN for PS-LPD MMIO")
        assert(awBurstSupported, "[pslpd] unsupported AWBURST for PS-LPD MMIO")
        assert(awSizeSupported, "[pslpd] unsupported AWSIZE for PS-LPD MMIO")
        writeInFlight := true.B
        writeWatchdog := 0.U
        writeAddr := axi.aw.bits.addr + addrOffset
        writeSize := axi.aw.bits.size
        writeLen := axi.aw.bits.len
        writeBurst := axi.aw.bits.burst
        when (!awSizeSupported) { unsupportedSizeSeen := true.B }
        when (!awBurstSupported) { unsupportedBurstSeen := true.B }
      }.elsewhen(writeInFlight && !axi.b.fire) {
        writeWatchdog := writeWatchdog + 1.U
      }

      when (axi.w.fire) {
        printf("[pslpd] W addr=0x%x data=0x%x strb=0x%x last=%d\n",
          writeAddr, axi.w.bits.data, axi.w.bits.strb, axi.w.bits.last)
        writeStrb := axi.w.bits.strb
      }

      when (axi.b.fire) {
        printf("[pslpd] B addr=0x%x resp=%d id=%d strb=0x%x\n",
          writeAddr, axi.b.bits.resp, axi.b.bits.id, writeStrb)
        writeResp := axi.b.bits.resp
      }

      when (writeInFlight) {
        when (writeWatchdog === writeTimeoutCycles - 1.U) { timeoutSeen := true.B }
        assert(writeWatchdog =/= writeTimeoutCycles, "[pslpd] write request did not complete in time")
      }
      when (axi.b.valid) {
        assert(writeInFlight, "[pslpd] stray write response without matching request")
      }
      when (axi.b.fire) {
        writeInFlight := false.B
      }

      // ----- AW channel -----
      lpd.awid    := axi.aw.bits.id
      lpd.awaddr  := axi.aw.bits.addr + addrOffset
      lpd.awlen   := 0.U
      lpd.awsize  := axi.aw.bits.size
      lpd.awburst := AXI4Parameters.BURST_INCR
      lpd.awlock  := 0.U
      lpd.awcache := axi.aw.bits.cache
      lpd.awprot  := psMMIOProt
      lpd.awqos   := 0.U
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
      lpd.arlen   := 0.U
      lpd.arsize  := axi.ar.bits.size
      lpd.arburst := AXI4Parameters.BURST_INCR
      lpd.arlock  := 0.U
      lpd.arcache := axi.ar.bits.cache
      lpd.arprot  := psMMIOProt
      lpd.arqos   := 0.U
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
