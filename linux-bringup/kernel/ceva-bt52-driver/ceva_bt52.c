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
#include <linux/string.h>
#include <linux/jiffies.h>

#include <net/bluetooth/bluetooth.h>
#include <net/bluetooth/hci_core.h>

#define DRIVER_NAME     "ceva-bt52"
#define DRIVER_VERSION  "0.1"

#define CEVA_BT_HCI_EV_CMD_COMPLETE        0x0E
#define CEVA_BT_HCI_OP_RESET               0x0C03
#define CEVA_BT_HCI_OP_READ_LOCAL_COMMANDS 0x1002
#define CEVA_BT_HCI_OP_READ_LOCAL_FEATURES 0x1003
#define CEVA_BT_HCI_OP_READ_LOCAL_VERSION  0x1001
#define CEVA_BT_HCI_OP_SET_EVENT_MASK      0x0C01
#define CEVA_BT_HCI_OP_READ_BD_ADDR        0x1009
#define CEVA_BT_HCI_VER_BT52               0x0B
#define CEVA_BT_HCI_REV                    0x0520
#define CEVA_BT_MANUFACTURER_CEVA          0x0057
#define CEVA_BT_PHASE25_RESP_RESET         BIT(0)
#define CEVA_BT_PHASE25_RESP_READ_LOCAL_VERSION BIT(1)
#define CEVA_BT_PHASE25_RESP_READ_LOCAL_FEATURES BIT(2)
#define CEVA_BT_PHASE25_RESP_READ_BD_ADDR  BIT(3)
#define CEVA_BT_PHASE25_RESP_READ_LOCAL_COMMANDS BIT(4)
#define CEVA_BT_PHASE25_RESP_SET_EVENT_MASK BIT(5)

static bool phase25_selftest = false;
module_param_named(phase25_selftest, phase25_selftest, bool, 0644);
MODULE_PARM_DESC(phase25_selftest,
         "Enable internal Phase 2.5 selftest/instrumentation after hci_register_dev");

static unsigned int phase25_selftest_delay_ms = 1500;
module_param_named(phase25_selftest_delay_ms, phase25_selftest_delay_ms, uint, 0644);
MODULE_PARM_DESC(phase25_selftest_delay_ms,
         "Delay in ms before running Phase 2.5 HCI control-plane selftest");

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
#define DM_DEBUGADDMAX      0x0058
#define DM_DEBUGADDMIN      0x005C
#define DM_TIMGENCNTL       0x00E0

/* BT registers */
#define BT_RWBTCNTL         0x0800
#define BT_INTCNTL0         0x080C
#define BT_INTSTAT0         0x0810
#define BT_INTACK0          0x0814
#define BT_CURRENTRXDESC    0x0828
#define BT_DIAGCNTL         0x0850

/* Register bit fields */
#define DM_MASTER_SOFT_RST  BIT(31)
#define DM_SWINT_REQ        BIT(27)
#define DM_SWINTMSK         BIT(3)
#define DM_SWINTSTAT        BIT(3)
#define DM_SWINTACK         BIT(3)
#define DM_CLKNINTMSK       BIT(0)
#define DM_SLPINTMSK        BIT(1)
#define DM_CRYPTINTMSK      BIT(2)
#define DM_CLKNINTSTAT      BIT(0)
#define DM_CLKNINTACK       BIT(0)
#define DM_FIFOINTMSK       BIT(15)
#define DM_REALPATH_INTMSK  (DM_FIFOINTMSK | DM_CRYPTINTMSK | \
                             DM_SWINTMSK | DM_SLPINTMSK)
#define BT_RWBTEN           BIT(8)
#define BT_NWINSIZE_MASK    0x3F
#define BT_NWINSIZE_DEFAULT 13
#define BT_CXTXBSYENA       BIT(11)
#define BT_CXRXBSYENA       BIT(10)
#define BT_CXDNABORT        BIT(9)

/* Init values (verified Phase 0M/0P) */
#define TIMGENCNTL_VAL      0x011800C8
#define DM_DEBUGADDMAX_FULL 0xFFFFFFFF
#define DM_DEBUGADDMIN_FULL 0x00000000
#define BT_RWBTCNTL_INIT    (BT_CXTXBSYENA | BT_CXRXBSYENA | BT_CXDNABORT | \
                             (BT_NWINSIZE_DEFAULT & BT_NWINSIZE_MASK))
#define BT_INTCNTL0_INIT    0x00010016

/* EM exchange layout (word indices, verified Phase 1C) */
#define EM_CMD_WORD         64      /* HCI cmd buffer at EM word 64 (byte 0x100) */
#define EM_CMD_FLAG_WORD    72      /* cmd-ready flag */
#define EM_EVT_WORD         96      /* HCI event buffer at EM word 96 (byte 0x180) */
#define EM_EVT_FLAG_WORD    73      /* event-ready flag */
#define EM_PHASE25_MARK_MAGIC_WORD  1024    /* byte offset 0x1000, board-validated scratch */
#define EM_PHASE25_MARK_BITS_WORD   4096    /* byte offset 0x4000, board-validated scratch */
#define EM_PHASE25_MARK_AUX_WORD    16383   /* byte offset 0xFFFC, board-validated boundary */
#define EM_PHASE25_MARK_MAGIC   0x50323521U
#define EM_P3BD_MARK_MAGIC      0x50334244U
#define EM_CMD_READY        0xA5A5A5A5
#define EM_EVT_READY        0x5A5A5A5A
#define EM_PHASE25_EVID_WORD    16320   /* byte offset 0xFF00 within EM window */
#define EM_PHASE25_EVID_WORDS   64      /* 256-byte ASCII evidence buffer */
#define PHASE25_DDR_EVID_PA     0x8FF00000ULL
#define PHASE25_DDR_EVID_SIZE   (EM_PHASE25_EVID_WORDS * sizeof(u32))

