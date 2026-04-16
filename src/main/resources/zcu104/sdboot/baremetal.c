// Minimal ZCU104 bootrom payload that runs directly on the RISC-V CPU.
#include <stdint.h>

#include <platform.h>

#ifndef TL_CLK
#error Must define TL_CLK in MHz
#endif

#define UART_BAUD 115200UL
#define UART_DIV  ((TL_CLK * 1000000UL) / UART_BAUD)
#define REG32(p, i) ((p)[(i) >> 2])
#define NEWBIT_TAG "[NEWBIT] "
#define DDR_FIXED_WORDS 4u
#define DDR_LINEAR_WORDS 16u
#define DDR_LINEAR_OFFSET_WORDS 16u

static volatile uint32_t * const uart0 = (void *)(UART_CTRL_ADDR);
static volatile uint32_t * const gpio0 = (void *)(GPIO_CTRL_ADDR);
static volatile uint32_t * const ddr0 = (void *)(MEMORY_MEM_ADDR + 0x7F00000u);
static uint32_t led_state;

static inline void uart_init(void)
{
  REG32(uart0, UART_REG_DIV) = UART_DIV;
  REG32(uart0, UART_REG_RXCTRL) = 0;
  REG32(uart0, UART_REG_TXCTRL) = UART_TXEN;
}

static inline void gpio_init(void)
{
  led_state = 0;
  REG32(gpio0, GPIO_INPUT_EN) = 0;
  REG32(gpio0, GPIO_PULLUP_EN) = 0;
  REG32(gpio0, GPIO_IOF_EN) = 0;
  REG32(gpio0, GPIO_OUTPUT_XOR) = 0;
  REG32(gpio0, GPIO_OUTPUT_VAL) = led_state;
  REG32(gpio0, GPIO_OUTPUT_EN) = 1;
}

static inline void led_set(uint32_t value)
{
  led_state = value & 1u;
  REG32(gpio0, GPIO_OUTPUT_VAL) = led_state;
}

static void uart_putc(char c)
{
  while ((int32_t)REG32(uart0, UART_REG_TXFIFO) < 0) {
  }
  REG32(uart0, UART_REG_TXFIFO) = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *s)
{
  while (*s != '\0') {
    if (*s == '\n') {
      uart_putc('\r');
    }
    uart_putc(*s++);
  }
}

static void uart_put_tag(const char *s)
{
  uart_puts(NEWBIT_TAG);
  uart_puts(s);
}

static void print_dec(uint64_t value)
{
  char buffer[21];
  int i = 0;

  if (value == 0) {
    uart_putc('0');
    return;
  }

  while (value != 0) {
    buffer[i++] = '0' + (value % 10);
    value /= 10;
  }

  while (i > 0) {
    uart_putc(buffer[--i]);
  }
}

static void print_hex32(uint32_t value)
{
  int shift;

  uart_puts("0x");
  for (shift = 28; shift >= 0; shift -= 4) {
    const uint32_t digit = (value >> shift) & 0xfu;
    uart_putc((digit < 10u) ? ('0' + digit) : ('a' + (digit - 10u)));
  }
}

static int ddr_report_mismatch(const char *label, volatile uint32_t *addr, uint32_t expected, uint32_t actual)
{
  uart_puts(label);
  uart_puts(" fail addr=");
  print_hex32((uint32_t)(uintptr_t)addr);
  uart_puts(" exp=");
  print_hex32(expected);
  uart_puts(" got=");
  print_hex32(actual);
  uart_puts("\n");
  return -1;
}

static int ddr_test_fixed(void)
{
  static const uint32_t patterns[DDR_FIXED_WORDS] = {
    0x11223344u,
    0xa5a55a5au,
    0xdeadbeefu,
    0xc001d00du,
  };
  uint32_t i;

  for (i = 0; i < DDR_FIXED_WORDS; ++i) {
    ddr0[i] = patterns[i];
  }

  __asm__ __volatile__("fence rw, rw" ::: "memory");

  for (i = 0; i < DDR_FIXED_WORDS; ++i) {
    const uint32_t actual = ddr0[i];
    if (actual != patterns[i]) {
      return ddr_report_mismatch("ddr fixed", &ddr0[i], patterns[i], actual);
    }
  }

  uart_puts("ddr fixed pass\n");
  return 0;
}

static int ddr_test_linear(void)
{
  volatile uint32_t * const base = ddr0 + DDR_LINEAR_OFFSET_WORDS;
  uint32_t i;

  for (i = 0; i < DDR_LINEAR_WORDS; ++i) {
    base[i] = 0x5a5a0000u ^ (0x01010101u * i);
  }

  __asm__ __volatile__("fence rw, rw" ::: "memory");

  for (i = 0; i < DDR_LINEAR_WORDS; ++i) {
    const uint32_t expected = 0x5a5a0000u ^ (0x01010101u * i);
    const uint32_t actual = base[i];
    if (actual != expected) {
      return ddr_report_mismatch("ddr linear", &base[i], expected, actual);
    }
  }

  uart_puts("ddr linear pass\n");
  return 0;
}

