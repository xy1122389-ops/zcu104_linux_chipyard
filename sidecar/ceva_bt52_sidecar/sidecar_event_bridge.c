#include <stddef.h>
#include <stdint.h>

#include "bridge_contract.h"
#include "marker.h"
#include "sidecar_event_bridge.h"
#include "vendor_adapter_boundary.h"

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

static void sidecar_em_write_word(uint32_t word_index, uint32_t value)
{
    em_words[word_index] = value;
    sidecar_fence();
}

int __attribute__((section(".text.ceva_bt52_sidecar_publish_vendor_event")))
ceva_bt52_sidecar_publish_vendor_event(
    const struct ceva_bt52_hci_event_view *event)
{
    uint32_t words[CEVA_BT52_BRIDGE_EVENT_MAX_WORDS];
    uint8_t *bytes = (uint8_t *)words;
    size_t payload_index;
    uint32_t word_index;

    if (event == NULL)
        return CEVA_BT52_VENDOR_EINVAL;
    if (event->payload_len > event->payload_capacity)
        return CEVA_BT52_VENDOR_EINVAL;
    if (event->payload_len > ((CEVA_BT52_BRIDGE_EVENT_MAX_WORDS * CEVA_BT52_BRIDGE_WORD_BYTES) - 3U))
        return CEVA_BT52_VENDOR_EINVAL;
    if (event->payload_len > 0U && event->payload == NULL)
        return CEVA_BT52_VENDOR_EINVAL;

    for (word_index = 0; word_index < CEVA_BT52_BRIDGE_EVENT_MAX_WORDS; word_index++)
        words[word_index] = 0U;

    bytes[0] = CEVA_BT52_HCI_PACKET_TYPE_EVENT;
    bytes[1] = event->event_code;
    bytes[2] = (uint8_t)event->payload_len;

    for (payload_index = 0; payload_index < event->payload_len; payload_index++)
        bytes[payload_index + 3U] = event->payload[payload_index];

    for (word_index = 0; word_index < CEVA_BT52_BRIDGE_EVENT_MAX_WORDS; word_index++)
        sidecar_em_write_word(CEVA_BT52_BRIDGE_EVENT_PAYLOAD_OFFSET + word_index,
                              words[word_index]);

    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_EVENT_CODE, event->event_code);
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_EGRESS_EVENT_READY,
                         CEVA_BT52_MARKER_VALUE_EGRESS_EVENT_READY);
    sidecar_write_marker(CEVA_BT52_MARKER_OFFSET_HCI_SEND_2_HOST,
                         CEVA_BT52_MARKER_VALUE_HCI_SEND_2_HOST);
    sidecar_em_write_word(CEVA_BT52_BRIDGE_EVENT_READY_OFFSET,
                          CEVA_BT52_BRIDGE_EVENT_READY_VALUE);

    return CEVA_BT52_VENDOR_OK;
}