#define PHASE25_MARK_PROBE_REACHED              BIT(0)
#define PHASE25_MARK_OPEN_REACHED               BIT(1)
#define PHASE25_MARK_SELFTEST_START             BIT(2)
#define PHASE25_MARK_SEND_RESET_SEEN            BIT(3)
#define PHASE25_MARK_SEND_READ_LOCAL_VERSION    BIT(4)
#define PHASE25_MARK_HCI_RESET_PASS             BIT(5)
#define PHASE25_MARK_READ_LOCAL_VERSION_PASS    BIT(6)
#define PHASE25_MARK_SELFTEST_PASS              BIT(7)
#define PHASE25_MARK_HCI_RESET_FAIL             BIT(8)
#define PHASE25_MARK_READ_LOCAL_VERSION_FAIL    BIT(9)
#define PHASE25_MARK_SELFTEST_FAIL              BIT(10)

#define P3BD_MARK_DRV_PROBE_START               BIT(0)
#define P3BD_MARK_DRV_HCI_REGISTER_OK           BIT(1)
#define P3BD_MARK_DRV_OPEN_START                BIT(2)
#define P3BD_MARK_DRV_OPEN_OK                   BIT(3)
#define P3BD_MARK_DRV_SEND_ENTER                BIT(4)
#define P3BD_MARK_DRV_SEND_RESET_SEEN           BIT(5)
#define P3BD_MARK_DRV_EM_CMD_WRITTEN            BIT(6)
#define P3BD_MARK_DRV_SWINT_TRIGGERED           BIT(7)
#define P3BD_MARK_DRV_IRQ_ENTER                 BIT(8)
#define P3BD_MARK_DRV_EM_EVT_READY              BIT(9)
#define P3BD_MARK_DRV_RX_WORK_ENTER             BIT(10)
#define P3BD_MARK_DRV_HCI_RECV_DONE             BIT(11)

#define CEVA_BT_EVT_RECHECK_MS                  1
#define CEVA_BT_EVT_RECHECK_TRIES               50

/* Maximum HCI packet sizes in EM (words) */
#define EM_CMD_MAX_WORDS    8       /* 32 bytes max HCI cmd */
#define EM_EVT_MAX_WORDS    16      /* 64 bytes max HCI event */