static void delay_cycles(volatile uint64_t cycles)
{
  while (cycles-- > 0) {
    __asm__ __volatile__("nop");
  }
}

static void delay_ms(uint32_t ms)
{
  delay_cycles((uint64_t)TL_CLK * 1000ULL * (uint64_t)ms);
}

static void startup_blink_sequence(void)
{
  uint32_t i;

  for (i = 0; i < 2u; ++i) {
    led_set(1u);
    delay_ms(80u);
    led_set(0u);
    delay_ms(80u);
  }

  delay_ms(240u);
}

/* DTB address where XSDB preloads the device tree */
#define DTB_ADDR     0x84000000UL
#define DTB_MAGIC    0xEDFE0DD0UL  /* 0xD00DFEED in little-endian memory */

/* Sentinel: after DDR test we clear 0x80000000; XSDB payload write will set a
   non-zero value.  We also accept any non-zero, non-0x11223344 (test pattern)
   value so we don't accidentally trigger on leftover test data.

   CRITICAL: The sentinel must NOT be at MEMORY_MEM_ADDR (0x80000000)
   because the DDR test writes there, populating the D-cache.
   Subsequent reads from the polling loop would hit the cache and
   never see firmware data written by XSDB through the non-coherent
   ARM path.  Using offset 0x1000 avoids this cache-coherence issue:
   the first read is a cold cache miss that fetches directly from DDR. */
#define PAYLOAD_SENTINEL_ADDR  ((volatile uint32_t *)(MEMORY_MEM_ADDR + 0x1000))
#define DDR_TEST_PATTERN       0x11223344u

static void jump_to_payload(unsigned long hart, unsigned long dtb)
{
  void (*entry)(unsigned long, unsigned long) =
    (void (*)(unsigned long, unsigned long))MEMORY_MEM_ADDR;

  /* fence to make sure all prior stores/loads are visible */
  __asm__ __volatile__("fence rw, rw" ::: "memory");

  uart_put_tag("jumping to 0x80000000  a0=");
  print_hex32((uint32_t)hart);
  uart_puts(" a1=");
  print_hex32((uint32_t)dtb);
  uart_puts("\n");

  entry(hart, dtb);
  __builtin_unreachable();
}

int main(void)
{
  uint64_t count = 0;
  int ddr_ok = 1;

  uart_init();
  gpio_init();
  uart_put_tag("ds39-uart-build-4 (ddr-test-safe)\n");
  uart_put_tag("bootrom=zcu104/sdboot/baremetal.c led=DS39 gpio=0x64002000 uart=0x64000000\n");
  startup_blink_sequence();
  uart_put_tag("ddr test start\n");
  if (ddr_test_fixed() != 0) {
    ddr_ok = 0;
  }
  if (ddr_test_linear() != 0) {
    ddr_ok = 0;
  }
  if (ddr_ok) {
    uart_put_tag("ddr test pass\n");
  } else {
    uart_put_tag("ddr test fail\n");
  }

  /* Do NOT clear sentinel — the sentinel is at 0x80001000 which is
     outside the DDR test area.  On cold boot the D-cache line for
     0x80001000 has not been allocated, so the first read will be a
     cache miss that fetches directly from DDR.  If firmware was
     preloaded by XSDB, we see non-zero immediately and jump. */
  __asm__ __volatile__("fence rw, rw" ::: "memory");

  uart_put_tag("polling 0x80001000 for payload (XSDB preload)...\n");

  while (1) {
    uint32_t val = *PAYLOAD_SENTINEL_ADDR;

    if (val != 0 && val != DDR_TEST_PATTERN) {
      /* Payload detected — wait a bit for the full write to finish */
      uart_put_tag("payload detected: ");
      print_hex32(val);
      uart_puts("\n");

      /* Wait 3 seconds to let XSDB finish writing DTB etc. */
      led_set(1u);
      delay_ms(3000u);

      /* Check DTB magic */
      volatile uint32_t *dtb_ptr = (volatile uint32_t *)DTB_ADDR;
      uint32_t dtb_val = *dtb_ptr;
      uart_put_tag("dtb @0x84000000 = ");
      print_hex32(dtb_val);
      uart_puts("\n");

      jump_to_payload(0, DTB_ADDR);
    }

    /* Heartbeat while waiting */
    if ((count & 0x3Fu) == 0) {
      uart_put_tag("alive ");
      print_dec(count);
      uart_puts("\n");
    }
    count++;
    led_set((count >> 3) & 1u);
    delay_ms(50u);
  }

  return 0;
}
