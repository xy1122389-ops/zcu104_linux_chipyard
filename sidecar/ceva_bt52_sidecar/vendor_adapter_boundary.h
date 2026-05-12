#ifndef CEVA_BT52_VENDOR_ADAPTER_BOUNDARY_H
#define CEVA_BT52_VENDOR_ADAPTER_BOUNDARY_H

#include <stddef.h>
#include <stdint.h>

#define CEVA_BT52_VENDOR_ADAPTER_ABI_VERSION 1U

enum ceva_bt52_vendor_gate_status {
    CEVA_BT52_VENDOR_GATE_CLOSED = 0,
    CEVA_BT52_VENDOR_GATE_ASSET_PRESENT = 1,
    CEVA_BT52_VENDOR_GATE_APPROVED_FOR_LINK = 2,
};

enum ceva_bt52_vendor_result {
    CEVA_BT52_VENDOR_OK = 0,
    CEVA_BT52_VENDOR_EAGAIN = 1,
    CEVA_BT52_VENDOR_EINVAL = -1,
    CEVA_BT52_VENDOR_ENOSYS = -2,
    CEVA_BT52_VENDOR_EIO = -3,
};

struct ceva_bt52_hci_cmd_view {
    uint16_t opcode;
    const uint8_t *payload;
    uint16_t payload_len;
};

struct ceva_bt52_hci_event_view {
    uint8_t event_code;
    uint8_t *payload;
    uint16_t payload_capacity;
    uint16_t payload_len;
};

struct ceva_bt52_vendor_host_ops {
    uint32_t abi_version;
    enum ceva_bt52_vendor_gate_status gate_status;
    void (*write_marker)(uint64_t offset, uint64_t value);
    int (*em_read)(uint32_t offset, void *buffer, size_t length);
    int (*em_write)(uint32_t offset, const void *buffer, size_t length);
    int (*raise_sw_irq)(void);
    uint64_t (*read_timebase)(void);
};

struct ceva_bt52_vendor_runtime_ops {
    uint32_t abi_version;
    int (*probe)(const struct ceva_bt52_vendor_host_ops *host_ops);
    int (*init)(void);
    int (*poll)(void);
    int (*handle_hci_cmd)(const struct ceva_bt52_hci_cmd_view *cmd,
                          struct ceva_bt52_hci_event_view *event);
};

#endif
