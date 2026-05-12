#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifndef AF_BLUETOOTH
#define AF_BLUETOOTH 31
#endif

#define BTPROTO_HCI 1
#define SOL_HCI 0

#define HCI_FILTER 2

#define HCI_CHANNEL_RAW 0
#define HCI_CHANNEL_USER 1

#define HCI_COMMAND_PKT 0x01
#define HCI_EVENT_PKT 0x04

#define HCI_EV_CMD_COMPLETE 0x0e
#define HCI_EV_CMD_STATUS 0x0f

#define HCI_UP 0

#define HCI_DEV_ID 0

#define OGF_HOST_CTL 0x03
#define OCF_RESET 0x0003
#define OGF_INFO_PARAM 0x04
#define OCF_READ_LOCAL_VERSION 0x0001

#define HCI_OPCODE(ogf, ocf) ((uint16_t) ((((ogf) & 0x3f) << 10) | ((ocf) & 0x03ff)))
#define HCI_OP_RESET HCI_OPCODE(OGF_HOST_CTL, OCF_RESET)
#define HCI_OP_READ_LOCAL_VERSION HCI_OPCODE(OGF_INFO_PARAM, OCF_READ_LOCAL_VERSION)

#define HCIDEVUP _IOW('H', 201, int)
#define HCIGETDEVINFO _IOR('H', 211, int)

#define DEFAULT_TIMEOUT_MS 3000
#define UP_WAIT_MS 1500

#define CEVA_EM_BASE_ADDR 0x65010000ULL
#define CEVA_EVT_WORD0_OFF 0x180
#define CEVA_EVT_WORD1_OFF 0x184
#define CEVA_EVT_WORD2_OFF 0x188
#define CEVA_EVT_WORD3_OFF 0x18c
#define CEVA_EVT_SHADOW_MAGIC_OFF 0x190
#define CEVA_EVT_SHADOW_BITS_OFF 0x194
#define CEVA_EVT_SHADOW_AUX_OFF 0x198
#define CEVA_PHASE25_MAGIC 0x50323521U

struct sockaddr_hci {
	sa_family_t hci_family;
	unsigned short hci_dev;
	unsigned short hci_channel;
};

struct hci_filter {
	unsigned long type_mask;
	unsigned long event_mask[2];
	uint16_t opcode;
};

typedef struct {
	uint8_t b[6];
} bdaddr_t;

struct hci_dev_stats {
	uint32_t err_rx;
	uint32_t err_tx;
	uint32_t cmd_tx;
	uint32_t evt_rx;
	uint32_t acl_tx;
	uint32_t acl_rx;
	uint32_t sco_tx;
	uint32_t sco_rx;
	uint32_t byte_rx;
	uint32_t byte_tx;
};

struct hci_dev_info {
	uint16_t dev_id;
	char name[8];
	bdaddr_t bdaddr;
	uint32_t flags;
	uint8_t type;
	uint8_t features[8];
	uint32_t pkt_type;
	uint32_t link_policy;
	uint32_t link_mode;
	uint16_t acl_mtu;
	uint16_t acl_pkts;
	uint16_t sco_mtu;
	uint16_t sco_pkts;
	struct hci_dev_stats stat;
};

struct hci_command_hdr {
	uint16_t opcode;
	uint8_t plen;
} __attribute__((packed));

struct hci_event_hdr {
	uint8_t evt;
	uint8_t plen;
} __attribute__((packed));

struct hci_ev_cmd_complete {
	uint8_t ncmd;
	uint16_t opcode;
} __attribute__((packed));

struct hci_ev_cmd_status {
	uint8_t status;
	uint8_t ncmd;
	uint16_t opcode;
} __attribute__((packed));

struct hci_rp_read_local_version {
	uint8_t status;
	uint8_t hci_ver;
	uint16_t hci_rev;
	uint8_t lmp_ver;
	uint16_t manufacturer;
	uint16_t lmp_subver;
} __attribute__((packed));

