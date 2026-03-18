package chipyard.fpga.zcu104

import chisel3._
import chisel3.util.{Cat, Fill, log2Ceil}

import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.diplomacy.{InModuleBody, LazyRawModuleImp}
import freechips.rocketchip.prci.ClockSinkNode

import sifive.fpgashells.shell.xilinx._
import sifive.fpgashells.ip.xilinx.PowerOnResetFPGAOnly
import sifive.fpgashells.ip.xilinx.bscan2.BUFGCE
import sifive.fpgashells.shell._
import sifive.fpgashells.clocks._

class ZCU104DirectHelloWorldUART(clockFreqHz: Int, baudRate: Int) extends Module {
  val txd = IO(Output(Bool())).suggestName("txd")

  private val messageBytes = Seq(
    0x68.U(8.W),
    0x65.U(8.W),
    0x6c.U(8.W),
    0x6c.U(8.W),
    0x6f.U(8.W),
    0x77.U(8.W),
    0x6f.U(8.W),
    0x72.U(8.W),
    0x6c.U(8.W),
    0x64.U(8.W),
    0x0a.U(8.W)
  )

  private val message = VecInit(messageBytes)
  private val lastCharIndex = (messageBytes.length - 1).U(log2Ceil(messageBytes.length).W)
  private val cyclesPerBit = ((clockFreqHz + (baudRate / 2)) / baudRate)
  require(cyclesPerBit > 1, s"Unsupported UART divider for $clockFreqHz Hz / $baudRate baud")

  val charIndex = RegInit(0.U(log2Ceil(messageBytes.length).W))
  val bitCounter = RegInit(0.U(log2Ceil(cyclesPerBit).W))
  val bitsRemaining = RegInit(0.U(4.W))
  val shiftReg = RegInit(0x3ff.U(10.W))

  when(bitsRemaining === 0.U) {
    shiftReg := Cat(1.U(1.W), message(charIndex), 0.U(1.W))
    bitsRemaining := 10.U
    bitCounter := (cyclesPerBit - 1).U
    charIndex := Mux(charIndex === lastCharIndex, 0.U, charIndex + 1.U)
  }.elsewhen(bitCounter === 0.U) {
    shiftReg := Cat(1.U(1.W), shiftReg(9, 1))
    bitsRemaining := bitsRemaining - 1.U
    bitCounter := (cyclesPerBit - 1).U
  }.otherwise {
    bitCounter := bitCounter - 1.U
  }

  txd := shiftReg(0)
}

class ZCU104DirectChipTopStub extends RawModule {
  override def desiredName = "ChipTop"
}

class ZCU104DirectUARTTestHarness(override implicit val p: Parameters) extends ZCU104ShellBasicOverlays {
  def dp = designParameters

  val pllReset = InModuleBody { Wire(Bool()) }

  require(dp(ClockInputOverlayKey).nonEmpty)
  val sysClkNode = dp(ClockInputOverlayKey)(0).place(ClockInputDesignInput()).overlayOutput.node
  val rawClockSink = ClockSinkNode(freqMHz = 125)
  rawClockSink := sysClkNode

  override lazy val module = new ZCU104DirectUARTTestHarnessImp(this)
}

class ZCU104DirectUARTTestHarnessImp(_outer: ZCU104DirectUARTTestHarness) extends LazyRawModuleImp(_outer) {
  val uart_rx = IO(Input(Bool())).suggestName("uart_rx")
  val uart_tx = IO(Output(Bool())).suggestName("uart_tx")

  private val sysclk = _outer.rawClockSink.in.head._1.clock
  private val powerOnReset = PowerOnResetFPGAOnly(sysclk)
  _outer.sdc.addAsyncPath(Seq(powerOnReset))
  _outer.pllReset := powerOnReset

  val uartClockBuf = Module(new BUFGCE)
  uartClockBuf.suggestName("uart_clock_bufg")
  uartClockBuf.CE := true.B
  uartClockBuf.I := sysclk.asBool

  val uartClock = uartClockBuf.O.asClock
  val chipTopStub = Module(new ZCU104DirectChipTopStub)
  val uartHello = withClockAndReset(uartClock, powerOnReset.asAsyncReset) {
    Module(new ZCU104DirectHelloWorldUART(clockFreqHz = 125000000, baudRate = 115200))
  }

  uart_tx := uartHello.txd
  dontTouch(uart_rx)
}
