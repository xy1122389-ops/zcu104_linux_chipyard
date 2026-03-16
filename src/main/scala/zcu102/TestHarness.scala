package chipyard.fpga.zcu102

import chisel3._
import chisel3.experimental.{attach}

import org.chipsalliance.cde.config.{Parameters}
import freechips.rocketchip.subsystem.{SystemBusKey}
import freechips.rocketchip.diplomacy.{LazyModule, LazyRawModuleImp, BundleBridgeSource, InModuleBody}
import freechips.rocketchip.prci._

import sifive.fpgashells.shell.xilinx._
import sifive.fpgashells.ip.xilinx.{PowerOnResetFPGAOnly, IBUF}
import sifive.fpgashells.shell._
import sifive.fpgashells.clocks._

import sifive.blocks.devices.uart.{PeripheryUARTKey, UARTPortIO}
import sifive.blocks.devices.spi.{PeripherySPIKey, SPIPortIO}

import chipyard._
import chipyard.harness._

class ZCU102FPGATestHarness(override implicit val p: Parameters) extends ZCU102ShellBasicOverlays {

  def dp = designParameters

  val pmod_is_sdio = p(ZCU102ShellPMOD) == "SDIO"

  // Overlays
  val uart      = Overlay(UARTOverlayKey, new UARTZCU102ShellPlacer(this, UARTShellInput()))
  val sdio      = if (pmod_is_sdio) Some(Overlay(SPIOverlayKey, new SDIOZCU102ShellPlacer(this, SPIShellInput()))) else None
  val jtag      = Overlay(JTAGDebugOverlayKey, new JTAGDebugZCU102ShellPlacer(this, JTAGDebugShellInput(location = Some("FMC_J5"))))

  // Clocking
  val sysClkNode = dp(ClockInputOverlayKey)(0).place(ClockInputDesignInput()).overlayOutput.node

  val harnessSysPLL = dp(PLLFactoryKey)()
  harnessSysPLL := sysClkNode

  val dutFreqMHz = (dp(SystemBusKey).dtsFrequency.get / (1000 * 1000)).toInt
  val dutClock   = ClockSinkNode(freqMHz = dutFreqMHz)
  println(s"ZCU102 FPGA Base Clock Freq: ${dutFreqMHz} MHz")
  val dutWrangler = LazyModule(new ResetWrangler)
  val dutGroup    = ClockGroup()
  dutClock := dutWrangler.node := dutGroup := harnessSysPLL

  // UART
  val io_uart_bb = BundleBridgeSource(() => (new UARTPortIO(dp(PeripheryUARTKey).head)))
  dp(UARTOverlayKey).head.place(UARTDesignInput(io_uart_bb))

  // SPI/SD
  val io_spi_bb = BundleBridgeSource(() => (new SPIPortIO(dp(PeripherySPIKey).head)))
  dp(SPIOverlayKey).head.place(SPIDesignInput(dp(PeripherySPIKey).head, io_spi_bb))

  // JTAG
  val jtagPlacedOverlay = dp(JTAGDebugOverlayKey).head.place(JTAGDebugDesignInput())

  override lazy val module = new ZCU102FPGATestHarnessImp(this)
}

class ZCU102FPGATestHarnessImp(_outer: ZCU102FPGATestHarness) extends LazyRawModuleImp(_outer) with HasHarnessInstantiators {
  override def provideImplicitClockToLazyChildren = true
  val zcu102Outer = _outer

  val reset = IO(Input(Bool())).suggestName("reset")
  _outer.xdc.addPackagePin(reset, "AM13")
  _outer.xdc.addIOStandard(reset, "LVCMOS33")
  val reset_ibuf = Module(new IBUF)
  reset_ibuf.io.I := reset

  val sysclk: Clock = _outer.sysClkNode.out.head._1.clock

  val powerOnReset: Bool = PowerOnResetFPGAOnly(sysclk)
  _outer.sdc.addAsyncPath(Seq(powerOnReset))

  _outer.pllReset := (reset_ibuf.io.O || powerOnReset)

  val hReset = Wire(Reset())
  hReset := _outer.dutClock.in.head._1.reset

  def referenceClockFreqMHz = _outer.dutFreqMHz
  def referenceClock        = _outer.dutClock.in.head._1.clock
  def referenceReset        = hReset
  def success = { require(false, "Unused"); false.B }

  childClock := referenceClock
  childReset := referenceReset

  instantiateChipTops()
}