struct command_result {
	bool pass;
	bool saw_cmd_complete;
	uint8_t status;
	int send_errno;
	int recv_errno;
	struct hci_rp_read_local_version version;
};

static void smoke_alarm_handler(int signo)
{
	(void) signo;
	printf("PHASE25_USER_SMOKE_TIMEOUT\n");
	fflush(stdout);
	_exit(124);
}

static uint16_t le16_to_cpu_u(uint16_t value)
{
	return value;
}

static uint16_t cpu_to_le16_u(uint16_t value)
{
	return value;
}

static long long monotonic_ms(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return 0;

	return (long long) ts.tv_sec * 1000LL + (long long) ts.tv_nsec / 1000000LL;
}

static const char *err_text(int err)
{
	return err ? strerror(err) : "OK";
}

static void print_errno_result(const char *label, int rc, int err)
{
	printf("%s rc=%d errno=%d (%s)\n", label, rc, err, err_text(err));
	fflush(stdout);
}

static void probe_log(const char *msg)
{
	FILE *kmsg = fopen("/dev/kmsg", "a");

	if (kmsg) {
		fprintf(kmsg, "<6>%s\n", msg);
		fclose(kmsg);
	}

	printf("%s\n", msg);
	fflush(stdout);
}

static void probe_command_stage(uint16_t opcode, const char *stage)
{
	char msg[96];

	snprintf(msg, sizeof(msg), "PHASE25_USER_CMD_%04x_%s", opcode, stage);
	probe_log(msg);
}

static void print_command_recv(const char *label,
				      int recv_len,
				      uint8_t event,
				      uint16_t opcode,
				      uint8_t status,
				      int err);

static void hci_filter_clear(struct hci_filter *filter)
{
	memset(filter, 0, sizeof(*filter));
}

static void hci_filter_set_ptype(unsigned int packet_type, struct hci_filter *filter)
{
	filter->type_mask |= (1UL << (packet_type & 31));
}

static void hci_filter_set_event(unsigned int event, struct hci_filter *filter)
{
	filter->event_mask[(event >> 5) & 1U] |= (1UL << (event & 31));
}

static int parse_timeout_ms(int argc, char **argv)
{
	const char *text = getenv("PHASE25_USER_HCI_TIMEOUT_MS");
	long value;
	char *endptr = NULL;

	if (argc > 1 && argv[1] && argv[1][0] != '\0')
		text = argv[1];

	if (!text || text[0] == '\0')
		return DEFAULT_TIMEOUT_MS;

	errno = 0;
	value = strtol(text, &endptr, 10);
	if (errno != 0 || endptr == text || *endptr != '\0' || value <= 0 || value > 60000)
		return DEFAULT_TIMEOUT_MS;

	return (int) value;
}

static int fetch_dev_info(int sock, struct hci_dev_info *info, const char *label)
{
	int rc;
	int saved_errno;

	memset(info, 0, sizeof(*info));
	info->dev_id = HCI_DEV_ID;
	rc = ioctl(sock, HCIGETDEVINFO, info);
	saved_errno = (rc < 0) ? errno : 0;
	print_errno_result(label, rc, saved_errno);
	if (rc == 0) {
		printf("%s name=%s flags=0x%08x type=%u\n",
		       label,
		       info->name,
		       info->flags,
		       info->type);
		fflush(stdout);
	}

	return rc;
}

static bool wait_until_hci_up(int sock, int timeout_ms, struct hci_dev_info *last_info)
{
	long long deadline = monotonic_ms() + timeout_ms;

	while (monotonic_ms() < deadline) {
		if (fetch_dev_info(sock, last_info, "PHASE25_USER_IOCTL_HCIGETDEVINFO_WAIT") == 0 &&
		    ((last_info->flags & (1U << HCI_UP)) != 0))
			return true;

		usleep(100000);
	}

	return fetch_dev_info(sock, last_info, "PHASE25_USER_IOCTL_HCIGETDEVINFO_FINAL") == 0 &&
	       ((last_info->flags & (1U << HCI_UP)) != 0);
}

