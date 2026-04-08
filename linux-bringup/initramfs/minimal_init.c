#define SYS_openat 56
#define SYS_close 57
#define SYS_write 64
#define SYS_dup3 24
#define SYS_mmap 222
#define SYS_nanosleep 101
#define SYS_exit 93

#define AT_FDCWD -100
#define O_RDWR 2

#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_SHARED 1

#define INIT_MAGIC_PA 0x8F000000UL
#define INIT_MAGIC_VALUE 0x5A435531494E4954ULL

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

static long syscall6(long num, long arg0, long arg1, long arg2, long arg3, long arg4, long arg5) {
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
    const char *devmem = "/dev/mem";
    const char *banner = "=== Minimal Linux booted successfully ===\n";
    const char *detail = "minimal init: writing magic to 0x8F000000, then looping forever\n";
    const char *map_ok = "minimal init: /dev/mem magic write complete\n";
    const char *map_fail = "minimal init: /dev/mem mmap failed\n";
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
    }

    long mem_fd = syscall3(SYS_openat, AT_FDCWD, (long)devmem, O_RDWR);
    if (mem_fd >= 0) {
        void *mapped = (void *)syscall6(SYS_mmap, 0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, INIT_MAGIC_PA);
        if ((long)mapped >= 0) {
            volatile unsigned long long *magic = (volatile unsigned long long *)mapped;
            *magic = INIT_MAGIC_VALUE;
            asm volatile("fence rw, rw" ::: "memory");
            write_str(1, map_ok);
            if (kmsg_fd >= 0) {
                write_str((int)kmsg_fd, map_ok);
            }
        } else {
            write_str(1, map_fail);
            if (kmsg_fd >= 0) {
                write_str((int)kmsg_fd, map_fail);
            }
        }
        syscall1(SYS_close, mem_fd);
    }

    if (kmsg_fd >= 0) {
        syscall1(SYS_close, kmsg_fd);
    }

    for (;;) {
        asm volatile("fence rw, rw" ::: "memory");
    }

    syscall1(SYS_exit, 0);
    syscall0(SYS_exit);
}
