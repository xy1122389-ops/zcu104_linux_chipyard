package sifive.fpgashells.shell.xilinx

import chisel3._
import chisel3.experimental.{attach, Analog}
import chisel3.experimental.dataview._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.prci._
import org.chipsalliance.cde.config._
import sifive.fpgashells.clocks._
import sifive.fpgashells.devices.xilinx.xilinxzcu102mig._
import sifive.fpgashells.ip.xilinx._
import sifive.fpgashells.ip.xilinx.zcu102mig._
import sifive.fpgashells.shell._

// ZCU104 uses xczu7ev-ffvc1156-2-e.
// We reuse ZCU102 MIG IP since DDR4 topology is compatible

// 125 MHz differential PL user clock on ZCU104
class SysClockZCU104PlacedOverlay(val shell: ZCU104ShellBasicOverlays, name: String,
    val designInput: ClockInputDesignInput, val shellInput: ClockInputShellInput)
  extends LVDSClockInputXilinxPlacedOverlay(name, designInput, shellInput)
{
  val node = shell { ClockSourceNode(freqMHz = 125, jitterPS = 50)(ValName(name)) }
  shell { InModuleBody {
    shell.xdc.addPackagePin(io.p, "F23")
    shell.xdc.addPackagePin(io.n, "E23")
    shell.xdc.addIOStandard(io.p, "LVDS")
    shell.xdc.addIOStandard(io.n, "LVDS")
  }}
}
class SysClockZCU104ShellPlacer(shell: ZCU104ShellBasicOverlays, val shellInput: ClockInputShellInput)(implicit val valName: ValName)
  extends ClockInputShellPlacer[ZCU104ShellBasicOverlays]
{
  def place(designInput: ClockInputDesignInput) = new SysClockZCU104PlacedOverlay(shell, valName.name, designInput, shellInput)
}

// UART on the board FT4232 channel D / UART2 path.
class UARTZCU104PlacedOverlay(val shell: ZCU104ShellBasicOverlays, name: String,
    val designInput: UARTDesignInput, val shellInput: UARTShellInput)
  extends UARTXilinxPlacedOverlay(name, designInput, shellInput, false)
{
  shell { InModuleBody {
    val packagePinsWithPackageIOs = Seq(
      // Route the FPGA UART to PMOD1 for direct cable access:
      //   J9  -> PMOD1_0 -> FPGA TXD
      //   K9  -> PMOD1_1 -> FPGA RXD
      ("K9", IOPin(io.rxd)),
      ("J9", IOPin(io.txd)))
    packagePinsWithPackageIOs foreach { case (pin, io) => {
      shell.xdc.addPackagePin(io, pin)
      shell.xdc.addIOStandard(io, "LVCMOS33")
    } }
  } }
}
class UARTZCU104ShellPlacer(shell: ZCU104ShellBasicOverlays, val shellInput: UARTShellInput)(implicit val valName: ValName)
  extends UARTShellPlacer[ZCU104ShellBasicOverlays]
{
  def place(designInput: UARTDesignInput) = new UARTZCU104PlacedOverlay(shell, valName.name, designInput, shellInput)
}

// SDIO on PMOD J55
// NOTE: Bank 67/68 are HP banks on ZCU104 - must use LVCMOS18, NOT LVCMOS33
class SDIOZCU104PlacedOverlay(val shell: ZCU104ShellBasicOverlays, name: String,
    val designInput: SPIDesignInput, val shellInput: SPIShellInput)
  extends SDIOXilinxPlacedOverlay(name, designInput, shellInput)
{
  shell { InModuleBody {
    // J55 PMOD pins (ZCU104 UG1267, Table 1-22) - all in Bank 67/68 (HP)
    val packagePinsWithPackageIOs = Seq(
      ("E12", IOPin(io.spi_clk)),
      ("F11", IOPin(io.spi_cs)),
      ("D12", IOPin(io.spi_dat(0))),
      ("C12", IOPin(io.spi_dat(1))),
      ("B12", IOPin(io.spi_dat(2))),
      ("A12", IOPin(io.spi_dat(3))))
    packagePinsWithPackageIOs foreach { case (pin, io) => {
      shell.xdc.addPackagePin(io, pin)
      shell.xdc.addIOStandard(io, "LVCMOS18")
    } }
    packagePinsWithPackageIOs drop 1 foreach { case (pin, io) => {
      shell.xdc.addPullup(io)
      shell.xdc.addIOB(io)
    } }
  } }
}
class SDIOZCU104ShellPlacer(shell: ZCU104ShellBasicOverlays, val shellInput: SPIShellInput)(implicit val valName: ValName)
  extends SPIShellPlacer[ZCU104ShellBasicOverlays]
{
  def place(designInput: SPIDesignInput) = new SDIOZCU104PlacedOverlay(shell, valName.name, designInput, shellInput)
}

