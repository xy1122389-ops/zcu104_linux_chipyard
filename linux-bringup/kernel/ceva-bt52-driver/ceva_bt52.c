// SPDX-License-Identifier: GPL-2.0
/*
 * CEVA RivieraWaves BT5.2 HCI MMIO driver for ZCU104 Rocket RISC-V
 *
 * Implements a Linux HCI platform driver for the CEVA rw-dm-bt52 IP
 * integrated into Chipyard FPGA (ZCU104 + Rocket RV64GC).
 *
 * Hardware transport:
 *   - CEVA registers mapped at MMIO base (0x65000000, from DTS)
 *   - EM BRAM accessible at MMIO base + 0x10000 (Phase 1A RTL addition)
 *   - PLIC IRQ 1 (dm_sw_irq, from DTS: interrupts = <1>)
 *
 * HCI exchange protocol (baremetal-verified, Phase 0R + Phase 1C):
 *   CPU→FW: Write HCI cmd to EM[EM_CMD_WORD..], set EM[EM_CMD_FLAG]=READY,
 *            SWINT_REQ → dm_sw_irq → PLIC → handler
 *   FW→CPU: FW writes HCI event to EM[EM_EVT_WORD..],
 *            sets EM[EM_EVT_FLAG]=READY → dm_sw_irq → PLIC IRQ
 *
 * Hardware verified phases:
 *   0G-0M: BT init, CLKN, rwip_init MMIO
 *   0N-0P: ETPTR, EM accessible, HCI reset equivalent
 *   0Q:    PLIC IRQ1 path (dm_sw_irq → PLIC pending → claim)
 *   0R:    Linux HCI driver skeleton (DDR mailbox)
 *   1A:    EM MMIO window (CPU direct EM access, Phase 1A RTL)
 *   1B:    Firmware boot inspection via EM
 *   1C:    HCI Reset via EM exchange table
 *
 * Author: ZCU104 Chipyard CEVA BT bringup
 */

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/slab.h>
#include <linux/skbuff.h>
#include <linux/workqueue.h>
#include <linux/delay.h>
#include <linux/completion.h>

#include <net/bluetooth/bluetooth.h>
#include <net/bluetooth/hci_core.h>

#define DRIVER_NAME     "ceva-bt52"
#define DRIVER_VERSION  "0.1"

/* EM MMIO layout (from RTL Phase 1A: haddr[16]=1 → EM BRAM) */
#define CEVA_REG_SIZE       0x10000     /* 64KB: CEVA registers */
#define CEVA_EM_OFFSET      0x10000     /* EM window offset in ioremap region */
#define CEVA_EM_SIZE        0x10000     /* 64KB: EM BRAM */

/* DM registers (byte offsets from MMIO base) */
#define DM_RWDMCNTL         0x0000
#define DM_VERSION          0x0004
#define DM_INTCNTL0         0x0008
#define DM_INTSTAT0         0x000C
#define DM_INTCNTL1         0x0018
#define DM_INTSTAT1         0x001C
#define DM_INTACK1          0x0020
#define DM_ETPTR            0x002C
#define DM_TIMGENCNTL       0x00E0

/* BT registers */
#define BT_RWBTCNTL         0x0800
#define BT_INTCNTL0         0x080C
#define BT_INTSTAT0         0x0810
#define BT_INTACK0          0x0814
#define BT_CURRENTRXDESC    0x0828

/* Register bit fields */
#define DM_MASTER_SOFT_RST  BIT(31)
#define DM_SWINT_REQ        BIT(27)
#define DM_SWINTMSK         BIT(3)
#define DM_SWINTSTAT        BIT(3)
#define DM_SWINTACK         BIT(3)
#define DM_CLKNINTMSK       BIT(0)
#define DM_CLKNINTSTAT      BIT(0)
#define DM_CLKNINTACK       BIT(0)
#define BT_RWBTEN           BIT(8)
#define BT_NWINSIZE_MASK    0x3F
#define BT_NWINSIZE_DEFAULT 13
#define BT_CXTXBSYENA       BIT(11)
#define BT_CXRXBSYENA       BIT(10)
#define BT_CXDNABORT        BIT(9)

/* Init values (verified Phase 0M/0P) */
#define TIMGENCNTL_VAL      0x011800C8
#define BT_RWBTCNTL_INIT    (BT_CXTXBSYENA | BT_CXRXBSYENA | BT_CXDNABORT | \
                             (BT_NWINSIZE_DEFAULT & BT_NWINSIZE_MASK))
#define BT_INTCNTL0_INIT    0x00010016

