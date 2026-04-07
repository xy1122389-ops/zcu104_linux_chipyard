#define SYS_openat 56
#define SYS_close 57
#define SYS_write 64
#define SYS_dup3 24
#define SYS_nanosleep 101
#define SYS_exit 93

#define AT_FDCWD -100
#define O_RDWR 2

struct timespec64 {
    long tv_sec;
    long tv_nsec;
};

static long syscall0(long num) {
    register long a7 asm("a7") = num;
    register long a0 asm("a0");
    asm volatile("ecall" : "=r"(a0) : "r"(a7) : "memory");
    return a0;
}

static long syscall1(long num, long arg0) {
    register long a7 asm("a7") = num;
    register long a0 asm("a0") = arg0;
    asm volatile("ecall" : "+r"(a0) : "r"(a7) : "memory");
    return a0;
}

static long syscall3(long num, long arg0, long arg1, long arg2) {
    register long a7 asm("a7") = num;
    register long a0 asm("a0") = arg0;
    register long a1 asm("a1") = arg1;
    register long a2 asm("a2") = arg2;
    asm volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
    return a0;
}

static long cstr_len(const char *s) {
    long n = 0;
    while (s[n]) {
        n++;
    }
    return n;
}

static void write_str(int fd, const char *s) {
    syscall3(SYS_write, fd, (long)s, cstr_len(s));
}

void _start(void) {
    const char *console = "/dev/console";
    const char *kmsg = "/dev/kmsg";
    const char *banner = "=== Minimal Linux booted successfully ===\n";
    const char *detail = "minimal init: reached userspace, looping forever\n";
    long console_fd = syscall3(SYS_openat, AT_FDCWD, (long)console, O_RDWR);

    if (console_fd >= 0) {
        syscall3(SYS_dup3, console_fd, 0, 0);
        syscall3(SYS_dup3, console_fd, 1, 0);
        syscall3(SYS_dup3, console_fd, 2, 0);
        if (console_fd > 2) {
            syscall1(SYS_close, console_fd);
        }
    }

    write_str(1, banner);
    write_str(1, detail);

    long kmsg_fd = syscall3(SYS_openat, AT_FDCWD, (long)kmsg, O_RDWR);
    if (kmsg_fd >= 0) {
        write_str((int)kmsg_fd, banner);
        write_str((int)kmsg_fd, detail);
        syscall1(SYS_close, kmsg_fd);
    }

    for (;;) {
        struct timespec64 ts;
        ts.tv_sec = 1;
        ts.tv_nsec = 0;
        syscall3(SYS_nanosleep, (long)&ts, 0, 0);
    }

    syscall1(SYS_exit, 0);
    syscall0(SYS_exit);
}