static bool mmio_read_u32(int mem_fd, off_t offset, uint32_t *value)
{
	ssize_t rc = pread(mem_fd, value, sizeof(*value), offset);

	return rc == (ssize_t) sizeof(*value);
}

static bool mmio_write_u32(int mem_fd, off_t offset, uint32_t value)
{
	ssize_t rc = pwrite(mem_fd, &value, sizeof(value), offset);

	return rc == (ssize_t) sizeof(value);
}

static bool clear_phase25_event_shadow(int mem_fd)
{
	return mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD0_OFF, 0) &&
	       mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD1_OFF, 0) &&
	       mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD2_OFF, 0) &&
	       mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD3_OFF, 0) &&
	       mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_SHADOW_MAGIC_OFF, 0) &&
	       mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_SHADOW_BITS_OFF, 0) &&
	       mmio_write_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_SHADOW_AUX_OFF, 0);
}

static bool wait_for_mmio_event(int mem_fd,
				      const char *label,
				      uint16_t opcode,
				      int timeout_ms,
				      struct command_result *result)
{
	long long deadline = monotonic_ms() + timeout_ms;
	uint32_t words[4];
	uint32_t shadow_magic;
	uint8_t raw[sizeof(words)];
	uint16_t event_opcode;
	uint8_t event_status;

	probe_command_stage(opcode, "MMIO_WAIT");
	while (monotonic_ms() < deadline) {
		if (!mmio_read_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_SHADOW_MAGIC_OFF,
				  &shadow_magic)) {
			result->recv_errno = errno ? errno : EIO;
			break;
		}

		if (shadow_magic != CEVA_PHASE25_MAGIC) {
			usleep(10000);
			continue;
		}

		if (!mmio_read_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD0_OFF, &words[0]) ||
		    !mmio_read_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD1_OFF, &words[1]) ||
		    !mmio_read_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD2_OFF, &words[2]) ||
		    !mmio_read_u32(mem_fd, CEVA_EM_BASE_ADDR + CEVA_EVT_WORD3_OFF, &words[3])) {
			result->recv_errno = errno ? errno : EIO;
			break;
		}

		memcpy(raw, words, sizeof(raw));
		event_opcode = (uint16_t) raw[4] | ((uint16_t) raw[5] << 8);
		event_status = raw[6];
		if (event_opcode != opcode) {
			usleep(10000);
			continue;
		}

		result->saw_cmd_complete = true;
		result->recv_errno = 0;
		result->status = event_status;
		if (opcode == HCI_OP_READ_LOCAL_VERSION) {
			result->version.status = raw[6];
			result->version.hci_ver = raw[7];
			result->version.hci_rev = (uint16_t) raw[8] | ((uint16_t) raw[9] << 8);
			result->version.lmp_ver = raw[10];
			result->version.manufacturer = (uint16_t) raw[11] | ((uint16_t) raw[12] << 8);
			result->version.lmp_subver = (uint16_t) raw[13] | ((uint16_t) raw[14] << 8);
		}

		probe_command_stage(opcode, "MMIO_MATCH");
		print_command_recv(label, (int) sizeof(raw), HCI_EV_CMD_COMPLETE,
				   event_opcode, event_status, 0);
		return event_status == 0;
	}

	result->recv_errno = result->recv_errno ? result->recv_errno : ETIMEDOUT;
	probe_command_stage(opcode, "MMIO_TIMEOUT");
	print_command_recv(label, -1, 0, opcode, 0xff, result->recv_errno);
	return false;
}

static bool bind_hci_socket(int sock, unsigned short channel)
{
	struct sockaddr_hci addr;
	int rc;
	int saved_errno;

	memset(&addr, 0, sizeof(addr));
	addr.hci_family = AF_BLUETOOTH;
	addr.hci_dev = HCI_DEV_ID;
	addr.hci_channel = channel;

	rc = bind(sock, (const struct sockaddr *) &addr, sizeof(addr));
	saved_errno = (rc < 0) ? errno : 0;
	print_errno_result("PHASE25_USER_BIND", rc, saved_errno);

	return rc == 0;
}

