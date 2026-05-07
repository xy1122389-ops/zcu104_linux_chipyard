package chipyard.fpga.zcu104

import sys.process._

import org.chipsalliance.cde.config.{Config, Parameters}
import freechips.rocketchip.subsystem.{SystemBusKey, PeripheryBusKey, ControlBusKey, ExtMem, ExtBus, MasterPortParams}
import freechips.rocketchip.devices.debug.{DebugModuleKey, ExportDebug, JTAG}
import freechips.rocketchip.devices.tilelink.{DevNullParams, BootROMLocated}
import freechips.rocketchip.diplomacy.{RegionType, AddressSet}
import freechips.rocketchip.resources.{DTSModel, DTSTimebase}
import freechips.rocketchip.util.{SystemFileName}

import sifive.blocks.devices.spi.{PeripherySPIKey, SPIParams}
import sifive.blocks.devices.uart.{PeripheryUARTKey, UARTParams}

import sifive.fpgashells.shell.{DesignKey}
import sifive.fpgashells.shell.xilinx.{ZCU104ShellPMOD, ZCU104DDRSize}

import testchipip.serdes.{SerialTLKey}
import testchipip.soc.SubsystemInjectorKey

import chipyard._
import chipyard.harness._

class WithZCU104DefaultPeripherals extends Config((site, here, up) => {
  case PeripheryUARTKey => List(
    UARTParams(address = BigInt(0x64000000L)),  // UART0: console (J9/K9)
    UARTParams(address = BigInt(0x64003000L))   // UART1: SLIP networking (L8/K8)
  )
  case PeripherySPIKey  => List(SPIParams(rAddress = BigInt(0x64001000L)))
  case ZCU104ShellPMOD  => "SDIO"
})

class WithZCU104SystemModifications extends Config((site, here, up) => {
  case DTSTimebase => BigInt((1e6).toLong)
  case BootROMLocated(x) => up(BootROMLocated(x), site).map { p =>
    val freqMHz = (site(SystemBusKey).dtsFrequency.get / (1000 * 1000)).toLong
    val make = s"make -C fpga/src/main/resources/zcu104/sdboot PBUS_CLK=${freqMHz} bin"
    require(make.! == 0, "Failed to build ZCU104 bootrom")
    p.copy(hang = 0x10000, contentFileName = SystemFileName(s"./fpga/src/main/resources/zcu104/sdboot/build/sdboot.bin"))
  }
  case ExtMem => up(ExtMem, site).map(x => x.copy(master = x.master.copy(size = site(ZCU104DDRSize))))
  case SerialTLKey => Nil
})

// WithDDRMem config: uses PS AXI HP0 → PS DDR4 (2GB)
// A2: Rocket → S_AXI_LPD → PS SDIO (J100). MMIO port at 0x60000000, 2MB.
class WithPSLPDMMIOPort extends Config((site, here, up) => {
  case ExtBus => Some(MasterPortParams(
    base = BigInt(0x60000000L),
    size = BigInt(0x200000L),   // 2MB window → PS 0xFF000000–0xFF1FFFFF (covers SDIO1 @ 0xFF170000)
    beatBytes = 4,              // 32-bit data (matches S_AXI_LPD DATA_WIDTH=32)
    idBits = 4))
})

// Requires FSBL to initialize PS DDR before PL bitstream is loaded
class WithZCU104Tweaks extends Config(
  new chipyard.iobinders.WithGPIOPunchthrough ++
  new chipyard.harness.WithAllClocksFromHarnessClockInstantiator ++
  new chipyard.clocking.WithPassthroughClockGenerator ++
  new chipyard.config.WithUniformBusFrequencies(50) ++
  new WithFPGAFrequency(50) ++
  new chipyard.config.WithGPIO(address = BigInt(0x64002000L), width = 1) ++
  new WithLEDGPIO ++
  new WithUART ++
  new WithUART1 ++
  new WithSPISDCard ++
  new WithPSDDRMem ++
  new WithPSLPDMem ++
  new WithJTAG ++
  new WithPSLPDMMIOPort ++
  new WithZCU104DefaultPeripherals ++
  new chipyard.config.WithTLBackingMemory ++
  new WithZCU104SystemModifications ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new freechips.rocketchip.subsystem.WithNMemoryChannels(1)
)

// Common ZCU104 bring-up stack without the A2 PSLPD MMIO path.
// Use this as the base for J-Link diagnostics to verify whether removing the
// Rocket -> S_AXI_LPD path restores clean debug halt behavior.
class WithZCU104TweaksNoPSLPD extends Config(
  new chipyard.iobinders.WithGPIOPunchthrough ++
  new chipyard.harness.WithAllClocksFromHarnessClockInstantiator ++
  new chipyard.clocking.WithPassthroughClockGenerator ++
  new chipyard.config.WithUniformBusFrequencies(50) ++
  new WithFPGAFrequency(50) ++
  new chipyard.config.WithGPIO(address = BigInt(0x64002000L), width = 1) ++
  new WithLEDGPIO ++
  new WithUART ++
  new WithUART1 ++
  new WithSPISDCard ++
  new WithPSDDRMem ++
  new WithJTAG ++
  new WithZCU104DefaultPeripherals ++
  new chipyard.config.WithTLBackingMemory ++
  new WithZCU104SystemModifications ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new freechips.rocketchip.subsystem.WithNMemoryChannels(1)
)

class RocketZCU104Config extends Config(
  new WithZCU104Tweaks ++
  new chipyard.RocketConfig
)

// Alias for Linux bring-up (same as RocketZCU104Config)
class RocketZCU104LinuxBringupConfig extends RocketZCU104Config