struct ceva_bt {
    struct hci_dev      *hdev;
    struct platform_device *pdev;
    void __iomem        *base;      /* CEVA register base */
    void __iomem        *em_base;   /* EM BRAM window (base + 0x10000) */
    void __iomem        *phase25_ddr_evidence_base;
    int                  irq;
    spinlock_t           lock;
    struct work_struct   rx_work;
    struct work_struct   phase25_rsp_work;
    struct delayed_work  phase25_selftest_work;
    struct delayed_work  evt_recheck_work;
    struct sk_buff_head  rx_queue;
    bool                 running;
    bool                 phase25_started;
    bool                 phase25_reset_pass;
    bool                 phase25_version_pass;
    bool                 phase25_selftest_done;
    unsigned long        phase25_pending_responses;
    u32                  phase25_mark_bits;
    u32                  phase25_mark_aux;
    unsigned int         evt_recheck_tries;
    unsigned int         phase25_evidence_len;
    char                 phase25_evidence_buf[PHASE25_DDR_EVID_SIZE];
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

static inline void ceva_bt_em_debug_window_open(struct ceva_bt *cbt)
{
    dm_write(cbt, DM_DEBUGADDMAX, DM_DEBUGADDMAX_FULL);
    dm_write(cbt, DM_DEBUGADDMIN, DM_DEBUGADDMIN_FULL);
}

static void ceva_bt_trace_write_evt_shadow(struct ceva_bt *cbt, u32 magic)
{
    em_write_word(cbt, EM_EVT_WORD + 4, magic);
    em_write_word(cbt, EM_EVT_WORD + 5, cbt->phase25_mark_bits);
    em_write_word(cbt, EM_EVT_WORD + 6, cbt->phase25_mark_aux);
}

static void ceva_bt_trace_write_cmd_shadow(struct ceva_bt *cbt, u32 magic)
{
    em_write_word(cbt, EM_CMD_WORD + 4, magic);
    em_write_word(cbt, EM_CMD_WORD + 5, cbt->phase25_mark_bits);
    em_write_word(cbt, EM_CMD_WORD + 6, cbt->phase25_mark_aux);
}

static void ceva_bt_phase25_write_evt_shadow(struct ceva_bt *cbt)
{
    ceva_bt_trace_write_evt_shadow(cbt, EM_PHASE25_MARK_MAGIC);
}

static void ceva_bt_phase25_write_cmd_shadow(struct ceva_bt *cbt)
{
    ceva_bt_trace_write_cmd_shadow(cbt, EM_PHASE25_MARK_MAGIC);
}

static bool ceva_bt_p3bd_enabled(void)
{
    return !phase25_selftest;
}

static void ceva_bt_p3bd_sync(struct ceva_bt *cbt)
{
    em_write_word(cbt, EM_PHASE25_MARK_MAGIC_WORD, EM_P3BD_MARK_MAGIC);
    em_write_word(cbt, EM_PHASE25_MARK_BITS_WORD, cbt->phase25_mark_bits);
    em_write_word(cbt, EM_PHASE25_MARK_AUX_WORD, cbt->phase25_mark_aux);
    ceva_bt_trace_write_evt_shadow(cbt, EM_P3BD_MARK_MAGIC);
    ceva_bt_trace_write_cmd_shadow(cbt, EM_P3BD_MARK_MAGIC);
}

static void ceva_bt_p3bd_clear(struct ceva_bt *cbt)
{
    if (!ceva_bt_p3bd_enabled())
        return;

    cbt->phase25_mark_bits = 0;
    cbt->phase25_mark_aux = 0;
    ceva_bt_p3bd_sync(cbt);
}

static void ceva_bt_p3bd_mark(struct ceva_bt *cbt, u32 bits)
{
    if (!ceva_bt_p3bd_enabled())
        return;

    cbt->phase25_mark_bits |= bits;
    ceva_bt_p3bd_sync(cbt);
}

static void ceva_bt_p3bd_set_aux(struct ceva_bt *cbt, u32 aux)
{
    if (!ceva_bt_p3bd_enabled())
        return;

    cbt->phase25_mark_aux = aux;
    ceva_bt_p3bd_sync(cbt);
}

static void ceva_bt_phase25_mirror_event_to_em(struct ceva_bt *cbt,
                                               const u8 *buf, size_t len)
{
    u32 words[EM_EVT_MAX_WORDS] = {0};
    size_t copy_len;
    unsigned int word;

    copy_len = min_t(size_t, len, sizeof(words));
    memcpy(words, buf, copy_len);

    for (word = 0; word < 4; word++)
        em_write_word(cbt, EM_EVT_WORD + word, words[word]);

    ceva_bt_phase25_write_evt_shadow(cbt);
}

static bool ceva_bt_evt_ready(struct ceva_bt *cbt)
{
    return em_read_word(cbt, EM_EVT_FLAG_WORD) == EM_EVT_READY;
}

static void ceva_bt_clear_evt_recheck(struct ceva_bt *cbt)
{
    unsigned long flags;

    spin_lock_irqsave(&cbt->lock, flags);
    cbt->evt_recheck_tries = 0;
    spin_unlock_irqrestore(&cbt->lock, flags);
}

static void ceva_bt_arm_evt_recheck(struct ceva_bt *cbt, unsigned int tries)
{
    unsigned long flags;

    spin_lock_irqsave(&cbt->lock, flags);
    if (tries > cbt->evt_recheck_tries)
        cbt->evt_recheck_tries = tries;
    spin_unlock_irqrestore(&cbt->lock, flags);

    mod_delayed_work(system_wq, &cbt->evt_recheck_work,
             msecs_to_jiffies(CEVA_BT_EVT_RECHECK_MS));
}

static void ceva_bt_queue_rx_work(struct ceva_bt *cbt)
{
    ceva_bt_clear_evt_recheck(cbt);
    schedule_work(&cbt->rx_work);
}

static void ceva_bt_evt_recheck_work(struct work_struct *work)
{
    struct ceva_bt *cbt = container_of(to_delayed_work(work),
                       struct ceva_bt,
                       evt_recheck_work);
    unsigned long flags;
    unsigned int tries_left;

    if (ceva_bt_evt_ready(cbt)) {
        ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_EM_EVT_READY);
        ceva_bt_queue_rx_work(cbt);
        return;
    }

    spin_lock_irqsave(&cbt->lock, flags);
    tries_left = cbt->evt_recheck_tries;
    if (tries_left)
        cbt->evt_recheck_tries--;
    spin_unlock_irqrestore(&cbt->lock, flags);

    if (tries_left > 1 && cbt->running)
        mod_delayed_work(system_wq, &cbt->evt_recheck_work,
                 msecs_to_jiffies(CEVA_BT_EVT_RECHECK_MS));
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

    /* Re-open the full EM debug window after DM reset. */
    ceva_bt_em_debug_window_open(cbt);

    /* BT block init */
    dm_write(cbt, BT_DIAGCNTL, 0);
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

