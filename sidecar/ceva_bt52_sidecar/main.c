#include <stdint.h>

#include "bridge_contract.h"
#include "marker.h"

static volatile uint64_t *const marker_base =
    (volatile uint64_t *)CEVA_BT52_SIDECAR_MARKER_BASE;

static void sidecar_fence(void)
{
    __asm__ volatile("fence rw, rw" ::: "memory");
}

static void sidecar_write_marker(uint64_t offset, uint64_t value)
{
    volatile uint64_t *slot = marker_base + (offset / CEVA_BT52_SIDECAR_MARKER_SLOT_BYTES);

    *slot = value;
    sidecar_fence();
}

static void sidecar_publish_static_contract(void)
{
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_OPCODE,
                         CEVA_BT52_HCI_OPCODE_RESET);
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_EVENT_CODE,
                         CEVA_BT52_HCI_EVENT_COMMAND_COMPLETE);
}

void sidecar_panic(uint64_t code) __attribute__((noreturn));
void sidecar_start(void) __attribute__((noreturn));

void sidecar_panic(uint64_t code)
{
    sidecar_write_marker(SIDECAR_PANIC_CODE_OFFSET, SIDECAR_PANIC_CODE);
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_SEQ, code);

    for (;;) {
        sidecar_fence();
    }
}

void sidecar_start(void)
{
    uint64_t loop_count = 0;

    sidecar_write_marker(SIDECAR_BOOT_MAGIC_OFFSET, SIDECAR_BOOT_MAGIC);
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_SIDECAR_START,
                         CEVA_BT52_MARKER_VALUE_SIDECAR_START);
    sidecar_write_marker(SIDECAR_MAIN_ENTER_OFFSET, SIDECAR_MAIN_ENTER);
    sidecar_publish_static_contract();
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_INGRESS_READY,
                         CEVA_BT52_MARKER_VALUE_INGRESS_READY);

    for (;;) {
        sidecar_write_marker(SIDECAR_LOOP_ALIVE_OFFSET, loop_count++);
        sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_EVENT_CODE,
                             SIDECAR_LOOP_ALIVE);
        sidecar_fence();
    }
}
