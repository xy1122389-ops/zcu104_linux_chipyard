package chipyard.fpga.zcu104

import chisel3._
import chisel3.util._

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

  val uart1 = Overlay(UARTOverlayKey, new UART1ZCU104ShellPlacer(this, UARTShellInput(index = 1)))
  val uart  = Overlay(UARTOverlayKey, new UARTZCU104ShellPlacer(this, UARTShellInput()))
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

  // UART0 (console)
  val io_uart_bb = BundleBridgeSource(() => (new UARTPortIO(dp(PeripheryUARTKey)(0))))
  dp(UARTOverlayKey).head.place(UARTDesignInput(io_uart_bb))

  // UART1 (SLIP networking)
  val io_uart1_bb = BundleBridgeSource(() => (new UARTPortIO(dp(PeripheryUARTKey)(1))))
  dp(UARTOverlayKey).head.place(UARTDesignInput(io_uart1_bb))

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
  // DS39 (gpio_led_2_ls) → A5, Bank 88, LVCMOS33
  val gpio_led_2_ls = IO(Output(Bool())).suggestName("gpio_led_2_ls")
  val gpio_led_2_ls_drive = WireDefault(false.B)
  _outer.xdc.addPackagePin(IOPin(gpio_led_2_ls), "A5")
  _outer.xdc.addIOStandard(IOPin(gpio_led_2_ls), "LVCMOS33")

  // DS40 (gpio_led_3_ls) → B5, Bank 88, LVCMOS33
  val gpio_led_3_ls = IO(Output(Bool())).suggestName("gpio_led_3_ls")
  val gpio_led_3_ls_drive = WireDefault(false.B)
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

  // Blink DS39 and DS40 in a paired dual-core signature so a freshly
  // synthesised dual-core bitstream is immediately obvious after programming.
  // Pattern runs from a shared 27-bit counter (at 50 MHz each phase ≈ 167 ms,
  // full cycle ≈ 2.68 s). GPIO software override is preserved on both LEDs.
  val (led39, led40) = withClockAndReset(referenceClock, referenceReset) {
    val counter = RegInit(0.U(27.W))
    counter := counter + 1.U

    val phase = counter(26, 23)   // 16 steps × ~167 ms = ~2.68 s cycle

    // DS39 (A5): two short flashes then a long gap  — marks "core 0"
    val ds39 = (phase === "b0000".U) ||
               (phase === "b0010".U) ||
               (phase === "b1000".U)

    // DS40 (B5): single long flash offset by ~500 ms — marks "core 1"
    // Phases 4-5 = on for ~334 ms, rest off; clearly distinct from DS39.
    val ds40 = (phase === "b0100".U) ||
               (phase === "b0101".U)

    (ds39, ds40)
  }
  gpio_led_2_ls := gpio_led_2_ls_drive || led39
  gpio_led_3_ls := gpio_led_3_ls_drive || led40

  childClock := referenceClock
  childReset := referenceReset

  // Set PS module clock = system clock
  _outer.ddrClient.foreach { case (ps, _) =>
    ps.module.clock := referenceClock
    ps.module.reset := referenceReset

    // Default tie-off for the optional PS LPD AXI slave port. Diagnostic
    // configs that remove the A2 path still instantiate the PS block, so the
    // raw LPD inputs must be driven even when no HarnessBinder consumes them.
    // If WithPSLPDMem is present, its later connections override these values.
    val lpd = ps.module.lpd
    lpd.awid    := 0.U
    lpd.awaddr  := 0.U
    lpd.awlen   := 0.U
    lpd.awsize  := 0.U
    lpd.awburst := 0.U
    lpd.awlock  := 0.U
    lpd.awcache := 0.U
    lpd.awprot  := 0.U
    lpd.awqos   := 0.U
    lpd.awvalid := false.B
    lpd.wdata   := 0.U
    lpd.wstrb   := 0.U
    lpd.wlast   := false.B
    lpd.wvalid  := false.B
    lpd.bready  := false.B
    lpd.arid    := 0.U
    lpd.araddr  := 0.U
    lpd.arlen   := 0.U
    lpd.arsize  := 0.U
    lpd.arburst := 0.U
    lpd.arlock  := 0.U
    lpd.arcache := 0.U
    lpd.arprot  := 0.U
    lpd.arqos   := 0.U
    lpd.arvalid := false.B
    lpd.rready  := false.B
  }

  instantiateChipTops()
}
