package chipyard.fpga.zcu102

import chisel3._

import org.chipsalliance.diplomacy.nodes.{HeterogeneousBag}
import freechips.rocketchip.tilelink.{TLBundle}

import sifive.blocks.devices.uart.{UARTPortIO}
import sifive.blocks.devices.spi.{SPIPortIO}

import chipyard._
import chipyard.harness._
import chipyard.iobinders._

/*** UART ***/
class WithUART extends HarnessBinder({
  case (th: ZCU102FPGATestHarnessImp, port: UARTPort, chipId: Int) => {
    th.zcu102Outer.io_uart_bb.bundle <> port.io
  }
})

/*** SPI/SD ***/
class WithSPISDCard extends HarnessBinder({
  case (th: ZCU102FPGATestHarnessImp, port: SPIPort, chipId: Int) => {
    th.zcu102Outer.io_spi_bb.bundle <> port.io
  }
})

/*** JTAG ***/
class WithJTAG extends HarnessBinder({
  case (th: ZCU102FPGATestHarnessImp, port: JTAGPort, chipId: Int) => {
    val jtag_io = th.zcu102Outer.jtagPlacedOverlay.overlayOutput.jtag.getWrappedValue
    port.io.TCK := jtag_io.TCK
    port.io.TMS := jtag_io.TMS
    port.io.TDI := jtag_io.TDI
    port.io.reset.foreach(_ := th.referenceReset)
    jtag_io.TDO.data    := port.io.TDO
    jtag_io.TDO.driven  := true.B
    jtag_io.srst_n      := DontCare
  }
})
