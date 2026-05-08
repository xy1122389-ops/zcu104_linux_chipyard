#include <stdint.h>

#include <platform.h>

#ifndef TL_CLK
#error Must define TL_CLK in MHz
#endif

#define UART_BAUD 115200UL
#define UART_DIV  ((TL_CLK * 1000000UL) / UART_BAUD)
#define REG32(p, i) ((p)[(i) >> 2])

#define CEVA_DM_VERSION_ADDR  ((volatile uint32_t *)0x65000004UL)
#define CEVA_BT_VERSION_ADDR  ((volatile uint32_t *)0x65000404UL)
#define CEVA_BLE_VERSION_ADDR ((volatile uint32_t *)0x65000804UL)

static volatile uint32_t * const uart0 = (void *)(UART_CTRL_ADDR);
static volatile uint32_t * const gpio0 = (void *)(GPIO_CTRL_ADDR);
static uint32_t led_state;

volatile uint32_t probe_magic;
volatile uint32_t probe_dm_version;
volatile uint32_t probe_bt_version;
volatile uint32_t probe_ble_version;

__attribute__((noinline, used)) void demo_target_entry_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void demo_target_loop_marker(void) { __asm__ __volatile__("nop"); }

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

static inline void led_toggle(void)
{
  led_state ^= 1u;
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

static void print_hex64(uint64_t value)
{
  int shift;

  uart_puts("0x");
  for (shift = 60; shift >= 0; shift -= 4) {
    const uint64_t digit = (value >> shift) & 0xfu;
    uart_putc((digit < 10u) ? ('0' + digit) : ('a' + (digit - 10u)));
  }
}

static uint64_t read_pc(void)
{
  uint64_t pc;
  __asm__ __volatile__("auipc %0, 0" : "=r"(pc));
  return pc;
}

static void delay_cycles(volatile uint64_t cycles)
{
  while (cycles-- > 0) {
    __asm__ __volatile__("nop");
  }
}

int main(uint64_t a0, uint64_t a1, uint64_t a2)
{
  uint64_t count = 0;

  uart_init();
  gpio_init();

  probe_magic = 0x53334230u;
  probe_dm_version = *CEVA_DM_VERSION_ADDR;
  probe_bt_version = *CEVA_BT_VERSION_ADDR;
  probe_ble_version = *CEVA_BLE_VERSION_ADDR;

  demo_target_entry_marker();
  uart_puts("demo target entered\n");
  uart_puts("demo a0=");
  print_hex64(a0);
  uart_puts("\n");
  uart_puts("demo a1=");
  print_hex64(a1);
  uart_puts("\n");
  uart_puts("demo a2=");
  print_hex64(a2);
  uart_puts("\n");
  uart_puts("demo pc=");
  print_hex64(read_pc());
  uart_puts("\n");
  uart_puts("ceva dm=");
  print_hex64(probe_dm_version);
  uart_puts("\n");
  uart_puts("ceva bt=");
  print_hex64(probe_bt_version);
  uart_puts("\n");
  uart_puts("ceva ble=");
  print_hex64(probe_ble_version);
  uart_puts("\n");

  while (1) {
    demo_target_loop_marker();
    uart_puts("demo count=");
    print_dec(count++);
    uart_puts("\n");
    led_toggle();
    delay_cycles(TL_CLK * 50000UL);
  }

  return 0;
}
