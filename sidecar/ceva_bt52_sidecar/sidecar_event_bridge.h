#ifndef CEVA_BT52_SIDECAR_EVENT_BRIDGE_H
#define CEVA_BT52_SIDECAR_EVENT_BRIDGE_H

#include "vendor_adapter_boundary.h"

int ceva_bt52_sidecar_publish_vendor_event(
    const struct ceva_bt52_hci_event_view *event);

#endif
