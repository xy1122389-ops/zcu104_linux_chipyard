// CEVA BT5.2 Phase 0B -- Chipyard/ZCU104 MMIO integration
//
// Exposes a TLRegisterNode on pbus at CEVA_BASE = 0x65000000.
// Phase 0B goal: CPU reads CEVA_BASE+0x4 and gets back 0x0B000500
// (the expected CEVA DM VERSION value).
//
// Phase 0B constraints:
//   - Register value hardcoded (no external RTL block, no real AHB bus)
//   - em_ready, radio_in, VPHY: not connected (Phase 0B)
//   - IRQ not connected (Phase 0B)
//
// NOTE: The chipyard_fpga sbt project does NOT include chiselSettings
// (no addCompilerPlugin for chisel-plugin). Therefore, we must avoid
// any code requiring the Chisel compiler plugin: no "extends Bundle",
// no IO(), no Input()/Output() in field declarations.
// All Chisel constructs used here (RegField.r, UInt literal, WireInit)
// follow the same pattern as PSLPDDebug.scala which already works.
//
package chipyard.fpga.zcu104

import chisel3._
import org.chipsalliance.cde.config.{Config, Parameters}
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.regmapper._
import freechips.rocketchip.subsystem._
import freechips.rocketchip.tilelink._
import testchipip.soc.{SubsystemInjector, SubsystemInjectorKey}

// ── 1. LazyModule wrapper ─────────────────────────────────────────────────────
// Lives on pbus. TLRegisterNode maps CEVA_BASE+0x4 → hardcoded 0x0B000500.
// Phase 0B: value is a compile-time constant (the AHB DM VERSION field).
// Phase 1 will replace this with a real TL-to-AHB bridge to the external CEVA RTL.
class CevaDmWrapper(beatBytes: Int)(implicit p: Parameters) extends LazyModule {

  val CEVA_BASE: Long = 0x65000000L
  val CEVA_MASK: Long = 0x1FFFFL   // 128 KB window

  val device = new SimpleDevice("ceva-dm", Seq("ceva,rw-dm-bt52"))

  val node = TLRegisterNode(
    address     = Seq(AddressSet(CEVA_BASE, CEVA_MASK)),
    device      = device,
    beatBytes   = beatBytes,
    concurrency = 1
  )

  lazy val module = new CevaDmWrapperImpl(this)

  class CevaDmWrapperImpl(outer: CevaDmWrapper) extends LazyModuleImp(outer) {
    // Phase 0B: CEVA DM AHB VERSION register value.
    // Real RTL returns 0x0B000500 at AHB offset 0x4.
    val DM_VERSION = WireInit(0x0B000500.U(32.W))

    // TileLink register map: offset 0x04 returns DM_VERSION (read-only).
    outer.node.regmap(
      0x04 -> Seq(RegField.r(32, DM_VERSION))
    )
  }
}

// ── 3. SubsystemInjector ──────────────────────────────────────────────────────
// Registers CevaDmWrapper on pbus and couples it to the TileLink fabric.
case object CevaPhase0bInjector extends SubsystemInjector((p, baseSubsystem) => {
  implicit val q: Parameters = p
  val tlbus   = baseSubsystem.locateTLBusWrapper(PBUS)
  val wrapper = tlbus { LazyModule(new CevaDmWrapper(tlbus.beatBytes)(p)) }
  tlbus.coupleTo("ceva-dm") {
    wrapper.node := TLFragmenter(tlbus, Some("CevaDm")) := _
  }
})

// ── 4. Config mixin ───────────────────────────────────────────────────────────
class WithCevaBt52Phase0b extends Config((site, here, up) => {
  case SubsystemInjectorKey => up(SubsystemInjectorKey) + CevaPhase0bInjector
})
