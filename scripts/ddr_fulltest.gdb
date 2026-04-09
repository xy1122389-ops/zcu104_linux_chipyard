# DDR full 64-bit integrity test after 39-register fix
# Tests: bit-13 aliasing, 2-byte duplication, 64-bit bus width

set confirm off
set pagination off

# Connect
python
import os
port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
end

echo \n=== DDR 64-bit Full Test ===\n

# Test 1: Bit-13 aliasing
echo \n--- Test 1: Bit-13 aliasing ---\n
set *(unsigned int*)0x80010000 = 0x11111111
set *(unsigned int*)0x80012000 = 0x22222222
set *(unsigned int*)0x80020000 = 0x33333333
set *(unsigned int*)0x80024000 = 0x44444444
printf "0x80010000 = 0x%08x (expect 0x11111111)\n", *(unsigned int*)0x80010000
printf "0x80012000 = 0x%08x (expect 0x22222222)\n", *(unsigned int*)0x80012000
printf "0x80020000 = 0x%08x (expect 0x33333333)\n", *(unsigned int*)0x80020000
printf "0x80024000 = 0x%08x (expect 0x44444444)\n", *(unsigned int*)0x80024000

# Test 2: 8-byte (64-bit) write pattern - checks all byte lanes
echo \n--- Test 2: 64-bit bus write (all 8 byte lanes) ---\n
set *(unsigned long long*)0x80030000 = 0x0102030405060708
set *(unsigned long long*)0x80030008 = 0x1112131415161718
set *(unsigned long long*)0x80030010 = 0xA1B2C3D4E5F60718
printf "0x80030000 = 0x%016llx (expect 0x0102030405060708)\n", *(unsigned long long*)0x80030000
printf "0x80030008 = 0x%016llx (expect 0x1112131415161718)\n", *(unsigned long long*)0x80030008
printf "0x80030010 = 0x%016llx (expect 0xA1B2C3D4E5F60718)\n", *(unsigned long long*)0x80030010

# Test 3: Check individual bytes to detect 2-byte duplication
echo \n--- Test 3: Byte-level check (detect 2-byte duplication) ---\n
set *(unsigned long long*)0x80040000 = 0x0807060504030201
printf "Wrote 0x0807060504030201 to 0x80040000\n"
printf "Byte 0: 0x%02x (expect 0x01)\n", *(unsigned char*)0x80040000
printf "Byte 1: 0x%02x (expect 0x02)\n", *(unsigned char*)0x80040001
printf "Byte 2: 0x%02x (expect 0x03)\n", *(unsigned char*)0x80040002
printf "Byte 3: 0x%02x (expect 0x04)\n", *(unsigned char*)0x80040003
printf "Byte 4: 0x%02x (expect 0x05)\n", *(unsigned char*)0x80040004
printf "Byte 5: 0x%02x (expect 0x06)\n", *(unsigned char*)0x80040005
printf "Byte 6: 0x%02x (expect 0x07)\n", *(unsigned char*)0x80040006
printf "Byte 7: 0x%02x (expect 0x08)\n", *(unsigned char*)0x80040007

# Test 4: Write known string pattern - checks if 2-byte dup happens
echo \n--- Test 4: ASCII string pattern ---\n
set *(unsigned long long*)0x80050000 = 0x6867666564636261
set *(unsigned long long*)0x80050008 = 0x706F6E6D6C6B6A69
# "abcdefgh" + "ijklmnop"
printf "0x80050000 = 0x%016llx (expect 0x6867666564636261 = 'abcdefgh')\n", *(unsigned long long*)0x80050000
printf "0x80050008 = 0x%016llx (expect 0x706F6E6D6C6B6A69 = 'ijklmnop')\n", *(unsigned long long*)0x80050008
# Read as 32-bit halves
printf "Lower 32: 0x%08x (expect 0x64636261 = 'abcd')\n", *(unsigned int*)0x80050000
printf "Upper 32: 0x%08x (expect 0x68676665 = 'efgh')\n", *(unsigned int*)0x80050004

# Test 5: Walking address test across cache lines
echo \n--- Test 5: Cross-cacheline test ---\n
set *(unsigned int*)0x80060000 = 0xDEADBEEF
set *(unsigned int*)0x80060040 = 0xCAFEBABE
set *(unsigned int*)0x80060080 = 0x12345678
set *(unsigned int*)0x800600C0 = 0x9ABCDEF0
printf "CL0: 0x%08x (expect 0xDEADBEEF)\n", *(unsigned int*)0x80060000
printf "CL1: 0x%08x (expect 0xCAFEBABE)\n", *(unsigned int*)0x80060040
printf "CL2: 0x%08x (expect 0x12345678)\n", *(unsigned int*)0x80060080
printf "CL3: 0x%08x (expect 0x9ABCDEF0)\n", *(unsigned int*)0x800600C0

echo \n=== DDR Test Complete ===\n
disconnect
quit