static bool install_filter(int sock, unsigned short channel, uint16_t opcode)
{
	struct hci_filter filter;
	int rc;
	int saved_errno;

	if (channel == HCI_CHANNEL_USER) {
		print_errno_result("PHASE25_USER_SETSOCKOPT_SKIP_USER", 0, 0);
		return true;
	}

	hci_filter_clear(&filter);
	hci_filter_set_ptype(HCI_EVENT_PKT, &filter);
	hci_filter_set_event(HCI_EV_CMD_COMPLETE, &filter);
	hci_filter_set_event(HCI_EV_CMD_STATUS, &filter);
	filter.opcode = cpu_to_le16_u(opcode);

	rc = setsockopt(sock, SOL_HCI, HCI_FILTER, &filter, sizeof(filter));
	saved_errno = (rc < 0) ? errno : 0;
	print_errno_result("PHASE25_USER_SETSOCKOPT", rc, saved_errno);

	return rc == 0;
}

static void print_command_recv(const char *label,
				      int recv_len,
				      uint8_t event,
				      uint16_t opcode,
				      uint8_t status,
				      int err)
{
	printf("PHASE25_USER_%s_RECV rc=%d errno=%d (%s) evt=0x%02x opcode=0x%04x status=0x%02x\n",
	       label,
	       recv_len,
	       err,
	       err_text(err),
	       event,
	       opcode,
	       status);
	fflush(stdout);
}

static bool wait_for_command_result(int sock,
				    const char *label,
				    uint16_t opcode,
				    int timeout_ms,
				    struct command_result *result)
{
	long long deadline = monotonic_ms() + timeout_ms;
	uint8_t buffer[260];

	result->recv_errno = ETIMEDOUT;

	while (monotonic_ms() < deadline) {
		struct pollfd poll_fd = {
			.fd = sock,
			.events = POLLIN,
		};
		int wait_ms = (int) (deadline - monotonic_ms());
		int poll_rc;
		ssize_t recv_rc;

		if (wait_ms < 0)
			wait_ms = 0;

		poll_rc = poll(&poll_fd, 1, wait_ms);
		if (poll_rc < 0) {
			if (errno == EINTR)
				continue;
			result->recv_errno = errno;
			print_command_recv(label, -1, 0, 0, 0, result->recv_errno);
			return false;
		}

		if (poll_rc == 0)
			break;

		probe_command_stage(opcode, "POLL_READY");

		recv_rc = recv(sock, buffer, sizeof(buffer), 0);
		if (recv_rc < 0) {
			if (errno == EINTR)
				continue;
			result->recv_errno = errno;
			print_command_recv(label, -1, 0, 0, 0, result->recv_errno);
			return false;
		}

		if (recv_rc < 1 + (ssize_t) sizeof(struct hci_event_hdr) || buffer[0] != HCI_EVENT_PKT)
			continue;

		{
			const struct hci_event_hdr *event_hdr = (const struct hci_event_hdr *) (buffer + 1);
			const uint8_t *payload = buffer + 1 + sizeof(*event_hdr);
			size_t payload_len = (size_t) recv_rc - 1 - sizeof(*event_hdr);

			if (payload_len < event_hdr->plen)
				continue;

			if (event_hdr->evt == HCI_EV_CMD_STATUS) {
				const struct hci_ev_cmd_status *status_evt;

				if (payload_len < sizeof(*status_evt))
					continue;

				status_evt = (const struct hci_ev_cmd_status *) payload;
				if (le16_to_cpu_u(status_evt->opcode) != opcode)
					continue;

				result->status = status_evt->status;
				result->recv_errno = 0;
				probe_command_stage(opcode, "CMD_STATUS");
				print_command_recv(label,
						   (int) recv_rc,
						   event_hdr->evt,
						   le16_to_cpu_u(status_evt->opcode),
						   status_evt->status,
						   0);
				if (status_evt->status != 0)
					return false;
				continue;
			}

			if (event_hdr->evt != HCI_EV_CMD_COMPLETE)
				continue;

			if (payload_len < sizeof(struct hci_ev_cmd_complete) + 1)
				continue;

			{
				const struct hci_ev_cmd_complete *complete_evt =
					(const struct hci_ev_cmd_complete *) payload;
				const uint8_t *return_params = payload + sizeof(*complete_evt);
				size_t return_len = payload_len - sizeof(*complete_evt);

				if (le16_to_cpu_u(complete_evt->opcode) != opcode)
					continue;

				result->saw_cmd_complete = true;
				result->status = return_params[0];
				result->recv_errno = 0;
				probe_command_stage(opcode, "CMD_COMPLETE");
				print_command_recv(label,
						   (int) recv_rc,
						   event_hdr->evt,
						   le16_to_cpu_u(complete_evt->opcode),
						   return_params[0],
						   0);

				if (opcode == HCI_OP_READ_LOCAL_VERSION &&
				    return_len >= sizeof(result->version))
					memcpy(&result->version, return_params, sizeof(result->version));

				return result->status == 0;
			}
		}
	}

