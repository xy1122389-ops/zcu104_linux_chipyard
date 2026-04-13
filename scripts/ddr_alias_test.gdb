# ddr_alias_test.gdb — Quick DDR bit-13 aliasing test
# Tests whether writing to 0x80002000 (bit-13 offset) overwrites 0x80000000
# If DDR is 32-bit mode, addresses alias at bit-13 → this test fails.
# If DDR is 64-bit mode, addresses are distinct → test passes.

set pagination off
set confirm off
set remotetimeout 30

python
import os
jlink_host = os.environ.get("JLINK_HOST", "172.19.128.1")
jlink_port = os.environ.get("JLINK_PORT", "2331")
gdb.execute(f"target extended-remote {jlink_host}:{jlink_port}")
end

echo \n=== DDR Bit-13 Aliasing Test ===\n

# Write distinct patterns to addr and addr+0x2000 (bit-13 offset)
set {long}0x80000000 = 0xDEADBEEF12345678
set {long}0x80002000 = 0xCAFEBABE87654321

# Read back the first address
set $val0 = *(unsigned long long *)0x80000000
set $val1 = *(unsigned long long *)0x80002000

printf "0x80000000 = 0x%016llx (expect 0xDEADBEEF12345678)\n", $val0
printf "0x80002000 = 0x%016llx (expect 0xCAFEBABE87654321)\n", $val1

python
v0 = int(gdb.parse_and_eval("$val0"))
v1 = int(gdb.parse_and_eval("$val1"))
# Handle sign extension
v0 = v0 & 0xFFFFFFFFFFFFFFFF
v1 = v1 & 0xFFFFFFFFFFFFFFFF
if v0 == 0xDEADBEEF12345678 and v1 == 0xCAFEBABE87654321:
    print("\n✅ PASS: No aliasing detected. DDR 64-bit mode is working correctly.")
elif v0 == v1:
    print(f"\n❌ FAIL: Aliasing detected! Both read 0x{v0:016X}. DDR still in 32-bit mode.")
else:
    print(f"\n⚠️  UNEXPECTED: 0x80000000=0x{v0:016X}, 0x80002000=0x{v1:016X}")
    print("   Values are different but don't match expected. Check SBA access.")
end

# Also test a few more bit positions to be thorough
echo \n=== Extended bit tests ===\n
set {long}0x80000000 = 0xAAAAAAAAAAAAAAAA
set {long}0x80001000 = 0xBBBBBBBBBBBBBBBB
set {long}0x80004000 = 0xCCCCCCCCCCCCCCCC
set {long}0x80008000 = 0xDDDDDDDDDDDDDDDD

set $t0 = *(unsigned long long *)0x80000000
set $t1 = *(unsigned long long *)0x80001000
set $t2 = *(unsigned long long *)0x80004000
set $t3 = *(unsigned long long *)0x80008000

printf "0x80000000 = 0x%016llx (expect AAAA...)\n", $t0
printf "0x80001000 = 0x%016llx (expect BBBB...)\n", $t1
printf "0x80004000 = 0x%016llx (expect CCCC...)\n", $t2
printf "0x80008000 = 0x%016llx (expect DDDD...)\n", $t3

python
t0 = int(gdb.parse_and_eval("$t0")) & 0xFFFFFFFFFFFFFFFF
t1 = int(gdb.parse_and_eval("$t1")) & 0xFFFFFFFFFFFFFFFF
t2 = int(gdb.parse_and_eval("$t2")) & 0xFFFFFFFFFFFFFFFF
t3 = int(gdb.parse_and_eval("$t3")) & 0xFFFFFFFFFFFFFFFF
ok = True
for name, val, expect in [("0x80000000", t0, 0xAAAAAAAAAAAAAAAA),
                           ("0x80001000", t1, 0xBBBBBBBBBBBBBBBB),
                           ("0x80004000", t2, 0xCCCCCCCCCCCCCCCC),
                           ("0x80008000", t3, 0xDDDDDDDDDDDDDDDD)]:
    if val != expect:
        print(f"  ❌ {name}: got 0x{val:016X}, expected 0x{expect:016X}")
        ok = False
if ok:
    print("✅ All extended bit tests PASS")
else:
    print("❌ Some extended bit tests FAILED - address aliasing present")
end

echo \n=== Test complete ===\n
disconnect
quit
