package chipyard.fpga.zcu102

import sys.process._

import org.chipsalliance.cde.config.{Config, Parameters}
import freechips.rocketchip.subsystem.{SystemBusKey, PeripheryBusKey}
import freechips.rocketchip.devices.debug.{DebugModuleKey, ExportDebug, JTAG}
import freechips.rocketchip.devices.tilelink.{BootROMLocated}
import freechips.rocketchip.util.{SystemFileName}

import sifive.blocks.devices.spi.{PeripherySPIKey, SPIParams}
import sifive.blocks.devices.uart.{PeripheryUARTKey, UARTParams}

import sifive.fpgashells.shell.{DesignKey}
import sifive.fpgashells.shell.xilinx.{ZCU102ShellPMOD}

import testchipip.serdes.{SerialTLKey}

import chipyard._
import chipyard.harness._

class WithZCU102DefaultPeripherals extends Config((site, here, up) => {
  // ZCU102 UART: E13/F13 pins (Bank 64), SPI on PMOD0
  case PeripheryUARTKey => List(UARTParams(address = BigInt(0x64000000L)))
  case PeripherySPIKey  => List(SPIParams(rAddress = BigInt(0x64001000L)))
  case ZCU102ShellPMOD  => "SDIO"
})

class WithZCU102SystemModifications extends Config((site, here, up) => {
  case BootROMLocated(x) => up(BootROMLocated(x), site).map { p =>
    val freqMHz = (site(SystemBusKey).dtsFrequency.get / (1000 * 1000)).toLong
    val make = s"make -C fpga/src/main/resources/zcu102/sdboot PBUS_CLK=${freqMHz} bin"
    require(make.! == 0, "Failed to build ZCU102 bootrom")
    p.copy(hang = 0x10000, contentFileName = SystemFileName(s"./fpga/src/main/resources/zcu102/sdboot/build/sdboot.bin"))
  }
  case SerialTLKey => Nil
})

class WithZCU102Tweaks extends Config(
  new chipyard.harness.WithAllClocksFromHarnessClockInstantiator ++
  new chipyard.clocking.WithPassthroughClockGenerator ++
  new chipyard.config.WithUniformBusFrequencies(50) ++
  new WithFPGAFrequency(50) ++
  new WithUART ++
  new WithSPISDCard ++
  new WithJTAG ++
  new WithZCU102DefaultPeripherals ++
  new WithZCU102SystemModifications ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors ++
  new freechips.rocketchip.subsystem.WithNMemoryChannels(1)
)

class RocketZCU102Config extends Config(
  new WithZCU102Tweaks ++
  new chipyard.RocketConfig
)

// NoDDR: no external memory, use scratchpad / small TCM for bring-up
class WithZCU102TweaksNoDDR extends Config(
  new chipyard.harness.WithAllClocksFromHarnessClockInstantiator ++
  new chipyard.clocking.WithPassthroughClockGenerator ++
  new chipyard.config.WithUniformBusFrequencies(50) ++
  new WithFPGAFrequency(50) ++
  new WithUART ++
  new WithSPISDCard ++
  new WithJTAG ++
  new WithZCU102DefaultPeripherals ++
  new WithZCU102SystemModifications ++
  new freechips.rocketchip.subsystem.WithoutTLMonitors
)

class RocketZCU102NoDDRConfig extends Config(
  new WithZCU102TweaksNoDDR ++
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
