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
static volatile uint32_t * const ddr0 = (void *)(MEMORY_MEM_ADDR);
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

int main(void)
{
  uint64_t count = 0;
  int ddr_ok = 1;

  uart_init();
  gpio_init();
  uart_put_tag("ds39-uart-build-1\n");
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

  while (1) {
    uart_put_tag("alive ");
    print_dec(count++);
    uart_puts("\n");
    led_set(1u);
    delay_ms(150u);
    led_set(0u);
    delay_ms(850u);
  }

  return 0;
}