	probe_command_stage(opcode, "WAIT_TIMEOUT");
	print_command_recv(label, -1, 0, opcode, 0xff, result->recv_errno);
	return false;
}

static bool run_command(int sock,
			int mem_fd,
			unsigned short channel,
			const char *label,
			uint16_t opcode,
			int timeout_ms,
			struct command_result *result)
{
	uint8_t command[1 + sizeof(struct hci_command_hdr)];
	struct hci_command_hdr *command_hdr = (struct hci_command_hdr *) (command + 1);
	ssize_t send_rc;

	memset(result, 0, sizeof(*result));

	if (!install_filter(sock, channel, opcode)) {
		result->send_errno = errno;
		return false;
	}
	probe_command_stage(opcode, "FILTER_OK");
	if (mem_fd >= 0 && !clear_phase25_event_shadow(mem_fd)) {
		result->send_errno = errno ? errno : EIO;
		printf("PHASE25_USER_%s_MMIO_CLEAR_FAIL errno=%d (%s)\n",
		       label,
		       result->send_errno,
		       err_text(result->send_errno));
		fflush(stdout);
		return false;
	}

	command[0] = HCI_COMMAND_PKT;
	command_hdr->opcode = cpu_to_le16_u(opcode);
	command_hdr->plen = 0;

	probe_command_stage(opcode, "BEFORE_SEND");
	send_rc = send(sock, command, sizeof(command), 0);
	result->send_errno = (send_rc < 0) ? errno : 0;
	printf("PHASE25_USER_%s_SEND rc=%zd errno=%d (%s) opcode=0x%04x\n",
	       label,
	       send_rc,
	       result->send_errno,
	       err_text(result->send_errno),
	       opcode);
	fflush(stdout);
	if (send_rc < 0)
		return false;
	probe_command_stage(opcode, "AFTER_SEND");

	probe_command_stage(opcode, "WAIT_RESULT");
	if (mem_fd >= 0)
		result->pass = wait_for_mmio_event(mem_fd, label, opcode, timeout_ms, result);
	else
		result->pass = wait_for_command_result(sock, label, opcode, timeout_ms, result);
	return result->pass;
}

