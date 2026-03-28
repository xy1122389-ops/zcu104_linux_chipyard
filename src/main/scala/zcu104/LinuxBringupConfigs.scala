package chipyard.fpga.zcu104

import sys.process._

import org.chipsalliance.cde.config.Config

import freechips.rocketchip.devices.tilelink.BootROMLocated
import freechips.rocketchip.resources.DTSTimebase
import freechips.rocketchip.subsystem.SystemBusKey
import freechips.rocketchip.util.SystemFileName
import sifive.blocks.devices.spi.PeripherySPIKey
import sifive.fpgashells.shell.xilinx.ZCU104ShellPMOD

/**
  * Parallel Linux bringup config for ZCU104.
  *
  * This intentionally leaves RocketZCU104Config untouched. By placing this
  * fragment to the left of WithZCU104Tweaks, it overrides the existing
  * BootROM path and timebase while reusing the exact same peripheral, DDR,
  * UART, GPIO, and JTAG topology as the working baremetal build.
  */
class WithZCU104LinuxBringupBootROM extends Config((site, here, up) => {
  case DTSTimebase => BigInt((1e6).toLong)
  case BootROMLocated(x) => up(BootROMLocated(x), site).map { p =>
    val freqMHz = (site(SystemBusKey).dtsFrequency.get / (1000 * 1000)).toLong
    val make = s"make -C fpga/src/main/resources/zcu104/sdboot-linux PBUS_CLK=${freqMHz} bin"
    require(make.! == 0, "Failed to build ZCU104 Linux handoff bootrom")
    p.copy(
      // Enter the Linux handoff main path directly. The sdboot-linux image keeps
      // a sentinel loop at 0x10000, while main starts at 0x10020.
      hang = 0x10020,
      contentFileName = SystemFileName("./fpga/src/main/resources/zcu104/sdboot-linux/build/sdboot.bin")
    )
  }
})

class WithZCU104DisableSDIO extends Config((site, here, up) => {
  case PeripherySPIKey => Nil
  case ZCU104ShellPMOD => "NONE"
})

class RocketZCU104LinuxBringupConfig extends Config(
  new WithZCU104LinuxBringupBootROM ++
  new chipyard.config.WithNoDebug ++
  new WithZCU104Tweaks ++
  new chipyard.RocketConfig
)

class RocketZCU104LinuxBringupDebugConfig extends Config(
  new WithZCU104LinuxBringupBootROM ++
  new WithZCU104DisableSDIO ++
  new WithZCU104Tweaks ++
  new chipyard.RocketConfig
)
