package chipyard.fpga.zcu104

import chisel3._

import org.chipsalliance.cde.config.{Parameters}
import freechips.rocketchip.subsystem.{SystemBusKey}
import freechips.rocketchip.diplomacy.{LazyModule, LazyRawModuleImp, BundleBridgeSource, InModuleBody, AddressSet, IdRange}
import freechips.rocketchip.tilelink._
import freechips.rocketchip.prci._
import chipyard.{ExtTLMem}

import sifive.fpgashells.shell.xilinx._
import sifive.fpgashells.ip.xilinx.{PowerOnResetFPGAOnly}
import sifive.fpgashells.shell._
import sifive.fpgashells.clocks._
import sifive.fpgashells.devices.xilinx.xilinxzcu104ps._

import sifive.blocks.devices.uart.{PeripheryUARTKey, UARTPortIO}
import sifive.blocks.devices.spi.{PeripherySPIKey, SPIPortIO}

import chipyard._
import chipyard.harness._

class ZCU104FPGATestHarness(override implicit val p: Parameters) extends ZCU104ShellBasicOverlays {

  def dp = designParameters

  val pmod_is_sdio = p(ZCU104ShellPMOD) == "SDIO"

  val uart = Overlay(UARTOverlayKey, new UARTZCU104ShellPlacer(this, UARTShellInput()))
  val sdio = if (pmod_is_sdio) Some(Overlay(SPIOverlayKey, new SDIOZCU104ShellPlacer(this, SPIShellInput()))) else None
  val jtag = Overlay(JTAGDebugOverlayKey, new JTAGDebugZCU104ShellPlacer(this, JTAGDebugShellInput()))

  val pllReset = InModuleBody { Wire(Bool()) }

  // clocking
  require(dp(ClockInputOverlayKey).size >= 1)
  val sysClkNode = dp(ClockInputOverlayKey)(0).place(ClockInputDesignInput()).overlayOutput.node

  val harnessSysPLL = dp(PLLFactoryKey)()
  harnessSysPLL := sysClkNode

  val dutFreqMHz = (dp(SystemBusKey).dtsFrequency.get / (1000 * 1000)).toInt
  val dutClock   = ClockSinkNode(freqMHz = dutFreqMHz)
  println(s"ZCU104 FPGA Base Clock Freq: ${dutFreqMHz} MHz")
  val dutWrangler = LazyModule(new ResetWrangler)
  val dutGroup    = ClockGroup()
  dutClock := dutWrangler.node := dutGroup := harnessSysPLL

  // UART
  val io_uart_bb = BundleBridgeSource(() => (new UARTPortIO(dp(PeripheryUARTKey).head)))
  dp(UARTOverlayKey).head.place(UARTDesignInput(io_uart_bb))

  // SPI/SD
  val io_spi_bb = BundleBridgeSource(() => (new SPIPortIO(dp(PeripherySPIKey).head)))
  dp(SPIOverlayKey).head.place(SPIDesignInput(dp(PeripherySPIKey).head, io_spi_bb))

  // PS DDR memory (via Zynq UltraScale+ AXI HP0): no external pins, all internal to PS
  val ddrClient = dp(ExtTLMem).map { m =>
    val psParams = XilinxZCU104PSParams(
      address = AddressSet.misaligned(m.master.base, m.master.size)
    )
    val ps = LazyModule(new XilinxZCU104PS(psParams))
    // ddrClient: the TL node that the chip's memory port connects to
    val client = TLClientNode(Seq(TLMasterPortParameters.v1(Seq(TLMasterParameters.v1(
      name     = "chip_ddr",
      sourceId = IdRange(0, 1 << m.master.idBits)
    )))))
    ps.node := TLWidthWidget(m.master.beatBytes) := client
    (ps, client)
  }

  // JTAG
  val jtagPlacedOverlay = dp(JTAGDebugOverlayKey).head.place(JTAGDebugDesignInput())

  override lazy val module = new ZCU104FPGATestHarnessImp(this)
}

class ZCU104FPGATestHarnessImp(_outer: ZCU104FPGATestHarness) extends LazyRawModuleImp(_outer) with HasHarnessInstantiators {
  override def provideImplicitClockToLazyChildren = true
  val zcu104Outer = _outer
  // DS40 on ZCU104 is driven by GPIO_LED_3_LS on package pin B5.
  val gpio_led_3_ls = IO(Output(Bool())).suggestName("gpio_led_3_ls")
  val gpio_led_3_ls_drive = WireDefault(false.B)
  gpio_led_3_ls := gpio_led_3_ls_drive
  _outer.xdc.addPackagePin(IOPin(gpio_led_3_ls), "B5")
  _outer.xdc.addIOStandard(IOPin(gpio_led_3_ls), "LVCMOS33")

  val sysclk: Clock = _outer.sysClkNode.out.head._1.clock

  val powerOnReset: Bool = PowerOnResetFPGAOnly(sysclk)
  _outer.sdc.addAsyncPath(Seq(powerOnReset))

  _outer.pllReset := powerOnReset

  val hReset = Wire(Reset())
  hReset := _outer.dutClock.in.head._1.reset

  def referenceClockFreqMHz = _outer.dutFreqMHz
  def referenceClock        = _outer.dutClock.in.head._1.clock
  def referenceReset        = hReset
  def success = { require(false, "Unused"); false.B }

  childClock := referenceClock
  childReset := referenceReset

  // Set PS module clock = system clock
  _outer.ddrClient.foreach { case (ps, _) =>
    ps.module.clock := referenceClock
    ps.module.reset := referenceReset
  }

  instantiateChipTops()
}