int main(int argc, char **argv)
{
	int timeout_ms = parse_timeout_ms(argc, argv);
	bool hci0_present = (access("/sys/class/bluetooth/hci0", F_OK) == 0);
	int mem_fd = -1;
	int sock;
	int saved_errno;
	struct hci_dev_info dev_info;
	bool hci_up = false;
	unsigned short active_channel = HCI_CHANNEL_RAW;
	struct command_result reset_result;
	struct command_result rlv_result;
	bool overall_pass = false;

	setvbuf(stdout, NULL, _IOLBF, 0);
	setvbuf(stderr, NULL, _IOLBF, 0);
	signal(SIGALRM, smoke_alarm_handler);
	alarm(20);
	probe_log("PHASE25_USER_SMOKE_START");

	if (hci0_present)
		printf("PHASE25_USER_HCI0_PRESENT\n");
	else
		printf("PHASE25_USER_HCI0_MISSING\n");
	printf("PHASE25_USER_TIMEOUT_MS %d\n", timeout_ms);

	probe_log("PHASE25_USER_STEP_SOCKET");
	sock = socket(AF_BLUETOOTH, SOCK_RAW, BTPROTO_HCI);
	saved_errno = (sock < 0) ? errno : 0;
	print_errno_result("PHASE25_USER_SOCKET", sock, saved_errno);
	if (sock < 0)
		goto summary;

	probe_log("PHASE25_USER_STEP_GETDEVINFO");
	if (fetch_dev_info(sock, &dev_info, "PHASE25_USER_IOCTL_HCIGETDEVINFO") == 0)
		hci0_present = true;
	if ((dev_info.flags & (1U << HCI_UP)) != 0)
		hci_up = true;

	if (!hci_up) {
		probe_log("PHASE25_USER_HCI0_NOT_UP_CONTINUE");
	} else {
		probe_log("PHASE25_USER_HCI0_ALREADY_UP");
	}

	printf("PHASE25_USER_HCI0_UP %s\n", hci_up ? "yes" : "no");
	fflush(stdout);

	probe_log("PHASE25_USER_STEP_BIND");
	if (!hci_up) {
		probe_log("PHASE25_USER_BIND_CHANNEL_USER");
		if (!bind_hci_socket(sock, HCI_CHANNEL_USER)) {
			probe_log("PHASE25_USER_BIND_CHANNEL_RAW_FALLBACK");
			if (!bind_hci_socket(sock, HCI_CHANNEL_RAW))
				goto close_and_summary;
			active_channel = HCI_CHANNEL_RAW;
		} else {
			active_channel = HCI_CHANNEL_USER;
		}
	} else if (!bind_hci_socket(sock, HCI_CHANNEL_RAW)) {
		goto close_and_summary;
	} else {
		active_channel = HCI_CHANNEL_RAW;
	}

	probe_log("PHASE25_USER_STEP_HCI_RESET");
	if (!run_command(sock, mem_fd, active_channel,
			 "HCI_RESET", HCI_OP_RESET, timeout_ms, &reset_result)) {
		printf("PHASE25_USER_HCI_RESET_FAIL\n");
		fflush(stdout);
		goto close_and_summary;
	}

	printf("PHASE25_USER_HCI_RESET_PASS\n");
	fflush(stdout);

	probe_log("PHASE25_USER_STEP_HCI_RLV");
	if (!run_command(sock, mem_fd, active_channel,
			 "HCI_RLV", HCI_OP_READ_LOCAL_VERSION, timeout_ms, &rlv_result)) {
		printf("PHASE25_USER_HCI_RLV_FAIL\n");
		fflush(stdout);
		goto close_and_summary;
	}

	printf("PHASE25_USER_HCI_RLV_VERSION hci_ver=0x%02x hci_rev=0x%04x lmp_ver=0x%02x manufacturer=0x%04x lmp_subver=0x%04x\n",
	       rlv_result.version.hci_ver,
	       le16_to_cpu_u(rlv_result.version.hci_rev),
	       rlv_result.version.lmp_ver,
	       le16_to_cpu_u(rlv_result.version.manufacturer),
	       le16_to_cpu_u(rlv_result.version.lmp_subver));
	printf("PHASE25_USER_HCI_RLV_PASS\n");
	fflush(stdout);

	overall_pass = hci0_present && reset_result.pass && rlv_result.pass;

close_and_summary:
	close(sock);
	if (mem_fd >= 0)
		close(mem_fd);

summary:
	if (overall_pass)
		printf("PHASE25_USER_SMOKE_PASS\n");
	else
		printf("PHASE25_USER_SMOKE_FAIL\n");

	alarm(0);
	fflush(stdout);
	return 0;
}