set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("=== parameq + parse_args disassembly ===\n")

# From klog:
# ra = 0xffffffff80031f56 = parameq+0x1e/0x40
# So parameq starts at VA = 0xffffffff80031f38, PA = 0x80231f38
# parameq is 0x40 = 64 bytes

# parse_args+0xe8/0x1f4 -> parse_args = 0xffffffff80032060 - 0xe8 = 0xffffffff80031f78
# parse_args is 0x1f4 = 500 bytes

# Read parameq (64 bytes)
parameq_pa = 0x80231f38
parameq_data = bytes(inf.read_memory(parameq_pa, 64))

print(f"parameq at PA 0x{parameq_pa:08x} (VA 0xffffffff80031f38):")
print(f"  raw: {' '.join(f'{b:02x}' for b in parameq_data)}")

# Disassemble
addr = 0
while addr < 64:
    hw = struct.unpack_from('<H', parameq_data, addr)[0]
    if (hw & 3) == 3:  # 32-bit instruction
        if addr + 2 < 64:
            hw2 = struct.unpack_from('<H', parameq_data, addr + 2)[0]
            insn = (hw2 << 16) | hw
            # Decode some common instructions
            opcode = insn & 0x7f
            rd = (insn >> 7) & 0x1f
            funct3 = (insn >> 12) & 0x7
            rs1 = (insn >> 15) & 0x1f
            rs2 = (insn >> 20) & 0x1f
            imm_i = (insn >> 20)  # I-type immediate (sign-extended)
            if imm_i >= 0x800:
                imm_i -= 0x1000
            
            desc = ""
            rnames = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1',
                      'a0','a1','a2','a3','a4','a5','a6','a7',
                      's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                      't3','t4','t5','t6']
            
            if opcode == 0x13:  # OP-IMM
                if funct3 == 0:
                    if rs1 == 0 and rd == 0:
                        desc = "nop"
                    elif rs1 == 0:
                        desc = f"li {rnames[rd]}, {imm_i}"
                    else:
                        desc = f"addi {rnames[rd]}, {rnames[rs1]}, {imm_i}"
            elif opcode == 0x03:  # LOAD
                ftype = ['lb','lh','lw','ld','lbu','lhu','lwu','?'][funct3]
                desc = f"{ftype} {rnames[rd]}, {imm_i}({rnames[rs1]})"
            elif opcode == 0x23:  # STORE
                imm_s = ((insn >> 25) << 5) | ((insn >> 7) & 0x1f)
                if imm_s >= 0x800:
                    imm_s -= 0x1000
                ftype = ['sb','sh','sw','sd','?','?','?','?'][funct3]
                desc = f"{ftype} {rnames[rs2]}, {imm_s}({rnames[rs1]})"
            elif opcode == 0x6f:  # JAL
                desc = f"jal {rnames[rd]}, ..."
            elif opcode == 0x67:  # JALR
                desc = f"jalr {rnames[rd]}, {imm_i}({rnames[rs1]})"
            elif opcode == 0x63:  # BRANCH
                ftype = ['beq','bne','?','?','blt','bge','bltu','bgeu'][funct3]
                desc = f"{ftype} {rnames[rs1]}, {rnames[rs2]}, ..."
            elif opcode == 0x33:  # OP
                funct7 = insn >> 25
                if funct7 == 0:
                    ops = ['add','sll','slt','sltu','xor','srl','or','and']
                    desc = f"{ops[funct3]} {rnames[rd]}, {rnames[rs1]}, {rnames[rs2]}"
                elif funct7 == 0x20:
                    ops = ['sub','?','?','?','?','sra','?','?']
                    desc = f"{ops[funct3]} {rnames[rd]}, {rnames[rs1]}, {rnames[rs2]}"
            
            va = 0xffffffff80031f38 + addr
            print(f"  +0x{addr:02x} ({va:016x}): 0x{insn:08x}  {desc}")
            addr += 4
        else:
            break
    else:  # 16-bit C-ext
        # Decode some compressed instructions
        desc = ""
        op = hw & 3
        funct3_c = (hw >> 13) & 7
        
        if op == 2:  # C2 quadrant
            funct4 = (hw >> 12) & 0xf
            rd = (hw >> 7) & 0x1f
            rs2 = (hw >> 2) & 0x1f
            rnames = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1',
                      'a0','a1','a2','a3','a4','a5','a6','a7',
                      's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                      't3','t4','t5','t6']
            if funct4 == 8 and rs2 != 0:
                desc = f"c.mv {rnames[rd]}, {rnames[rs2]}"
            elif funct4 == 9 and rs2 != 0:
                desc = f"c.add {rnames[rd]}, {rnames[rs2]}"
            elif funct4 == 9 and rs2 == 0 and rd != 0:
                desc = f"c.jalr {rnames[rd]}"
            elif funct4 == 8 and rs2 == 0 and rd != 0:
                desc = f"c.jr {rnames[rd]}"
            elif funct3_c == 2:
                # C.LDSP
                imm = ((hw >> 5) & 0x3) << 6 | ((hw >> 12) & 1) << 5 | ((hw >> 2) & 0x7) << 3
                desc = f"c.ldsp {rnames[rd]}, {imm}(sp)"
            elif funct3_c == 7:
                # C.SDSP
                imm = ((hw >> 7) & 0x7) << 3 | ((hw >> 10) & 0x7) << 6
                desc = f"c.sdsp {rnames[rs2]}, {imm}(sp)"
        elif op == 1:  # C1 quadrant
            if funct3_c == 0:  # C.NOP / C.ADDI
                rd = (hw >> 7) & 0x1f
                imm = ((hw >> 12) & 1) << 5 | ((hw >> 2) & 0x1f)
                if imm >= 32:
                    imm -= 64
                rnames_l = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1',
                          'a0','a1','a2','a3','a4','a5','a6','a7',
                          's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                          't3','t4','t5','t6']
                if rd == 0:
                    desc = "c.nop"
                else:
                    desc = f"c.addi {rnames_l[rd]}, {imm}"
            elif funct3_c == 5:
                desc = "c.j ..."
            elif funct3_c == 6:
                desc = "c.beqz ..."
            elif funct3_c == 7:
                desc = "c.bnez ..."
            elif funct3_c == 1:
                rd = (hw >> 7) & 0x1f
                desc = f"c.addiw {rnames[rd]}, ..."
            elif funct3_c == 3:
                rd = (hw >> 7) & 0x1f
                rnames_l = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1',
                          'a0','a1','a2','a3','a4','a5','a6','a7',
                          's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                          't3','t4','t5','t6']
                if rd == 2:
                    desc = "c.addi16sp ..."
                else:
                    desc = f"c.lui {rnames_l[rd]}, ..."
        elif op == 0:  # C0 quadrant
            if funct3_c == 0:
                desc = "c.addi4spn ..."
            elif funct3_c == 3:
                desc = "c.ld ..."
            elif funct3_c == 7:
                desc = "c.sd ..."
        
        va = 0xffffffff80031f38 + addr
        rnames = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1',
                  'a0','a1','a2','a3','a4','a5','a6','a7',
                  's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                  't3','t4','t5','t6']
        print(f"  +0x{addr:02x} ({va:016x}): 0x{hw:04x}      {desc}")
        addr += 2

# Also read strlen code from DDR (unpatched) for reference
print(f"\nstrlen at PA 0x804fda58 (VA 0xffffffff802fda58):")
strlen_data = bytes(inf.read_memory(0x804fda58, 28))
print(f"  raw: {' '.join(f'{b:02x}' for b in strlen_data)}")

# Read a bit of parse_args around the call to parameq
# parse_args at VA 0xffffffff80031f78, PA 0x80231f78
# The call to parameq is at or near parse_args+0xe6 (since return = parse_args+0xe8)
parse_args_call_pa = 0x80231f78 + 0xd0  # a bit before +0xe8
pa_data = bytes(inf.read_memory(parse_args_call_pa, 48))
print(f"\nparse_args+0xd0..+0xff at PA 0x{parse_args_call_pa:08x}:")
print(f"  raw: {' '.join(f'{b:02x}' for b in pa_data)}")

gdb.execute("disconnect")
end
quit