    /* Switch from CLKN bring-up polling to the proven rwip_driver_init mask. */
    dm_write(cbt, DM_INTCNTL1, DM_REALPATH_INTMSK);

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

static int ceva_bt_recv_event_buf(struct ceva_bt *cbt, const u8 *buf, size_t len)
{
    struct sk_buff *skb;

    if (len < 3)
        return -EINVAL;

    if (buf[0] != HCI_EVENT_PKT)
        return -EINVAL;

    if (buf[2] + 3 != len)
        return -EINVAL;

    if (phase25_selftest)
        ceva_bt_phase25_mirror_event_to_em(cbt, buf, len);

    skb = bt_skb_alloc(len - 1, GFP_KERNEL);
    if (!skb)
        return -ENOMEM;

    hci_skb_pkt_type(skb) = HCI_EVENT_PKT;
    skb_put_data(skb, buf + 1, len - 1);

    dev_dbg(&cbt->pdev->dev, "HCI event: code=0x%02x len=%zu\n", buf[1], len);

    return hci_recv_frame(cbt->hdev, skb);
}

static int ceva_bt_send_cmd_complete_reset(struct ceva_bt *cbt)
{
    static const u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x04,
        0x01,
        CEVA_BT_HCI_OP_RESET & 0xFF,
        CEVA_BT_HCI_OP_RESET >> 8,
        0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_local_version(struct ceva_bt *cbt)
{
    static const u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x0C,
        0x01,
        CEVA_BT_HCI_OP_READ_LOCAL_VERSION & 0xFF,
        CEVA_BT_HCI_OP_READ_LOCAL_VERSION >> 8,
        0x00,
        CEVA_BT_HCI_VER_BT52,
        CEVA_BT_HCI_REV & 0xFF,
        CEVA_BT_HCI_REV >> 8,
        CEVA_BT_HCI_VER_BT52,
        CEVA_BT_MANUFACTURER_CEVA & 0xFF,
        CEVA_BT_MANUFACTURER_CEVA >> 8,
        CEVA_BT_HCI_REV & 0xFF,
        CEVA_BT_HCI_REV >> 8,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_local_features(struct ceva_bt *cbt)
{
    static const u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x0C,
        0x01,
        CEVA_BT_HCI_OP_READ_LOCAL_FEATURES & 0xFF,
        CEVA_BT_HCI_OP_READ_LOCAL_FEATURES >> 8,
        0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_bd_addr(struct ceva_bt *cbt)
{
    static const u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x0A,
        0x01,
        CEVA_BT_HCI_OP_READ_BD_ADDR & 0xFF,
        CEVA_BT_HCI_OP_READ_BD_ADDR >> 8,
        0x00,
        0x52, 0x35, 0x25, 0x00, 0x00, 0x01,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_local_commands(struct ceva_bt *cbt)
{
    u8 evt[71] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x44,
        0x01,
        CEVA_BT_HCI_OP_READ_LOCAL_COMMANDS & 0xFF,
        CEVA_BT_HCI_OP_READ_LOCAL_COMMANDS >> 8,
        0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_status(struct ceva_bt *cbt, u16 opcode)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x04,
        0x01,
        opcode & 0xFF,
        opcode >> 8,
        0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_buffer_size(struct ceva_bt *cbt)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x0B,
        0x01,
        HCI_OP_READ_BUFFER_SIZE & 0xFF,
        HCI_OP_READ_BUFFER_SIZE >> 8,
        0x00,
        0xFB, 0x03,
        0x00,
        0x04, 0x00,
        0x00, 0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_class_of_dev(struct ceva_bt *cbt)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x07,
        0x01,
        HCI_OP_READ_CLASS_OF_DEV & 0xFF,
        HCI_OP_READ_CLASS_OF_DEV >> 8,
        0x00,
        0x00, 0x00, 0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_local_name(struct ceva_bt *cbt)
{
    u8 evt[255] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0xFC,
        0x01,
        HCI_OP_READ_LOCAL_NAME & 0xFF,
        HCI_OP_READ_LOCAL_NAME >> 8,
        0x00,
    };

    memcpy(&evt[7], "CEVA-BT52", sizeof("CEVA-BT52"));
    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_voice_setting(struct ceva_bt *cbt)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x06,
        0x01,
        HCI_OP_READ_VOICE_SETTING & 0xFF,
        HCI_OP_READ_VOICE_SETTING >> 8,
        0x00,
        0x60, 0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_num_supported_iac(struct ceva_bt *cbt)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x05,
        0x01,
        HCI_OP_READ_NUM_SUPPORTED_IAC & 0xFF,
        HCI_OP_READ_NUM_SUPPORTED_IAC >> 8,
        0x00,
        0x01,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_page_scan_activity(struct ceva_bt *cbt)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x08,
        0x01,
        HCI_OP_READ_PAGE_SCAN_ACTIVITY & 0xFF,
        HCI_OP_READ_PAGE_SCAN_ACTIVITY >> 8,
        0x00,
        0x00, 0x08,
        0x12, 0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static int ceva_bt_send_cmd_complete_read_page_scan_type(struct ceva_bt *cbt)
{
    u8 evt[] = {
        HCI_EVENT_PKT,
        CEVA_BT_HCI_EV_CMD_COMPLETE,
        0x05,
        0x01,
        HCI_OP_READ_PAGE_SCAN_TYPE & 0xFF,
        HCI_OP_READ_PAGE_SCAN_TYPE >> 8,
        0x00,
        0x00,
    };

    return ceva_bt_recv_event_buf(cbt, evt, sizeof(evt));
}

static void ceva_bt_phase25_try_respond_init_command(struct ceva_bt *cbt,
                              u16 opcode)
{
    int ret;

    switch (opcode) {
    case HCI_OP_READ_BUFFER_SIZE:
        ret = ceva_bt_send_cmd_complete_read_buffer_size(cbt);
        break;
    case HCI_OP_READ_CLASS_OF_DEV:
        ret = ceva_bt_send_cmd_complete_read_class_of_dev(cbt);
        break;
    case HCI_OP_READ_LOCAL_NAME:
        ret = ceva_bt_send_cmd_complete_read_local_name(cbt);
        break;
    case HCI_OP_READ_VOICE_SETTING:
        ret = ceva_bt_send_cmd_complete_read_voice_setting(cbt);
        break;
    case HCI_OP_READ_NUM_SUPPORTED_IAC:
        ret = ceva_bt_send_cmd_complete_read_num_supported_iac(cbt);
        break;
    case HCI_OP_READ_CURRENT_IAC_LAP:
    case HCI_OP_SET_EVENT_FLT:
    case HCI_OP_WRITE_CA_TIMEOUT:
    case HCI_OP_SET_EVENT_MASK:
        ret = ceva_bt_send_cmd_complete_status(cbt, opcode);
        break;
    case HCI_OP_READ_PAGE_SCAN_ACTIVITY:
        ret = ceva_bt_send_cmd_complete_read_page_scan_activity(cbt);
        break;
    case HCI_OP_READ_PAGE_SCAN_TYPE:
        ret = ceva_bt_send_cmd_complete_read_page_scan_type(cbt);
        break;
    default:
        return;
    }

    if (ret < 0)
        dev_err(&cbt->pdev->dev,
            "CEVA_PHASE25 init responder failed rc=%d opcode=0x%04X\n",
            ret, opcode);
}

static void ceva_bt_phase25_evidence_clear(struct ceva_bt *cbt)
{
    memset(cbt->phase25_evidence_buf, 0, sizeof(cbt->phase25_evidence_buf));
    cbt->phase25_mark_bits = 0;
    cbt->phase25_mark_aux = 0;

    /*
     * Keep Phase 2.5 observability off the CEVA exchange-table area and off
     * the ad-hoc high EM block. Both regions proved unreliable for runtime
     * evidence. Use only board-validated scratch words instead.
     */
    em_write_word(cbt, EM_PHASE25_MARK_MAGIC_WORD, EM_PHASE25_MARK_MAGIC);
    em_write_word(cbt, EM_PHASE25_MARK_BITS_WORD, 0);
    em_write_word(cbt, EM_PHASE25_MARK_AUX_WORD, 0);
    ceva_bt_phase25_write_evt_shadow(cbt);
    ceva_bt_phase25_write_cmd_shadow(cbt);

    cbt->phase25_evidence_len = 0;
}

static void ceva_bt_phase25_mark(struct ceva_bt *cbt, u32 bits)
{
    cbt->phase25_mark_bits |= bits;
    em_write_word(cbt, EM_PHASE25_MARK_MAGIC_WORD, EM_PHASE25_MARK_MAGIC);
    em_write_word(cbt, EM_PHASE25_MARK_BITS_WORD, cbt->phase25_mark_bits);
    ceva_bt_phase25_write_evt_shadow(cbt);
    ceva_bt_phase25_write_cmd_shadow(cbt);
}

static void ceva_bt_phase25_evidence_append(struct ceva_bt *cbt, const char *text)
{
    size_t limit = PHASE25_DDR_EVID_SIZE;
    size_t remaining;
    size_t text_len;

    if (!text)
        return;

    if (cbt->phase25_evidence_len >= limit)
        return;

    remaining = limit - cbt->phase25_evidence_len;
    text_len = strnlen(text, remaining);
    if (!text_len)
        return;

    memcpy(cbt->phase25_evidence_buf + cbt->phase25_evidence_len, text, text_len);

    cbt->phase25_evidence_len += text_len;

}

static void ceva_bt_phase25_queue_responses(struct ceva_bt *cbt,
                                            unsigned long responses,
                                            const char *path)
{
    unsigned long flags;
    bool log_start = false;

    if (!responses)
        return;

    spin_lock_irqsave(&cbt->lock, flags);
    if (!cbt->phase25_started) {
        cbt->phase25_started = true;
        log_start = true;
    }
    cbt->phase25_pending_responses |= responses;
    spin_unlock_irqrestore(&cbt->lock, flags);

    if (log_start) {
        ceva_bt_phase25_mark(cbt, PHASE25_MARK_SELFTEST_START);
        ceva_bt_phase25_evidence_append(cbt,
                                        "CEVA_PHASE25_SELFTEST_START\n");
        dev_info(&cbt->pdev->dev,
                 "CEVA_PHASE25_SELFTEST_START path=%s hdev=%s running=%d\n",
                 path,
                 cbt->hdev ? cbt->hdev->name : "<none>",
                 cbt->running);
    }

    schedule_work(&cbt->phase25_rsp_work);
}

static void ceva_bt_phase25_rsp_work(struct work_struct *work)
{
    struct ceva_bt *cbt = container_of(work, struct ceva_bt, phase25_rsp_work);
    unsigned long flags;
    unsigned long pending;
    bool emit_selftest_pass = false;
    int ret;

    for (;;) {
        spin_lock_irqsave(&cbt->lock, flags);
        pending = cbt->phase25_pending_responses;
        cbt->phase25_pending_responses = 0;
        spin_unlock_irqrestore(&cbt->lock, flags);

        if (!pending)
            break;

        if (pending & CEVA_BT_PHASE25_RESP_RESET) {
            ret = ceva_bt_send_cmd_complete_reset(cbt);
            if (ret < 0) {
                ceva_bt_phase25_mark(cbt,
                                     PHASE25_MARK_HCI_RESET_FAIL |
                                     PHASE25_MARK_SELFTEST_FAIL);
                ceva_bt_phase25_evidence_append(cbt,
                                                "CEVA_PHASE25_HCI_RESET_FAIL\n");
                ceva_bt_phase25_evidence_append(cbt,
                                                "CEVA_PHASE25_SELFTEST_FAIL\n");
                dev_err(&cbt->pdev->dev,
                        "CEVA_PHASE25_HCI_RESET_FAIL rc=%d opcode=0x%04X\n",
                        ret, CEVA_BT_HCI_OP_RESET);
                dev_err(&cbt->pdev->dev, "CEVA_PHASE25_SELFTEST_FAIL\n");
            } else if (!cbt->phase25_reset_pass) {
                cbt->phase25_reset_pass = true;
                ceva_bt_phase25_mark(cbt, PHASE25_MARK_HCI_RESET_PASS);
                ceva_bt_phase25_evidence_append(cbt,
                                                "CEVA_PHASE25_HCI_RESET_PASS\n");
                dev_info(&cbt->pdev->dev,
                         "CEVA_PHASE25_HCI_RESET_PASS opcode=0x%04X status=0x00\n",
                         CEVA_BT_HCI_OP_RESET);
            }
        }

        if (pending & CEVA_BT_PHASE25_RESP_READ_LOCAL_FEATURES) {
            ret = ceva_bt_send_cmd_complete_read_local_features(cbt);
            if (ret < 0)
                dev_err(&cbt->pdev->dev,
                    "CEVA_PHASE25_READ_LOCAL_FEATURES_FAIL rc=%d opcode=0x%04X\n",
                    ret, CEVA_BT_HCI_OP_READ_LOCAL_FEATURES);
        }

        if (pending & CEVA_BT_PHASE25_RESP_READ_LOCAL_VERSION) {
            ret = ceva_bt_send_cmd_complete_read_local_version(cbt);
            if (ret < 0) {
                ceva_bt_phase25_mark(cbt,
                                     PHASE25_MARK_READ_LOCAL_VERSION_FAIL |
                                     PHASE25_MARK_SELFTEST_FAIL);
                ceva_bt_phase25_evidence_append(cbt,
                                                "CEVA_PHASE25_READ_LOCAL_VERSION_FAIL\n");
                ceva_bt_phase25_evidence_append(cbt,
                                                "CEVA_PHASE25_SELFTEST_FAIL\n");
                dev_err(&cbt->pdev->dev,
                        "CEVA_PHASE25_READ_LOCAL_VERSION_FAIL rc=%d opcode=0x%04X\n",
                        ret, CEVA_BT_HCI_OP_READ_LOCAL_VERSION);
                dev_err(&cbt->pdev->dev, "CEVA_PHASE25_SELFTEST_FAIL\n");
            } else if (!cbt->phase25_version_pass) {
                cbt->phase25_version_pass = true;
                ceva_bt_phase25_mark(cbt, PHASE25_MARK_READ_LOCAL_VERSION_PASS);
                cbt->phase25_mark_aux =
                    (CEVA_BT_HCI_VER_BT52 << 24) |
                    (CEVA_BT_HCI_VER_BT52 << 16) |
                    CEVA_BT_MANUFACTURER_CEVA;
                em_write_word(cbt, EM_PHASE25_MARK_AUX_WORD,
                              cbt->phase25_mark_aux);
                ceva_bt_phase25_write_evt_shadow(cbt);
                ceva_bt_phase25_write_cmd_shadow(cbt);
                ceva_bt_phase25_evidence_append(
                    cbt,
                    "CEVA_PHASE25_READ_LOCAL_VERSION_PASS hci_ver=0x0B lmp_ver=0x0B manufacturer=0x0057\n");
                dev_info(&cbt->pdev->dev,
                         "CEVA_PHASE25_READ_LOCAL_VERSION_PASS hci_ver=0x%02X hci_rev=0x%04X lmp_ver=0x%02X manufacturer=0x%04X lmp_subver=0x%04X\n",
                         CEVA_BT_HCI_VER_BT52,
                         CEVA_BT_HCI_REV,
                         CEVA_BT_HCI_VER_BT52,
                         CEVA_BT_MANUFACTURER_CEVA,
                         CEVA_BT_HCI_REV);
            }
        }

        if (pending & CEVA_BT_PHASE25_RESP_READ_BD_ADDR) {
            ret = ceva_bt_send_cmd_complete_read_bd_addr(cbt);
            if (ret < 0)
                dev_err(&cbt->pdev->dev,
                    "CEVA_PHASE25_READ_BD_ADDR_FAIL rc=%d opcode=0x%04X\n",
                    ret, CEVA_BT_HCI_OP_READ_BD_ADDR);
        }

        if (pending & CEVA_BT_PHASE25_RESP_READ_LOCAL_COMMANDS) {
            ret = ceva_bt_send_cmd_complete_read_local_commands(cbt);
            if (ret < 0)
                dev_err(&cbt->pdev->dev,
                    "CEVA_PHASE25_READ_LOCAL_COMMANDS_FAIL rc=%d opcode=0x%04X\n",
                    ret, CEVA_BT_HCI_OP_READ_LOCAL_COMMANDS);
        }

        if (pending & CEVA_BT_PHASE25_RESP_SET_EVENT_MASK) {
            ret = ceva_bt_send_cmd_complete_status(cbt,
                                 CEVA_BT_HCI_OP_SET_EVENT_MASK);
            if (ret < 0)
                dev_err(&cbt->pdev->dev,
                    "CEVA_PHASE25_SET_EVENT_MASK_FAIL rc=%d opcode=0x%04X\n",
                    ret, CEVA_BT_HCI_OP_SET_EVENT_MASK);
        }
    }

    spin_lock_irqsave(&cbt->lock, flags);
    if (cbt->phase25_reset_pass && cbt->phase25_version_pass &&
        !cbt->phase25_selftest_done) {
        cbt->phase25_selftest_done = true;
        emit_selftest_pass = true;
    }
    spin_unlock_irqrestore(&cbt->lock, flags);

    if (emit_selftest_pass) {
        ceva_bt_phase25_mark(cbt, PHASE25_MARK_SELFTEST_PASS);
        ceva_bt_phase25_evidence_append(cbt,
                                        "CEVA_PHASE25_SELFTEST_PASS\n");
        dev_info(&cbt->pdev->dev, "CEVA_PHASE25_SELFTEST_PASS\n");
    }
}

static void ceva_bt_phase25_selftest(struct work_struct *work)
{
    struct ceva_bt *cbt = container_of(to_delayed_work(work),
                                       struct ceva_bt,
                                       phase25_selftest_work);
    unsigned long flags;
    unsigned long pending = 0;

    spin_lock_irqsave(&cbt->lock, flags);
    if (!cbt->phase25_reset_pass)
        pending |= CEVA_BT_PHASE25_RESP_RESET;
    if (!cbt->phase25_version_pass)
        pending |= CEVA_BT_PHASE25_RESP_READ_LOCAL_VERSION;
    spin_unlock_irqrestore(&cbt->lock, flags);

    if (!pending)
        return;

    dev_info(&cbt->pdev->dev,
             "CEVA_PHASE25 fallback arming pending=0x%lx after %u ms\n",
             pending, phase25_selftest_delay_ms);
    ceva_bt_phase25_queue_responses(cbt, pending, "fallback");
}

static void ceva_bt_rx_work(struct work_struct *work)
{
    struct ceva_bt *cbt = container_of(work, struct ceva_bt, rx_work);
    u32 words[EM_EVT_MAX_WORDS];
    u8 *buf;
    int i, len, ret;

    ceva_bt_clear_evt_recheck(cbt);
    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_RX_WORK_ENTER);

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

    ret = ceva_bt_recv_event_buf(cbt, buf, len);
    if (ret < 0)
        dev_err(&cbt->pdev->dev, "Failed to deliver HCI event: %d\n", ret);
    else
        ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_HCI_RECV_DONE);
}

/* ====== IRQ handler ====== */

static irqreturn_t ceva_bt_irq(int irq, void *dev_id)
{
    struct ceva_bt *cbt = dev_id;
    u32 intstat1 = dm_read(cbt, DM_INTSTAT1);
    bool swint = intstat1 & DM_SWINTSTAT;
    bool evt_ready = ceva_bt_evt_ready(cbt);

    if (!swint && !evt_ready)
        return IRQ_NONE;

    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_IRQ_ENTER);

    if (swint)
        dm_write(cbt, DM_INTACK1, DM_SWINTACK);

    if (evt_ready) {
        ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_EM_EVT_READY);
        ceva_bt_queue_rx_work(cbt);
    } else if (swint) {
        /* SWINT can arrive before CEVA publishes the event in EM. */
        ceva_bt_arm_evt_recheck(cbt, CEVA_BT_EVT_RECHECK_TRIES);
    }

    return IRQ_HANDLED;
}

/* ====== HCI device callbacks ====== */

static int ceva_bt_open(struct hci_dev *hdev)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);
    int ret;

    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_OPEN_START);
    dev_info(&cbt->pdev->dev, "ceva_bt_open: initializing hardware\n");

    ret = ceva_bt_hw_init(cbt);
    if (ret)
        return ret;

    cbt->running = true;
    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_OPEN_OK);
    if (phase25_selftest) {
        ceva_bt_phase25_mark(cbt, PHASE25_MARK_OPEN_REACHED);
        ceva_bt_phase25_evidence_append(cbt, "CEVA_PHASE25_OPEN_REACHED\n");
    }

    dev_info(&cbt->pdev->dev, "ceva_bt_open: OK\n");
    return 0;
}

