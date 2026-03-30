#include <stdint.h>

#include <platform.h>

#ifndef TL_CLK
#error Must define TL_CLK in MHz
#endif

#define UART_BAUD 115200UL
#define UART_DIV  ((TL_CLK * 1000000UL) / UART_BAUD)
#define REG32(p, i) ((p)[(i) >> 2])

#define LINUX_CHAIN_PAYLOAD_ADDR   0x88000000UL
#define LINUX_CHAIN_PAYLOAD_SIZE   0x00400000UL
#define LINUX_CHAIN_MANIFEST_ADDR  0x883df000UL
#define LINUX_CHAIN_STACK_BASE     0x883e0000UL
#define LINUX_CHAIN_STACK_TOP      0x88400000UL
#define LINUX_KERNEL_LOAD_ADDR     0x80200000UL
#define LINUX_KERNEL_MAX_SIZE      0x02000000UL
#define LINUX_DTB_LOAD_ADDR        0x82400000UL
#define LINUX_DTB_MAX_SIZE         0x00020000UL
#define LINUX_PAYLOAD_BLOB_ADDR    0x83000000UL
#define LINUX_PAYLOAD_BLOB_MAXSIZE 0x04000000UL
#define LINUX_OPENSBI_LOAD_ADDR    0x88400000UL
#define LINUX_OPENSBI_MAX_SIZE     0x00400000UL
#define LINUX_JUMP_ENTRY_ADDR      LINUX_OPENSBI_LOAD_ADDR
#define LINUX_CHAIN_MANIFEST_MAGIC 0x4c43484d4e465431ULL
#define LINUX_CHAIN_MANIFEST_VER   0x0000000000000002ULL

#define LINUX_FLAG_FIRMWARE_READY  (1ULL << 0)
#define LINUX_FLAG_KERNEL_READY    (1ULL << 0)
#undef LINUX_FLAG_KERNEL_READY
#define LINUX_FLAG_KERNEL_READY    (1ULL << 1)
#define LINUX_FLAG_DTB_READY       (1ULL << 2)
#define LINUX_FLAG_PAYLOAD_READY   (1ULL << 3)
#define LINUX_FLAG_READY_TO_JUMP   (1ULL << 4)
#define LINUX_FLAG_JUMP_ENABLED    (1ULL << 5)

static volatile uint32_t * const uart0 = (void *)(UART_CTRL_ADDR);
static volatile uint32_t * const gpio0 = (void *)(GPIO_CTRL_ADDR);
static uint32_t led_state;

struct linux_chain_manifest {
  uint64_t magic;
  uint64_t version;
  uint64_t flags;
  uint64_t firmware_addr;
  uint64_t firmware_size;
  uint64_t kernel_addr;
  uint64_t kernel_size;
  uint64_t dtb_addr;
  uint64_t dtb_size;
  uint64_t payload_addr;
  uint64_t payload_size;
  uint64_t jump_addr;
};

static volatile const struct linux_chain_manifest * const linux_manifest =
  (volatile const struct linux_chain_manifest *)(uintptr_t)(LINUX_CHAIN_MANIFEST_ADDR);

__attribute__((noinline, used)) void linux_chain_start_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_payload_stage_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_kernel_stage_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_dtb_stage_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_jump_stage_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_count_loop_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void firmware_load_done_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void payload_load_done_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void kernel_load_done_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void dtb_load_done_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_ready_to_jump_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_jump_taken_marker(void) { __asm__ __volatile__("nop"); }
__attribute__((noinline, used)) void linux_jump_blocked_marker(void) { __asm__ __volatile__("nop"); }

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

