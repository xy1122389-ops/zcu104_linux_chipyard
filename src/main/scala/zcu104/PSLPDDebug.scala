package chipyard.fpga.zcu104

import chisel3._
import chisel3.util._
import chisel3.util.experimental.BoringUtils
import org.chipsalliance.cde.config.{Config, Field, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.devices.tilelink._
import freechips.rocketchip.regmapper._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.tilelink._
import testchipip.soc.{SubsystemInjector, SubsystemInjectorKey}

object PSLPDDebugNames {
  val clear                 = "pslpd_dbg_clear"
  val lastArAddr            = "pslpd_dbg_last_araddr"
  val lastArMeta            = "pslpd_dbg_last_armeta"
  val lastAwAddr            = "pslpd_dbg_last_awaddr"
  val lastAwMeta            = "pslpd_dbg_last_awmeta"
  val lastWstrb             = "pslpd_dbg_last_wstrb"
  val lastResp              = "pslpd_dbg_last_resp"
  val status                = "pslpd_dbg_status"
}

case class PSLPDDebugParams(
  address: BigInt = BigInt(0x64004000L),
  slaveWhere: TLBusWrapperLocation = PBUS)

case object PSLPDDebugKey extends Field[Option[PSLPDDebugParams]](Some(PSLPDDebugParams()))

case object PSLPDDebugInjector extends SubsystemInjector((p, baseSubsystem) => {
  p(PSLPDDebugKey).map { params =>
    implicit val q: Parameters = p
    val tlbus = baseSubsystem.locateTLBusWrapper(params.slaveWhere)
    val device = new SimpleDevice("pslpd-debug", Seq("ucb-bar,pslpd-debug0"))

    tlbus {
      val node = TLRegisterNode(
        address = Seq(AddressSet(params.address, 4096 - 1)),
        device = device,
        beatBytes = tlbus.beatBytes,
        concurrency = 1)

      tlbus.coupleTo("pslpd-debug") { node := TLFragmenter(tlbus, Some("PSLPDDebug")) := _ }

      InModuleBody {
        val clearPulse = WireInit(false.B)
        BoringUtils.addSource(clearPulse, PSLPDDebugNames.clear)

        val lastArAddr = WireInit(0.U(64.W))
        val lastArMeta = WireInit(0.U(16.W))
        val lastAwAddr = WireInit(0.U(64.W))
        val lastAwMeta = WireInit(0.U(16.W))
        val lastWstrb  = WireInit(0.U(8.W))
        val lastResp   = WireInit(0.U(8.W))
        val status     = WireInit(0.U(8.W))

        BoringUtils.addSink(lastArAddr, PSLPDDebugNames.lastArAddr)
        BoringUtils.addSink(lastArMeta, PSLPDDebugNames.lastArMeta)
        BoringUtils.addSink(lastAwAddr, PSLPDDebugNames.lastAwAddr)
        BoringUtils.addSink(lastAwMeta, PSLPDDebugNames.lastAwMeta)
        BoringUtils.addSink(lastWstrb,  PSLPDDebugNames.lastWstrb)
        BoringUtils.addSink(lastResp,   PSLPDDebugNames.lastResp)
        BoringUtils.addSink(status,     PSLPDDebugNames.status)

        node.regmap(
          0x00 -> Seq(RegField.r(64, "h50534c5044444247".U)), // "PSLPDDBG"
          0x08 -> Seq(RegField.w(1, RegWriteFn((valid, data) => {
            clearPulse := valid && data(0)
            true.B
          }))),
          0x10 -> Seq(RegField.r(64, Cat(0.U(56.W), status))),
          0x18 -> Seq(RegField.r(64, lastArAddr)),
          0x20 -> Seq(RegField.r(16, lastArMeta)),
          0x28 -> Seq(RegField.r(64, lastAwAddr)),
          0x30 -> Seq(RegField.r(16, lastAwMeta)),
          0x38 -> Seq(RegField.r(8, lastWstrb)),
          0x40 -> Seq(RegField.r(8, lastResp))
        )
      }
    }
  }
})

class WithPSLPDDebugRegs extends Config((site, here, up) => {
  case SubsystemInjectorKey => up(SubsystemInjectorKey) + PSLPDDebugInjector
})