/* EM exchange layout (word indices, verified Phase 1C) */
#define EM_CMD_WORD         64      /* HCI cmd buffer at EM word 64 (byte 0x100) */
#define EM_CMD_FLAG_WORD    72      /* cmd-ready flag */
#define EM_EVT_WORD         96      /* HCI event buffer at EM word 96 (byte 0x180) */
#define EM_EVT_FLAG_WORD    73      /* event-ready flag */
#define EM_CMD_READY        0xA5A5A5A5
#define EM_EVT_READY        0x5A5A5A5A

/* Maximum HCI packet sizes in EM (words) */
#define EM_CMD_MAX_WORDS    8       /* 32 bytes max HCI cmd */
#define EM_EVT_MAX_WORDS    16      /* 64 bytes max HCI event */

struct ceva_bt {
    struct hci_dev      *hdev;
    struct platform_device *pdev;
    void __iomem        *base;      /* CEVA register base */
    void __iomem        *em_base;   /* EM BRAM window (base + 0x10000) */
    int                  irq;
    spinlock_t           lock;
    struct work_struct   rx_work;
    struct sk_buff_head  rx_queue;
    bool                 running;
};

/* ====== Low-level register accessors ====== */

static inline u32 dm_read(struct ceva_bt *cbt, unsigned int reg)
{
    return readl(cbt->base + reg);
}

static inline void dm_write(struct ceva_bt *cbt, unsigned int reg, u32 val)
{
    writel(val, cbt->base + reg);
}

static inline u32 em_read_word(struct ceva_bt *cbt, unsigned int word_idx)
{
    return readl(cbt->em_base + word_idx * 4);
}

static inline void em_write_word(struct ceva_bt *cbt, unsigned int word_idx, u32 val)
{
    writel(val, cbt->em_base + word_idx * 4);
}

/* ====== Hardware init/cleanup (Phase 0M/0P sequence) ====== */

static int ceva_bt_hw_init(struct ceva_bt *cbt)
{
    int i, clkn = 0;
    u32 val;

    /* DM MASTER_SOFT_RST */
    dm_write(cbt, DM_RWDMCNTL, DM_MASTER_SOFT_RST);
    for (i = 0; i < 1000; i++) {
        if (!(dm_read(cbt, DM_RWDMCNTL) & DM_MASTER_SOFT_RST))
            break;
        udelay(1);
    }

    /* TIMGENCNTL */
    dm_write(cbt, DM_TIMGENCNTL, TIMGENCNTL_VAL);

    /* ETPTR = 0 (Exchange Table at EM start) */
    dm_write(cbt, DM_ETPTR, 0);

    /* BT block init */
    dm_write(cbt, BT_INTCNTL0, BT_INTCNTL0_INIT);
    dm_write(cbt, BT_INTACK0, 0xFFFFFFFF);
    dm_write(cbt, BT_CURRENTRXDESC, 0);
    dm_write(cbt, BT_RWBTCNTL, BT_RWBTCNTL_INIT | BT_RWBTEN);

    /* Enable CLKN interrupt for CLKN polling */
    val = dm_read(cbt, DM_INTCNTL1) | DM_CLKNINTMSK;
    dm_write(cbt, DM_INTCNTL1, val);
    dm_write(cbt, DM_INTACK1, DM_CLKNINTACK);

    /* Wait for CLKN (verify BT core is running) */
    for (i = 0; i < 10000 && clkn < 5; i++) {
        if (dm_read(cbt, DM_INTSTAT1) & DM_CLKNINTSTAT) {
            clkn++;
            dm_write(cbt, DM_INTACK1, DM_CLKNINTACK);
        }
        udelay(1);
    }

    if (clkn < 5) {
        dev_err(&cbt->pdev->dev, "BT core not running (CLKN %d/5)\n", clkn);
        return -ETIMEDOUT;
    }

    dev_info(&cbt->pdev->dev, "BT core running (CLKN %d/5 OK)\n", clkn);

    /* Enable SWINT for HCI transport */
    val = dm_read(cbt, DM_INTCNTL1) | DM_SWINTMSK;
    dm_write(cbt, DM_INTCNTL1, val);

    return 0;
}

static void ceva_bt_hw_stop(struct ceva_bt *cbt)
{
    /* Disable RWBTEN */
    dm_write(cbt, BT_RWBTCNTL, BT_RWBTCNTL_INIT);
    /* Disable interrupts */
    dm_write(cbt, DM_INTCNTL1, 0);
}

/* ====== HCI transport (EM MMIO exchange table) ====== */

