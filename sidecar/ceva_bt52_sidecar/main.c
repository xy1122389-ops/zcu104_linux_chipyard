#include <stdint.h>

#include "bridge_contract.h"
#include "marker.h"

static volatile uint64_t *const marker_base =
    (volatile uint64_t *)CEVA_BT52_SIDECAR_MARKER_BASE;
static volatile uint32_t *const em_words =
    (volatile uint32_t *)CEVA_BT52_BRIDGE_EM_BASE;

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

static uint32_t sidecar_em_read_word(uint32_t word_index)
{
    uint32_t value = em_words[word_index];

    sidecar_fence();
    return value;
}

static void sidecar_em_write_word(uint32_t word_index, uint32_t value)
{
    em_words[word_index] = value;
    sidecar_fence();
}

static uint32_t sidecar_hci_packet_type(uint32_t word0)
{
    return word0 & 0xffU;
}

static uint32_t sidecar_hci_opcode(uint32_t word0)
{
    return (word0 >> 8) & 0xffffU;
}

static void sidecar_poll_ingress(void)
{
    uint32_t cmd_ready = sidecar_em_read_word(CEVA_BT52_BRIDGE_CMD_READY_OFFSET);
    uint32_t word0;
    uint32_t packet_type;
    uint32_t opcode;

    if (cmd_ready != CEVA_BT52_BRIDGE_CMD_READY_VALUE)
        return;

    word0 = sidecar_em_read_word(CEVA_BT52_BRIDGE_CMD_PAYLOAD_OFFSET);
    packet_type = sidecar_hci_packet_type(word0);
    opcode = sidecar_hci_opcode(word0);
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_OPCODE, opcode);

    if (packet_type != CEVA_BT52_HCI_PACKET_TYPE_COMMAND) {
        sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_ERROR, packet_type);
        sidecar_em_write_word(CEVA_BT52_BRIDGE_CMD_READY_OFFSET, 0U);
        return;
    }

    if (opcode == CEVA_BT52_HCI_OPCODE_RESET) {
        sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_RX_CMD_0C03,
                             CEVA_BT52_MARKER_VALUE_RX_CMD_0C03);
    }

    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_CMD_CONSUMED,
                         CEVA_BT52_MARKER_VALUE_CMD_CONSUMED);
    sidecar_em_write_word(CEVA_BT52_BRIDGE_CMD_READY_OFFSET, 0U);
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
        sidecar_poll_ingress();
        sidecar_write_marker(SIDECAR_LOOP_ALIVE_OFFSET, loop_count++);
        sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_EVENT_CODE,
                             SIDECAR_LOOP_ALIVE);
        sidecar_fence();
    }
}