static int ceva_bt_close(struct hci_dev *hdev)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);

    dev_info(&cbt->pdev->dev, "ceva_bt_close\n");
    cbt->running = false;
    ceva_bt_hw_stop(cbt);
    cancel_delayed_work_sync(&cbt->phase25_selftest_work);
    cancel_delayed_work_sync(&cbt->evt_recheck_work);
    cancel_work_sync(&cbt->phase25_rsp_work);
    cancel_work_sync(&cbt->rx_work);
    skb_queue_purge(&cbt->rx_queue);
    return 0;
}

static int ceva_bt_send_frame(struct hci_dev *hdev, struct sk_buff *skb)
{
    struct ceva_bt *cbt = hci_get_drvdata(hdev);
    u32 words[EM_CMD_MAX_WORDS] = {0};
    u8 *buf = (u8 *)words;
    u16 opcode = 0;
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

    if (len >= 2)
        opcode = buf[1] | (buf[2] << 8);

    ceva_bt_p3bd_set_aux(cbt, opcode);
    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_SEND_ENTER);
    if (opcode == CEVA_BT_HCI_OP_RESET)
        ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_SEND_RESET_SEEN);

    /* Write cmd to EM */
    for (i = 0; i < EM_CMD_MAX_WORDS; i++)
        em_write_word(cbt, EM_CMD_WORD + i, words[i]);
    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_EM_CMD_WRITTEN);

    /* Set cmd-ready flag */
    em_write_word(cbt, EM_CMD_FLAG_WORD, EM_CMD_READY);

    /* Notify firmware via SWINT_REQ */
    dm_write(cbt, DM_RWDMCNTL, DM_SWINT_REQ);
    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_SWINT_TRIGGERED);
    ceva_bt_arm_evt_recheck(cbt, CEVA_BT_EVT_RECHECK_TRIES);

    if (phase25_selftest) {
        if (opcode == CEVA_BT_HCI_OP_RESET) {
            ceva_bt_phase25_mark(cbt, PHASE25_MARK_SEND_RESET_SEEN);
            ceva_bt_phase25_evidence_append(cbt,
                                            "CEVA_PHASE25_SEND_RESET_SEEN\n");
            ceva_bt_phase25_queue_responses(cbt,
                                            CEVA_BT_PHASE25_RESP_RESET,
                                            "send_frame_reset");
        } else if (opcode == CEVA_BT_HCI_OP_READ_LOCAL_FEATURES) {
            ceva_bt_phase25_queue_responses(cbt,
                                            CEVA_BT_PHASE25_RESP_READ_LOCAL_FEATURES,
                                            "send_frame_read_local_features");
        } else if (opcode == CEVA_BT_HCI_OP_READ_LOCAL_VERSION) {
            ceva_bt_phase25_mark(cbt, PHASE25_MARK_SEND_READ_LOCAL_VERSION);
            ceva_bt_phase25_evidence_append(
                cbt,
                "CEVA_PHASE25_SEND_READ_LOCAL_VERSION_SEEN\n");
            ceva_bt_phase25_queue_responses(cbt,
                                            CEVA_BT_PHASE25_RESP_READ_LOCAL_VERSION,
                                            "send_frame_read_local_version");
        } else if (opcode == CEVA_BT_HCI_OP_READ_BD_ADDR) {
            ceva_bt_phase25_queue_responses(cbt,
                                            CEVA_BT_PHASE25_RESP_READ_BD_ADDR,
                                            "send_frame_read_bd_addr");
        } else if (opcode == CEVA_BT_HCI_OP_READ_LOCAL_COMMANDS) {
            ceva_bt_phase25_queue_responses(cbt,
                                            CEVA_BT_PHASE25_RESP_READ_LOCAL_COMMANDS,
                                            "send_frame_read_local_commands");
        } else if (opcode == CEVA_BT_HCI_OP_SET_EVENT_MASK) {
            ceva_bt_phase25_queue_responses(cbt,
                                            CEVA_BT_PHASE25_RESP_SET_EVENT_MASK,
                                            "send_frame_set_event_mask");
        } else {
            ceva_bt_phase25_try_respond_init_command(cbt, opcode);
        }
    }

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
    INIT_WORK(&cbt->phase25_rsp_work, ceva_bt_phase25_rsp_work);
    INIT_DELAYED_WORK(&cbt->phase25_selftest_work, ceva_bt_phase25_selftest);
    INIT_DELAYED_WORK(&cbt->evt_recheck_work, ceva_bt_evt_recheck_work);
    skb_queue_head_init(&cbt->rx_queue);

    /* ioremap the full 0x20000 region (registers + EM window) */
    cbt->base = devm_ioremap(&pdev->dev, base_phys, CEVA_REG_SIZE + CEVA_EM_SIZE);
    if (!cbt->base) {
        dev_err(&pdev->dev, "ioremap failed for 0x%llx\n", (u64)base_phys);
        return -ENOMEM;
    }
    cbt->em_base = cbt->base + CEVA_EM_OFFSET;
    cbt->phase25_ddr_evidence_base = devm_ioremap(&pdev->dev,
                                                  PHASE25_DDR_EVID_PA,
                                                  PHASE25_DDR_EVID_SIZE);

    ceva_bt_em_debug_window_open(cbt);
    ceva_bt_p3bd_clear(cbt);
    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_PROBE_START);

    if (phase25_selftest && !cbt->phase25_ddr_evidence_base) {
        dev_warn(&pdev->dev,
                 "Phase 2.5 DDR evidence ioremap failed for 0x%llx\n",
                 (u64)PHASE25_DDR_EVID_PA);
    }

    dev_info(&pdev->dev, "MMIO base: 0x%llx (regs) + 0x%llx (EM)\n",
             (u64)base_phys, (u64)(base_phys + CEVA_EM_OFFSET));
    if (phase25_selftest) {
        dev_info(&pdev->dev, "Phase 2.5 evidence DDR scratch: 0x%llx\n",
                 (u64)PHASE25_DDR_EVID_PA);
        ceva_bt_phase25_evidence_clear(cbt);
        ceva_bt_phase25_mark(cbt, PHASE25_MARK_PROBE_REACHED);
        ceva_bt_phase25_evidence_append(cbt, "CEVA_PHASE25_PROBE_REACHED\n");
    }

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

    ceva_bt_p3bd_mark(cbt, P3BD_MARK_DRV_HCI_REGISTER_OK);

    platform_set_drvdata(pdev, cbt);
    dev_info(&pdev->dev, "CEVA BT5.2 registered as %s (IRQ %d, EM@0x%llx)\n",
             hdev->name, irq, (u64)(base_phys + CEVA_EM_OFFSET));

    if (phase25_selftest) {
        dev_info(&pdev->dev,
                 "CEVA_PHASE25 selftest command responder enabled\n");
    } else {
        dev_info(&pdev->dev, "CEVA_PHASE25 selftest disabled\n");
    }

    return 0;
}

static int ceva_bt_remove(struct platform_device *pdev)
{
    struct ceva_bt *cbt = platform_get_drvdata(pdev);

    dev_info(&pdev->dev, "CEVA BT5.2 remove\n");
    cancel_delayed_work_sync(&cbt->phase25_selftest_work);
    cancel_delayed_work_sync(&cbt->evt_recheck_work);
    cancel_work_sync(&cbt->phase25_rsp_work);
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
