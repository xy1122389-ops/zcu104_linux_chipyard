#define SYS_openat 56
#define SYS_close 57
#define SYS_mmap 222
#define SYS_exit 93

#define AT_FDCWD -100
#define O_RDWR 2

#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1

#define STAGE_MARK_PA 0x8F000000UL

static long syscall1(long num, long arg0)
{
	register long a7 asm("a7") = num;
	register long a0 asm("a0") = arg0;
	asm volatile("ecall" : "+r"(a0) : "r"(a7) : "memory");
	return a0;
}

static long syscall3(long num, long arg0, long arg1, long arg2)
{
	register long a7 asm("a7") = num;
	register long a0 asm("a0") = arg0;
	register long a1 asm("a1") = arg1;
	register long a2 asm("a2") = arg2;
	asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
	return a0;
}

static long syscall6(long num, long arg0, long arg1, long arg2,
			 long arg3, long arg4, long arg5)
{
	register long a7 asm("a7") = num;
	register long a0 asm("a0") = arg0;
	register long a1 asm("a1") = arg1;
	register long a2 asm("a2") = arg2;
	register long a3 asm("a3") = arg3;
	register long a4 asm("a4") = arg4;
	register long a5 asm("a5") = arg5;
	asm volatile("ecall"
		     : "+r"(a0)
		     : "r"(a1), "r"(a2), "r"(a3), "r"(a4), "r"(a5), "r"(a7)
		     : "memory");
	return a0;
}

static unsigned long long parse_u64(const char *text)
{
	unsigned long long value = 0;
	int base = 10;
	int index = 0;

	if (!text)
		return 0;

	if (text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
		base = 16;
		index = 2;
	}

	for (; text[index]; index++) {
		char ch = text[index];
		unsigned digit;

		if (ch >= '0' && ch <= '9')
			digit = ch - '0';
		else if (base == 16 && ch >= 'a' && ch <= 'f')
			digit = 10 + ch - 'a';
		else if (base == 16 && ch >= 'A' && ch <= 'F')
			digit = 10 + ch - 'A';
		else
			break;

		value = (value * base) + digit;
	}

	return value;
}

void _start(void)
{
	long *stack;
	long argc;
	char **argv;
	unsigned long long stage;
	unsigned long page_base;
	unsigned long page_off;
	long mem_fd;
	void *mapped;
	volatile unsigned long long *slot;

	asm volatile("mv %0, sp" : "=r"(stack));
	argc = stack[0];
	argv = (char **)&stack[1];

	stage = (argc > 1) ? parse_u64(argv[1]) : 0;
	page_base = STAGE_MARK_PA & ~4095UL;
	page_off = STAGE_MARK_PA & 4095UL;

	mem_fd = syscall3(SYS_openat, AT_FDCWD, (long)"/dev/mem", O_RDWR);
	if (mem_fd < 0)
		syscall1(SYS_exit, 2);

	mapped = (void *)syscall6(SYS_mmap, 0, 4096, PROT_READ | PROT_WRITE,
				 MAP_SHARED, mem_fd, page_base);
	if ((long)mapped < 0) {
		syscall1(SYS_close, mem_fd);
		syscall1(SYS_exit, 3);
	}

	slot = (volatile unsigned long long *)((char *)mapped + page_off);
	*slot = stage;
	asm volatile("fence rw, rw" ::: "memory");

	syscall1(SYS_close, mem_fd);
	syscall1(SYS_exit, 0);
}