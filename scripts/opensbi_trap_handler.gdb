set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("=== OpenSBI trap handler analysis ===\n")

# Read mtvec CSR - J-Link can read M-mode CSRs
try:
    out = gdb.execute("monitor ReadCSR 0x305", to_string=True).strip()
    print(f"mtvec = {out}")
except:
    print("Cannot read mtvec via monitor")

# Read mideleg to check interrupt delegation
try:
    out = gdb.execute("monitor ReadCSR 0x303", to_string=True).strip()
    print(f"mideleg = {out}")
except:
    print("Cannot read mideleg via monitor")

# Read mcause
try:
    out = gdb.execute("monitor ReadCSR 0x342", to_string=True).strip()
    print(f"mcause = {out}")
except:
    print("Cannot read mcause via monitor")

# The OpenSBI trap handler is at mtvec. Let's read it.
# mtvec is typically 0x80000000 or similar for OpenSBI
# Let's try reading from 0x80000000 (start of OpenSBI)
# First, find the trap handler by reading mtvec

# Parse mtvec value
try:
    out = gdb.execute("monitor ReadCSR 0x305", to_string=True).strip()
    # Extract hex value
    import re
    m = re.search(r'(?:0x|= )([0-9A-Fa-f]+)', out)
    if m:
        mtvec_val = int(m.group(1), 16)
        mtvec_base = mtvec_val & ~3  # Clear mode bits
        mtvec_mode = mtvec_val & 3   # 0=Direct, 1=Vectored
        print(f"\nmtvec base = 0x{mtvec_base:016x}, mode = {mtvec_mode} ({'Direct' if mtvec_mode == 0 else 'Vectored'})")
        
        # Read trap handler code (256 bytes)
        handler_data = bytes(inf.read_memory(mtvec_base, 256))
        print(f"\nTrap handler at 0x{mtvec_base:08x}:")
        
        # Disassemble looking for t1 (x6) saves and restores
        rnames = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1',
                  'a0','a1','a2','a3','a4','a5','a6','a7',
                  's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                  't3','t4','t5','t6']
        
        addr = 0
        insn_list = []
        while addr < 256:
            hw = struct.unpack_from('<H', handler_data, addr)[0]
            if (hw & 3) == 3:  # 32-bit
                if addr + 2 < 256:
                    hw2 = struct.unpack_from('<H', handler_data, addr + 2)[0]
                    insn = (hw2 << 16) | hw
                    
                    opcode = insn & 0x7f
                    rd = (insn >> 7) & 0x1f
                    funct3 = (insn >> 12) & 0x7
                    rs1 = (insn >> 15) & 0x1f
                    rs2 = (insn >> 20) & 0x1f
                    
                    desc = ""
                    if opcode == 0x23:  # STORE
                        imm_s = ((insn >> 25) << 5) | ((insn >> 7) & 0x1f)
                        if imm_s >= 0x800: imm_s -= 0x1000
                        ftype = ['sb','sh','sw','sd','?','?','?','?'][funct3]
                        desc = f"{ftype} {rnames[rs2]}, {imm_s}({rnames[rs1]})"
                    elif opcode == 0x03:  # LOAD
                        imm_i = insn >> 20
                        if imm_i >= 0x800: imm_i -= 0x1000
                        ftype = ['lb','lh','lw','ld','lbu','lhu','lwu','?'][funct3]
                        desc = f"{ftype} {rnames[rd]}, {imm_i}({rnames[rs1]})"
                    elif opcode == 0x73:  # SYSTEM (CSR)
                        csr = (insn >> 20) & 0xFFF
                        csr_names = {0x300: 'mstatus', 0x302: 'medeleg', 0x303: 'mideleg',
                                     0x305: 'mtvec', 0x340: 'mscratch', 0x341: 'mepc',
                                     0x342: 'mcause', 0x343: 'mtval', 0x344: 'mip',
                                     0x180: 'satp', 0x100: 'sstatus', 0x141: 'sepc',
                                     0x142: 'scause', 0x143: 'stval', 0x144: 'sip',
                                     0x105: 'stvec', 0x140: 'sscratch'}
                        csr_name = csr_names.get(csr, f'0x{csr:03x}')
                        if funct3 == 1:
                            desc = f"csrrw {rnames[rd]}, {csr_name}, {rnames[rs1]}"
                        elif funct3 == 2:
                            desc = f"csrrs {rnames[rd]}, {csr_name}, {rnames[rs1]}"
                        elif funct3 == 3:
                            desc = f"csrrc {rnames[rd]}, {csr_name}, {rnames[rs1]}"
                        elif funct3 == 5:
                            desc = f"csrrwi {rnames[rd]}, {csr_name}, {rs1}"
                        elif funct3 == 6:
                            desc = f"csrrsi {rnames[rd]}, {csr_name}, {rs1}"
                        elif funct3 == 0:
                            if insn == 0x30200073:
                                desc = "mret"
                            elif insn == 0x10200073:
                                desc = "sret"
                            elif insn == 0x00000073:
                                desc = "ecall"
                            elif insn == 0x00100073:
                                desc = "ebreak"
                            elif insn == 0x10500073:
                                desc = "wfi"
                            else:
                                desc = f"system 0x{insn:08x}"
                    elif opcode == 0x13:  # OP-IMM
                        imm_i = insn >> 20
                        if imm_i >= 0x800: imm_i -= 0x1000
                        if funct3 == 0:
                            if rs1 == 0 and rd == 0:
                                desc = "nop"
                            elif rs1 == 0:
                                desc = f"li {rnames[rd]}, {imm_i}"
                            else:
                                desc = f"addi {rnames[rd]}, {rnames[rs1]}, {imm_i}"
                        elif funct3 == 4:
                            desc = f"xori {rnames[rd]}, {rnames[rs1]}, {imm_i}"
                        elif funct3 == 6:
                            desc = f"ori {rnames[rd]}, {rnames[rs1]}, {imm_i}"
                        elif funct3 == 7:
                            desc = f"andi {rnames[rd]}, {rnames[rs1]}, {imm_i}"
                        elif funct3 == 1:
                            desc = f"slli {rnames[rd]}, {rnames[rs1]}, {rs2}"
                        elif funct3 == 5:
                            desc = f"srli/srai {rnames[rd]}, {rnames[rs1]}, {rs2}"
                    elif opcode == 0x33:  # OP
                        funct7 = insn >> 25
                        ops = {(0,0):'add',(0x20,0):'sub',(0,1):'sll',(0,2):'slt',
                               (0,3):'sltu',(0,4):'xor',(0,5):'srl',(0x20,5):'sra',
                               (0,6):'or',(0,7):'and'}
                        op_name = ops.get((funct7, funct3), f'op{funct7}_{funct3}')
                        desc = f"{op_name} {rnames[rd]}, {rnames[rs1]}, {rnames[rs2]}"
                    elif opcode == 0x6f:  # JAL
                        desc = f"jal {rnames[rd]}, ..."
                    elif opcode == 0x67:  # JALR
                        desc = f"jalr {rnames[rd]}, {insn >> 20}({rnames[rs1]})"
                    elif opcode == 0x63:  # BRANCH
                        bops = ['beq','bne','?','?','blt','bge','bltu','bgeu']
                        desc = f"{bops[funct3]} {rnames[rs1]}, {rnames[rs2]}, ..."
                    elif opcode == 0x37:  # LUI
                        desc = f"lui {rnames[rd]}, 0x{(insn >> 12) & 0xFFFFF:05x}"
                    elif opcode == 0x17:  # AUIPC
                        desc = f"auipc {rnames[rd]}, 0x{(insn >> 12) & 0xFFFFF:05x}"
                    
                    # Highlight t1 (x6) references
                    marker = ""
                    if rd == 6 or rs1 == 6 or rs2 == 6:
                        marker = " <<<< T1"
                    if 'mcause' in desc:
                        marker = " <<<< MCAUSE"
                    
                    va = mtvec_base + addr
                    insn_list.append(f"  0x{va:08x} (+{addr:3d}): 0x{insn:08x}  {desc}{marker}")
                    addr += 4
                else:
                    break
            else:  # 16-bit compressed
                desc = f"C:0x{hw:04x}"
                # Basic compressed decoding
                op = hw & 3
                funct3_c = (hw >> 13) & 7
                if op == 2:
                    funct4 = (hw >> 12) & 0xf
                    rd_c = (hw >> 7) & 0x1f
                    rs2_c = (hw >> 2) & 0x1f
                    if funct4 == 8 and rs2_c != 0:
                        desc = f"c.mv {rnames[rd_c]}, {rnames[rs2_c]}"
                    elif funct4 == 9 and rs2_c != 0:
                        desc = f"c.add {rnames[rd_c]}, {rnames[rs2_c]}"
                    elif funct4 == 8 and rs2_c == 0 and rd_c != 0:
                        desc = f"c.jr {rnames[rd_c]}"
                    elif funct4 == 9 and rs2_c == 0 and rd_c != 0:
                        desc = f"c.jalr {rnames[rd_c]}"
                    elif funct3_c == 2:
                        desc = f"c.ldsp {rnames[rd_c]}, ?(sp)"
                    elif funct3_c == 7:
                        desc = f"c.sdsp {rnames[rs2_c]}, ?(sp)"
                elif op == 0:
                    if funct3_c == 3:
                        desc = "c.ld ..."
                    elif funct3_c == 7:
                        desc = "c.sd ..."
                elif op == 1:
                    if funct3_c == 0:
                        rd_c = (hw >> 7) & 0x1f
                        imm = ((hw >> 12) & 1) << 5 | ((hw >> 2) & 0x1f)
                        if imm >= 32: imm -= 64
                        if rd_c == 0:
                            desc = "c.nop"
                        else:
                            desc = f"c.addi {rnames[rd_c]}, {imm}"
                    elif funct3_c == 3:
                        rd_c = (hw >> 7) & 0x1f
                        if rd_c == 2:
                            desc = "c.addi16sp ..."
                    elif funct3_c == 5:
                        desc = "c.j ..."
                
                marker = ""
                # Check if compressed insn references t1
                if 't1' in desc:
                    marker = " <<<< T1"
                
                va = mtvec_base + addr
                insn_list.append(f"  0x{va:08x} (+{addr:3d}): 0x{hw:04x}      {desc}{marker}")
                addr += 2
        
        for line in insn_list:
            print(line)
    else:
        print("Could not parse mtvec value")
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

gdb.execute("disconnect")
end
quit