static void ceva_bt_rx_work(struct work_struct *work)
{
    struct ceva_bt *cbt = container_of(work, struct ceva_bt, rx_work);
    struct sk_buff *skb;
    u32 words[EM_EVT_MAX_WORDS];
    u8 *buf;
    int i, len;

    /* Read event from EM event buffer */
    for (i = 0; i < EM_EVT_MAX_WORDS; i++)
        words[i] = em_read_word(cbt, EM_EVT_WORD + i);

    /* Clear event-ready flag */
    em_write_word(cbt, EM_EVT_FLAG_WORD, 0);

    /* Parse HCI event header */
    buf = (u8 *)words;
    if (buf[0] != HCI_EVENT_PKT) {
        dev_err(&cbt->pdev->dev, "Unexpected HCI type 0x%02x\n", buf[0]);
        return;
    }

    len = buf[2] + 3;   /* HCI event: type(1) + code(1) + plen(1) + params */
    if (len > sizeof(words)) {
        dev_err(&cbt->pdev->dev, "HCI event too large: %d\n", len);
        return;
    }

    skb = bt_skb_alloc(len, GFP_KERNEL);
    if (!skb)
        return;

    hci_skb_pkt_type(skb) = HCI_EVENT_PKT;
    skb_put_data(skb, buf + 1, len - 1);    /* skip type byte */

    dev_dbg(&cbt->pdev->dev, "HCI event: code=0x%02x len=%d\n", buf[1], len);

    hci_recv_frame(cbt->hdev, skb);
}

/* ====== IRQ handler ====== */

static irqreturn_t ceva_bt_irq(int irq, void *dev_id)
{
    struct ceva_bt *cbt = dev_id;
    u32 intstat1 = dm_read(cbt, DM_INTSTAT1);

    if (!(intstat1 & DM_SWINTSTAT))
        return IRQ_NONE;

    /* Acknowledge SWINT */
    dm_write(cbt, DM_INTACK1, DM_SWINTACK);

    /* Check if firmware wrote an HCI event */
    if (em_read_word(cbt, EM_EVT_FLAG_WORD) == EM_EVT_READY)
        schedule_work(&cbt->rx_work);

    return IRQ_HANDLED;
}

/* ====== HCI device callbacks ====== */

static int ceva_bt_open(struct hci_dev *hdev)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);
    int ret;

    dev_info(&cbt->pdev->dev, "ceva_bt_open: initializing hardware\n");

    ret = ceva_bt_hw_init(cbt);
    if (ret)
        return ret;

    cbt->running = true;
    dev_info(&cbt->pdev->dev, "ceva_bt_open: OK\n");
    return 0;
}

static int ceva_bt_close(struct hci_dev *hdev)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);

    dev_info(&cbt->pdev->dev, "ceva_bt_close\n");
    cbt->running = false;
    ceva_bt_hw_stop(cbt);
    cancel_work_sync(&cbt->rx_work);
    skb_queue_purge(&cbt->rx_queue);
    return 0;
}

static int ceva_bt_send_frame(struct hci_dev *hdev, struct sk_buff *skb)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);
    u32 words[EM_CMD_MAX_WORDS] = {0};
    u8 *buf = (u8 *)words;
    int len = skb->len;
    int i;

    if (hci_skb_pkt_type(skb) != HCI_COMMAND_PKT) {
        dev_err(&cbt->pdev->dev, "Unsupported HCI pkt type: %d\n",
                hci_skb_pkt_type(skb));
        kfree_skb(skb);
        return -EINVAL;
    }

    if (len + 1 > sizeof(words)) {
        dev_err(&cbt->pdev->dev, "HCI cmd too large: %d\n", len);
        kfree_skb(skb);
        return -EINVAL;
    }

    /* Pack: type byte + cmd payload */
    buf[0] = HCI_COMMAND_PKT;
    skb_copy_from_linear_data(skb, buf + 1, len);

    /* Write cmd to EM */
    for (i = 0; i < EM_CMD_MAX_WORDS; i++)
        em_write_word(cbt, EM_CMD_WORD + i, words[i]);

    /* Set cmd-ready flag */
    em_write_word(cbt, EM_CMD_FLAG_WORD, EM_CMD_READY);

    /* Notify firmware via SWINT_REQ */
    dm_write(cbt, DM_RWDMCNTL, DM_SWINT_REQ);

    dev_dbg(&cbt->pdev->dev, "HCI cmd sent to EM (len=%d)\n", len + 1);

    kfree_skb(skb);
    return 0;
}

static int ceva_bt_setup(struct hci_dev *hdev)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);
    u32 ver;

    ver = dm_read(cbt, DM_VERSION);
    dev_info(&cbt->pdev->dev, "CEVA DM VERSION = 0x%08X\n", ver);

    hdev->manufacturer = 0x0057;    /* CEVA/RivieraWaves */
    return 0;
}

