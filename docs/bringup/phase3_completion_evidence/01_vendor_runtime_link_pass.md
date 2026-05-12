# Phase3 Evidence 01: Vendor Runtime Link Pass

Status: local link evidence only.
Date: 2026-05-13 local run.

```text
PHASE3_VENDOR_RUNTIME_LINK=PASS
NO_VENDOR_SOURCE_COMMITTED=PASS
```

## Scope

This evidence proves that the approved local CEVA BT5.2 vendor runtime sources can be compiled and linked into a complete RV32 firmware ELF in the local probe workspace.

It does not claim `rwip_init()` execution, `rwip_driver_init()` execution, real HCI Reset/RLV response, Linux HCI RX delivery, or Phase3 completion. Those remain gated by evidence files 02 through 07.

## Local Inputs

Approved local vendor SW root:

```text
/mnt/e/桌面/CEVA_BT5.2/home/user007/project/CEVA_BT5.2/rw-btdm-blehost-sw-v11_0_3
```

Temporary probe workspace:

```text
/tmp/ceva_phase3_vendor_py2_probe
```

The temporary workspace contains local-only build wrappers and freestanding stubs used to complete the link with the available Chipyard RISC-V toolchain. No CEVA source, generated vendor object, firmware ELF, firmware BIN, or vendor binary is committed to this repository.

## Build Command

```bash
cd /tmp/ceva_phase3_vendor_py2_probe
export PATH=/tmp/ceva_phase3_vendor_py2_probe/riscv/bin:$PATH
riscv32-unknown-elf-gcc -c -march=rv32imc -mabi=ilp32 -mcmodel=medlow -ffreestanding -fno-builtin -Os freestanding_stubs.c -o freestanding_stubs.o
cd /tmp/ceva_phase3_vendor_py2_probe/sw/src/config
export RISCV=/tmp/ceva_phase3_vendor_py2_probe/riscv
python2 /tmp/ceva_phase3_vendor_py2_probe/sw/src/tools/scons.py . PRODUCT=btdm PLF=bluegrip BT=riscv32-gcc BUILD_DIR=/tmp/ceva_phase3_vendor_py2_probe/build
```

Successful output summary:

```text
LINK_RC=0
/tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.elf created
/tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.bin created
```

## Artifact Proof

```text
/tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.elf: ELF 32-bit LSB executable, UCB RISC-V, RVC, soft-float ABI, version 1 (SYSV), statically linked, with debug_info, not stripped
/tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.bin: data
```

Hashes:

```text
ad4b1ff3df07284b7fbff03ec2d2f405cf5d4ed084ef5db39d2c73ae5419c225  /tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.elf
de45d374774fb43979151da02cc848fabb60103ed64f93a10c63676f7251bb68  /tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.bin
2f4d5a83a772c1fec32983fa667972a98267534cfa8003ccf1c78ade3c6abcdb  /tmp/ceva_phase3_vendor_py2_probe/freestanding_stubs.o
```

ELF header excerpt:

```text
Class:                             ELF32
Data:                              2's complement, little endian
Type:                              EXEC (Executable file)
Machine:                           RISC-V
Entry point address:               0x0
Flags:                             0x1, RVC, soft-float ABI
Number of program headers:         4
Number of section headers:         21
```

Undefined-symbol check:

```text
riscv64-unknown-elf-nm -u /tmp/ceva_phase3_vendor_py2_probe/build/btdm-bluegrip/fw.elf
# no output
```

## Runtime Symbol Proof

Required vendor-runtime anchor symbols are present in the linked ELF:

```text
000000dc T _start
00000b90 T rwip_init
000011d6 T rwip_driver_init
0000b8c0 T h4tl_init
0000c2dc T main
000765ac T hci_send_2_host
00077a64 T hci_tl_send
00077e06 T hci_cmd_received
```

The link includes generated object groups for `rwip`, `rwip_driver`, `ke`, `co`, `h4tl`, `hci`, `sch`, BT LL/LM/LC/LD/LB, BLE LL/LLM/LLI/LLC/LLD, generated register headers under the temporary build tree, and platform glue for BlueGRiP.

## Local Link Adjustments

The probe used local-only wrappers under `/tmp/ceva_phase3_vendor_py2_probe/riscv/bin` to map the vendor build's expected `riscv32-unknown-elf-*` commands onto the available Chipyard RISC-V tools. The wrappers also normalized `rv32imc` to `rv32imc_zicsr` so CSR instructions assemble correctly.

The temporary linker script copy had `INPUT(-lc)` and `INPUT(-lgcc)` removed because the available Chipyard toolchain does not provide matching RV32 multilib standard libraries. The probe instead linked a local freestanding stub object for the small set of C/libgcc surface symbols required by the full vendor runtime link. This is link-enablement evidence, not final production runtime policy.

## Repository Cleanliness

`git status --short` at evidence capture time:

```text
 M linux-bringup/dtb/chipyard-zcu104-fedora.dtb
 M linux-bringup/dtb/chipyard-zcu104-fedora.dts
 M scripts/run_ps_ddr_init.tcl
```

These are pre-existing protected local files and are not part of this evidence. No CEVA vendor source, generated vendor object, firmware ELF, firmware BIN, or restricted binary is staged or committed by this evidence file.
