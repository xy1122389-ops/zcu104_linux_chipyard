// Minimal Rocket-only ZCU104 no-DDR payload.
#include <stdint.h>

#include <platform.h>

#ifndef TL_CLK
#error Must define TL_CLK in MHz
#endif

#define UART_BAUD 115200UL
#define UART_DIV  ((TL_CLK * 1000000UL) / UART_BAUD)
#define REG32(p, i) ((p)[(i) >> 2])
// ZCU104 user LED DS38 is driven by GPIO_LED_0 / GPIO bit 0.
#define DS38_LED_MASK 0x1u
#define HEARTBEAT_DELAY_CYCLES (TL_CLK * 250000UL)

static volatile uint32_t * const uart0 = (void *)(UART_CTRL_ADDR);
static volatile uint32_t * const gpio0 = (void *)(GPIO_CTRL_ADDR);
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
  REG32(gpio0, GPIO_OUTPUT_EN) = DS38_LED_MASK;
}

static inline void ds38_toggle(void)
{
  led_state ^= DS38_LED_MASK;
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

static void delay_cycles(volatile uint64_t cycles)
{
  while (cycles-- > 0) {
    __asm__ __volatile__("nop");
  }
}

int main(void)
{
  uint64_t count = 0;

  uart_init();
  gpio_init();
  uart_puts("zcu104 rocket noddr bit ok\n");
  uart_puts("j9 tx / k9 rx uart active\n");
  uart_puts("ds38 blink armed\n");

  while (1) {
    uart_puts("helloworld rocket_noddr heartbeat=");
    print_dec(count++);
    uart_puts(" ds38=");
    uart_puts((led_state & DS38_LED_MASK) ? "on" : "off");
    uart_puts("\n");
    ds38_toggle();
    delay_cycles(HEARTBEAT_DELAY_CYCLES);
  }

  return 0;
}