/* ====== Platform driver probe/remove ====== */

static int ceva_bt_probe(struct platform_device *pdev)
{
    struct ceva_bt *cbt;
    struct hci_dev *hdev;
    struct resource *res;
    resource_size_t base_phys;
    int irq, ret;

    dev_info(&pdev->dev, "CEVA BT5.2 probe\n");

    /* Get MMIO resource (DTS: reg = <0x65000000 0x20000>) */
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (!res) {
        dev_err(&pdev->dev, "No MMIO resource\n");
        return -ENODEV;
    }
    base_phys = res->start;

    /* Get IRQ (DTS: interrupts = <1>, PLIC IRQ 1) */
    irq = platform_get_irq(pdev, 0);
    if (irq < 0) {
        dev_err(&pdev->dev, "No IRQ resource\n");
        return irq;
    }

    cbt = devm_kzalloc(&pdev->dev, sizeof(*cbt), GFP_KERNEL);
    if (!cbt)
        return -ENOMEM;

    cbt->pdev = pdev;
    cbt->irq  = irq;
    spin_lock_init(&cbt->lock);
    INIT_WORK(&cbt->rx_work, ceva_bt_rx_work);
    skb_queue_head_init(&cbt->rx_queue);

    /* ioremap the full 0x20000 region (registers + EM window) */
    cbt->base = devm_ioremap(&pdev->dev, base_phys, CEVA_REG_SIZE + CEVA_EM_SIZE);
    if (!cbt->base) {
        dev_err(&pdev->dev, "ioremap failed for 0x%llx\n", (u64)base_phys);
        return -ENOMEM;
    }
    cbt->em_base = cbt->base + CEVA_EM_OFFSET;

    dev_info(&pdev->dev, "MMIO base: 0x%llx (regs) + 0x%llx (EM)\n",
             (u64)base_phys, (u64)(base_phys + CEVA_EM_OFFSET));

    /* Allocate HCI device */
    hdev = hci_alloc_dev();
    if (!hdev) {
        dev_err(&pdev->dev, "hci_alloc_dev failed\n");
        return -ENOMEM;
    }

    hdev->bus       = HCI_VIRTUAL;     /* No specific bus type for MMIO */
    hdev->dev_type  = HCI_PRIMARY;
    hci_set_drvdata(hdev, cbt);
    SET_HCIDEV_DEV(hdev, &pdev->dev);

    hdev->open      = ceva_bt_open;
    hdev->close     = ceva_bt_close;
    hdev->send      = ceva_bt_send_frame;
    hdev->setup     = ceva_bt_setup;

    cbt->hdev = hdev;

    /* Register IRQ */
    ret = devm_request_irq(&pdev->dev, irq, ceva_bt_irq,
                           IRQF_TRIGGER_HIGH, DRIVER_NAME, cbt);
    if (ret) {
        dev_err(&pdev->dev, "request_irq(%d) failed: %d\n", irq, ret);
        hci_free_dev(hdev);
        return ret;
    }

    /* Register HCI device */
    ret = hci_register_dev(hdev);
    if (ret < 0) {
        dev_err(&pdev->dev, "hci_register_dev failed: %d\n", ret);
        hci_free_dev(hdev);
        return ret;
    }

    platform_set_drvdata(pdev, cbt);
    dev_info(&pdev->dev, "CEVA BT5.2 registered as %s (IRQ %d, EM@0x%llx)\n",
             hdev->name, irq, (u64)(base_phys + CEVA_EM_OFFSET));

    return 0;
}

static int ceva_bt_remove(struct platform_device *pdev)
{
    struct ceva_bt *cbt = platform_get_drvdata(pdev);

    dev_info(&pdev->dev, "CEVA BT5.2 remove\n");
    hci_unregister_dev(cbt->hdev);
    hci_free_dev(cbt->hdev);
    return 0;
}

static const struct of_device_id ceva_bt_of_match[] = {
    { .compatible = "ceva,rw-dm-bt52" },
    { }
};
MODULE_DEVICE_TABLE(of, ceva_bt_of_match);

static struct platform_driver ceva_bt_driver = {
    .probe  = ceva_bt_probe,
    .remove = ceva_bt_remove,
    .driver = {
        .name           = DRIVER_NAME,
        .of_match_table = ceva_bt_of_match,
    },
};

module_platform_driver(ceva_bt_driver);

MODULE_DESCRIPTION("CEVA RivieraWaves BT5.2 HCI MMIO driver (ZCU104 Rocket RISC-V)");
MODULE_AUTHOR("ZCU104 Chipyard CEVA BT bringup");
MODULE_LICENSE("GPL v2");
MODULE_VERSION(DRIVER_VERSION);