// Phase 0B: CEVA BT5.2 DM VERSION read test.
// CEVA_BASE = 0x65000000 (pbus, no address conflict).
// Phase 0B: stub only, no EM SRAM, no IRQ, no VPHY, no Linux.
// Test: read CEVA_BASE+0x4, expect 0x0B000500.
class RocketZCU104Phase0bConfig extends Config(
  new WithCevaBt52Phase0b ++
  new WithZCU104TweaksNoPSLPD ++
  new chipyard.RocketConfig
)

// Diagnostic config: removes the A2 PSLPD MMIO path entirely.
class RocketZCU104JLinkDiagConfig extends Config(
  new WithZCU104TweaksNoPSLPD ++
  new chipyard.RocketConfig
)

// Diagnostic split 1: keep only the MMIO port declaration, but do not connect
// it to the PS LPD bridge. If this alone breaks J-Link halt, the presence of
// the port/topology is enough to trigger the issue.
class RocketZCU104JLinkDiagMMIOPortOnlyConfig extends Config(
  new WithZCU104TweaksNoPSLPD ++
  new WithPSLPDMMIOPort ++
  new chipyard.RocketConfig
)

// Diagnostic split 1b: keep only the MMIO port declaration, and explicitly tie
// it off in the FPGA harness so the default simulation MMIO memory is not
// synthesized into the bitstream.
class RocketZCU104JLinkDiagMMIOPortOnlyCleanConfig extends Config(
  new WithZCU104TweaksNoPSLPD ++
  new WithPSLPDMMIOPort ++
  new WithTiedOffAXI4MMIO ++
  new chipyard.RocketConfig
)

// Diagnostic split 2: keep only the harness binder logic. Without ExtBus this
// binder should be inert; if behavior changes anyway, that points to binder-side
// elaboration or unintended connectivity.
class RocketZCU104JLinkDiagPSLPDConnectOnlyConfig extends Config(
  new WithZCU104TweaksNoPSLPD ++
  new WithPSLPDMem ++
  new chipyard.RocketConfig
)

// Diagnostic split 3: original A2 path, used as the direct comparison point.
class RocketZCU104JLinkDiagFullPSLPDConfig extends Config(
  new WithZCU104TweaksNoPSLPD ++
  new WithPSLPDMem ++
  new WithPSLPDMMIOPort ++
  new chipyard.RocketConfig
)

// Minimal safe config: no Zba/Zbb/Zbs — reduces decode complexity
// For Linux bring-up debugging
class RocketZCU104SafeConfig extends Config(
  new WithZCU104Tweaks ++
  new freechips.rocketchip.rocket.RocketCoreConfig(
    _.copy(useZba = false, useZbb = false, useZbs = false)
  ) ++
  new chipyard.RocketConfig
)

// Minimal Linux-focused config: keep PS DDR, remove subsystem L2/InclusiveCache,
// and disable Zb* to reduce early-boot complexity while preserving the same
// bring-up flow as RocketZCU104Config.
class RocketZCU104NoL2LinuxConfig extends Config(
  new WithZCU104Tweaks ++
  new testchipip.soc.WithNoScratchpads ++
  new freechips.rocketchip.subsystem.WithIncoherentTiles ++
  new freechips.rocketchip.subsystem.WithIncoherentBusTopology ++
  new freechips.rocketchip.subsystem.WithNBanks(0) ++
  new freechips.rocketchip.rocket.RocketCoreConfig(
    _.copy(useZba = false, useZbb = false, useZbs = false)
  ) ++
  new chipyard.RocketConfig
)

// No-DDR fallback: uses Rocket scratchpad TCM (for bring-up / no PS init required)
class WithZCU104TweaksNoDDR extends Config(
  new chipyard.iobinders.WithGPIOPunchthrough ++
  new chipyard.harness.WithAllClocksFromHarnessClockInstantiator ++
  new chipyard.clocking.WithPassthroughClockGenerator ++
  new chipyard.config.WithUniformBusFrequencies(50) ++
  new WithFPGAFrequency(50) ++
  new chipyard.config.WithGPIO(address = BigInt(0x64002000L), width = 1) ++
  new WithLEDGPIO ++
  new WithUART ++
  new WithSPISDCard ++
  new WithJTAG ++
  new WithZCU104DefaultPeripherals ++
  new WithZCU104SystemModifications ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors
)

class RocketZCU104NoDDRConfig extends Config(
  new WithZCU104TweaksNoDDR ++
  new testchipip.soc.WithNoScratchpads ++
  new freechips.rocketchip.subsystem.WithIncoherentBusTopology ++
  new freechips.rocketchip.subsystem.WithNBanks(0) ++
  new freechips.rocketchip.subsystem.WithNoMemPort ++
  new freechips.rocketchip.rocket.With1TinyCore ++
  new chipyard.config.AbstractConfig
)

class WithFPGAFrequency(fMHz: Double) extends Config(
  new chipyard.harness.WithHarnessBinderClockFreqMHz(fMHz) ++
  new chipyard.config.WithSystemBusFrequency(fMHz) ++
  new chipyard.config.WithPeripheryBusFrequency(fMHz) ++
  new chipyard.config.WithControlBusFrequency(fMHz) ++
  new chipyard.config.WithFrontBusFrequency(fMHz) ++
  new chipyard.config.WithMemoryBusFrequency(fMHz)
)

class WithFPGAFreq25MHz  extends WithFPGAFrequency(25)
class WithFPGAFreq50MHz  extends WithFPGAFrequency(50)
class WithFPGAFreq75MHz  extends WithFPGAFrequency(75)
class WithFPGAFreq100MHz extends WithFPGAFrequency(100)