static void print_hex64(uint64_t value)
{
  int shift;

  uart_puts("0x");
  for (shift = 60; shift >= 0; shift -= 4) {
    const uint64_t digit = (value >> shift) & 0xfu;
    uart_putc((digit < 10u) ? ('0' + digit) : ('a' + (digit - 10u)));
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

static void print_region(const char *label, uint64_t addr, uint64_t size)
{
  uart_puts(label);
  uart_puts(" addr=");
  print_hex64(addr);
  uart_puts(" size=");
  print_hex64(size);
  uart_puts("\n");
}

static uint64_t peek64(uint64_t addr)
{
  volatile const uint64_t * const p = (volatile const uint64_t *)(uintptr_t)addr;
  return *p;
}

static void print_yes_no(const char *label, int yes)
{
  uart_puts(label);
  uart_puts(yes ? " yes\n" : " no\n");
}

static int region_ok(uint64_t addr, uint64_t size, uint64_t expected_base, uint64_t max_size)
{
  if (addr != expected_base) {
    return 0;
  }
  if (size == 0 || size > max_size) {
    return 0;
  }
  return 1;
}

static void print_status_line(const char *label, const char *value)
{
  uart_puts(label);
  uart_puts(value);
  uart_puts("\n");
}

typedef void (*linux_entry_t)(uint64_t, uint64_t, uint64_t);

__attribute__((noreturn)) static void jump_to_linux(uint64_t entry, uint64_t hartid, uint64_t dtb_addr)
{
  linux_entry_t entry_fn = (linux_entry_t)(uintptr_t)entry;
  __asm__ __volatile__("fence.i" ::: "memory");
  entry_fn(hartid, dtb_addr, 0);
  while (1) {
  }
}

int main(void)
{
  uint64_t count = 0;
  uint64_t flags = 0;
  uint64_t firmware_addr = LINUX_OPENSBI_LOAD_ADDR;
  uint64_t firmware_size = 0;
  uint64_t kernel_addr = LINUX_KERNEL_LOAD_ADDR;
  uint64_t kernel_size = 0;
  uint64_t dtb_addr = LINUX_DTB_LOAD_ADDR;
  uint64_t dtb_size = 0;
  uint64_t payload_addr = LINUX_PAYLOAD_BLOB_ADDR;
  uint64_t payload_size = 0;
  uint64_t jump_addr = LINUX_JUMP_ENTRY_ADDR;
  int manifest_ok = 0;
  int ready_to_jump = 0;
  int jump_enabled = 0;
  int firmware_region_valid = 0;
  int kernel_region_valid = 0;
  int dtb_region_valid = 0;
  int payload_region_valid = 0;

  uart_init();
  gpio_init();

  linux_chain_start_marker();
  uart_puts("linux chain start\n");
  print_region("front payload", LINUX_CHAIN_PAYLOAD_ADDR, LINUX_CHAIN_PAYLOAD_SIZE);
  print_region("manifest", LINUX_CHAIN_MANIFEST_ADDR, 0x1000);
  print_region("front stack", LINUX_CHAIN_STACK_BASE, LINUX_CHAIN_STACK_TOP - LINUX_CHAIN_STACK_BASE);

  if (linux_manifest->magic == LINUX_CHAIN_MANIFEST_MAGIC &&
      linux_manifest->version == LINUX_CHAIN_MANIFEST_VER) {
    manifest_ok = 1;
    flags = linux_manifest->flags;
    firmware_addr = linux_manifest->firmware_addr;
    firmware_size = linux_manifest->firmware_size;
    kernel_addr = linux_manifest->kernel_addr;
    kernel_size = linux_manifest->kernel_size;
    dtb_addr = linux_manifest->dtb_addr;
    dtb_size = linux_manifest->dtb_size;
    payload_addr = linux_manifest->payload_addr;
    payload_size = linux_manifest->payload_size;
    jump_addr = linux_manifest->jump_addr;
  }

  print_yes_no("manifest ready", manifest_ok);
  if (manifest_ok) {
    print_status_line("manifest flags=", "");
    print_hex64(flags);
    uart_puts("\n");
  }

  linux_payload_stage_marker();
  uart_puts("load firmware start\n");
  firmware_region_valid = region_ok(firmware_addr, firmware_size, LINUX_OPENSBI_LOAD_ADDR, LINUX_OPENSBI_MAX_SIZE);
  if (manifest_ok && (flags & LINUX_FLAG_FIRMWARE_READY)) {
    firmware_load_done_marker();
    print_yes_no("firmware prepared", 1);
    print_region("firmware", firmware_addr, firmware_size);
    uart_puts("firmware first64=");
    print_hex64(peek64(firmware_addr));
    uart_puts("\n");
  } else {
    print_yes_no("firmware prepared", 0);
    print_region("firmware", firmware_addr, firmware_size);
  }
  print_yes_no("firmware range valid", firmware_region_valid);

  linux_payload_stage_marker();
  uart_puts("load payload start\n");
  payload_region_valid = (payload_size == 0) || region_ok(payload_addr, payload_size, LINUX_PAYLOAD_BLOB_ADDR, LINUX_PAYLOAD_BLOB_MAXSIZE);
  if (manifest_ok && (flags & LINUX_FLAG_PAYLOAD_READY)) {
    payload_load_done_marker();
    print_yes_no("payload prepared", 1);
    print_region("payload blob", payload_addr, payload_size);
    uart_puts("payload first64=");
    print_hex64(peek64(payload_addr));
    uart_puts("\n");
  } else {
    print_yes_no("payload prepared", 0);
    print_region("payload blob", payload_addr, payload_size);
  }
  print_yes_no("payload range valid", payload_region_valid);

  linux_kernel_stage_marker();
  uart_puts("load kernel start\n");
  kernel_region_valid = region_ok(kernel_addr, kernel_size, LINUX_KERNEL_LOAD_ADDR, LINUX_KERNEL_MAX_SIZE);
  if (manifest_ok && (flags & LINUX_FLAG_KERNEL_READY)) {
    kernel_load_done_marker();
    print_yes_no("kernel prepared", 1);
    print_region("kernel", kernel_addr, kernel_size);
    uart_puts("kernel first64=");
    print_hex64(peek64(kernel_addr));
    uart_puts("\n");
  } else {
    print_yes_no("kernel prepared", 0);
    print_region("kernel", kernel_addr, kernel_size);
  }
  print_yes_no("kernel range valid", kernel_region_valid);

  linux_dtb_stage_marker();
  uart_puts("load dtb start\n");
  dtb_region_valid = region_ok(dtb_addr, dtb_size, LINUX_DTB_LOAD_ADDR, LINUX_DTB_MAX_SIZE);
  if (manifest_ok && (flags & LINUX_FLAG_DTB_READY)) {
    dtb_load_done_marker();
    print_yes_no("dtb prepared", 1);
    print_region("dtb", dtb_addr, dtb_size);
    uart_puts("dtb first64=");
    print_hex64(peek64(dtb_addr));
    uart_puts("\n");
  } else {
    print_yes_no("dtb prepared", 0);
    print_region("dtb", dtb_addr, dtb_size);
  }
  print_yes_no("dtb range valid", dtb_region_valid);

  linux_jump_stage_marker();
  jump_enabled = manifest_ok && ((flags & LINUX_FLAG_JUMP_ENABLED) != 0);
  ready_to_jump = manifest_ok &&
                  ((flags & LINUX_FLAG_FIRMWARE_READY) != 0) &&
                  ((flags & LINUX_FLAG_KERNEL_READY) != 0) &&
                  ((flags & LINUX_FLAG_DTB_READY) != 0) &&
                  firmware_region_valid &&
                  kernel_region_valid &&
                  dtb_region_valid &&
                  payload_region_valid &&
                  (jump_addr == firmware_addr);
  if (ready_to_jump) {
    linux_ready_to_jump_marker();
  }
  uart_puts("jump linux entry\n");
  uart_puts("linux entry addr=");
  print_hex64(jump_addr);
  uart_puts("\n");
  print_yes_no("ready to jump", ready_to_jump);
  print_yes_no("jump enabled", jump_enabled);
  if (!manifest_ok) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " manifest invalid");
  } else if (!(flags & LINUX_FLAG_FIRMWARE_READY)) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " firmware not ready");
  } else if (!(flags & LINUX_FLAG_KERNEL_READY)) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " kernel not ready");
  } else if (!(flags & LINUX_FLAG_DTB_READY)) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " dtb not ready");
  } else if (!firmware_region_valid) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " firmware region invalid");
  } else if (!kernel_region_valid) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " kernel region invalid");
  } else if (!dtb_region_valid) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " dtb region invalid");
  } else if (!payload_region_valid) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " payload region invalid");
  } else if (jump_addr != firmware_addr) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " jump addr mismatch");
  } else if (!jump_enabled) {
    linux_jump_blocked_marker();
    print_status_line("jump blocked:", " jump disabled by manifest");
  } else {
    linux_jump_taken_marker();
    print_status_line("jump action:", " taking linux entry");
    jump_to_linux(jump_addr, 0, dtb_addr);
  }
  uart_puts("jump not enabled yet\n");

  while (1) {
    linux_count_loop_marker();
    uart_puts("linux chain idle count=");
    print_dec(count++);
    uart_puts("\n");
    led_toggle();
    delay_cycles(TL_CLK * 50000UL);
  }

  return 0;
}
