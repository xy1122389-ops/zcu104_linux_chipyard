package chipyard.fpga.zcu104

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
  case (th: ZCU104FPGATestHarnessImp, port: UARTPort, chipId: Int) => {
    th.zcu104Outer.io_uart_bb.bundle <> port.io
  }
})

/*** GPIO LED ***/
class WithLEDGPIO extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: GPIOPinsPort, chipId: Int) if port.gpioId == 0 => {
    val ledDrives = Seq(
      th.gpio_led_0_ls_drive,
      th.gpio_led_1_ls_drive,
      th.gpio_led_2_ls_drive,
      th.gpio_led_3_ls_drive
    )
    ledDrives.zipWithIndex.foreach { case (drive, idx) =>
      val ledDrive = port.io.pins(idx).o.oe && port.io.pins(idx).o.oval
      drive := ledDrive
      port.io.pins(idx).i.ival := ledDrive
      port.io.pins(idx).i.po.foreach(_ := false.B)
    }
  }
})

/*** SPI/SD ***/
class WithSPISDCard extends HarnessBinder({
  case (th: ZCU104FPGATestHarnessImp, port: SPIPort, chipId: Int) => {
    th.zcu104Outer.io_spi_bb.foreach(_.bundle <> port.io)
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
    port.io.reset.foreach(_ := false.B)
    jtag_io.TDO.data    := port.io.TDO
    jtag_io.TDO.driven  := true.B
    jtag_io.srst_n      := DontCare
  }
})