// External Rocket/J-Link JTAG on PMOD0 / J55.
// Pinout follows the ZCU104 master XDC PMOD0_4..7 entries:
//   TDI -> PMOD0_4 -> G6
//   TMS -> PMOD0_5 -> H6
//   TCK -> PMOD0_6 -> J6
//   TDO -> PMOD0_7 -> J7
class JTAGDebugZCU104PlacedOverlay(val shell: ZCU104ShellBasicOverlays, name: String,
    val designInput: JTAGDebugDesignInput, val shellInput: JTAGDebugShellInput)
  extends JTAGDebugXilinxPlacedOverlay(name, designInput, shellInput)
{
  shell { InModuleBody {
    shell.xdc.addPackagePin(IOPin(io.jtag_TDI), "G6")
    shell.xdc.addIOStandard(IOPin(io.jtag_TDI), "LVCMOS33")
    shell.xdc.addPackagePin(IOPin(io.jtag_TMS), "H6")
    shell.xdc.addIOStandard(IOPin(io.jtag_TMS), "LVCMOS33")
    shell.xdc.addPackagePin(IOPin(io.jtag_TCK), "J6")
    shell.xdc.addIOStandard(IOPin(io.jtag_TCK), "LVCMOS33")
    shell.xdc.clockDedicatedRouteFalse(IOPin(io.jtag_TCK)) // prevent JTAG TCK from using dedicated clock routing
    shell.xdc.addPackagePin(IOPin(io.jtag_TDO), "J7")
    shell.xdc.addIOStandard(IOPin(io.jtag_TDO), "LVCMOS33")
  } }
}
class JTAGDebugZCU104ShellPlacer(shell: ZCU104ShellBasicOverlays, val shellInput: JTAGDebugShellInput)(implicit val valName: ValName)
  extends JTAGDebugShellPlacer[ZCU104ShellBasicOverlays]
{
  def place(designInput: JTAGDebugDesignInput) = new JTAGDebugZCU104PlacedOverlay(shell, valName.name, designInput, shellInput)
}

class JTAGDebugBScanZCU104PlacedOverlay(
  val shell: ZCU104ShellBasicOverlays,
  name: String,
  val designInput: JTAGDebugBScanDesignInput,
  val shellInput: JTAGDebugBScanShellInput)
  extends JTAGDebugBScanXilinxPlacedOverlay(name, designInput, shellInput)

class JTAGDebugBScanZCU104ShellPlacer(
  shell: ZCU104ShellBasicOverlays,
  val shellInput: JTAGDebugBScanShellInput)(implicit val valName: ValName)
  extends JTAGDebugBScanShellPlacer[ZCU104ShellBasicOverlays]
{
  def place(designInput: JTAGDebugBScanDesignInput) =
    new JTAGDebugBScanZCU104PlacedOverlay(shell, valName.name, designInput, shellInput)
}

// DDR: ZCU104 has no PL-side DDR4. Memory provided via PS AXI HP0 or scratchpad.
// This placeholder DDR overlay is unused in the no-DDR config.
// For PS DDR support, see ZCU104FPGATestHarness which instantiates XilinxZCU104PS directly.
case object ZCU104DDRSize extends Field[BigInt](0x40000000L * 2) // 2GB

class DDRZCU104ShellPlacer(shell: ZCU104ShellBasicOverlays, val shellInput: DDRShellInput)(implicit val valName: ValName)
  extends DDRShellPlacer[ZCU104ShellBasicOverlays]
{
  def place(designInput: DDRDesignInput) = throw new Exception("ZCU104 has no PL DDR. Use PS-based memory in TestHarness instead.")
}

abstract class ZCU104ShellBasicOverlays()(implicit p: Parameters) extends UltraScaleShell {
  // must match zcu104/tcl/board.tcl
  val pllReset: ModuleValue[Bool]
  val sys_clock = Overlay(ClockInputOverlayKey, new SysClockZCU104ShellPlacer(this, ClockInputShellInput()))
  val ddr       = Overlay(DDROverlayKey, new DDRZCU104ShellPlacer(this, DDRShellInput()))
}

case object ZCU104ShellPMOD extends Field[String]("SDIO")

class WithZCU104ShellPMOD(device: String) extends Config((site, here, up) => {
  case ZCU104ShellPMOD => device
})
class WithZCU104ShellPMODSDIO extends WithZCU104ShellPMOD("SDIO")

class ZCU104Shell()(implicit p: Parameters) extends ZCU104ShellBasicOverlays {
  val pmod_is_sdio = p(ZCU104ShellPMOD) == "SDIO"

  val uart      = Overlay(UARTOverlayKey, new UARTZCU104ShellPlacer(this, UARTShellInput()))
  val sdio      = if (pmod_is_sdio) Some(Overlay(SPIOverlayKey, new SDIOZCU104ShellPlacer(this, SPIShellInput()))) else None
  val jtag      = Overlay(JTAGDebugOverlayKey, new JTAGDebugZCU104ShellPlacer(this, JTAGDebugShellInput()))
  // Keep the BSCAN overlay available for alternate debug flows, but the
  // Linux bringup test harness can choose to leave it unplaced.
  val jtagBScan = Overlay(JTAGDebugBScanOverlayKey, new JTAGDebugBScanZCU104ShellPlacer(this, JTAGDebugBScanShellInput()))

  val pllReset = InModuleBody { Wire(Bool()) }
}
