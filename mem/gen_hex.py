#!/usr/bin/env python3
# asm_to_mem.py
# Simple RISC-V assembler + Simulator -> mem_initial_contents.hex
# Usage: python asm_to_mem.py [inputfile]

import sys
import re
import argparse

# --- Cấu hình thanh ghi ---
REGS = {
    **{f'x{i}': i for i in range(32)},
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,
    's0':8,'fp':8,'s1':9,'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
    's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
    't3':28,'t4':29,'t5':30,'t6':31
}

def regnum(r):
    r = r.strip()
    if r in REGS: return REGS[r]
    if re.match(r'^x\d+$', r):
        val = int(r[1:])
        if 0<=val<32: return val
    raise ValueError(f"Unknown register '{r}'")

def parse_imm(s):
    s = s.strip()
    if s.startswith('0x') or s.startswith('-0x'): return int(s, 16)
    return int(s, 0)

def mask(x, bits):
    return x & ((1<<bits)-1)

def sign_extend(x, bits):
    sign = 1 << (bits-1)
    return (x & (sign-1)) - (x & sign)

# --- Encoder Functions (Giữ nguyên) ---
def encode_R(funct7, funct3, opcode, rd, rs1, rs2):
    return ((funct7 & 0x7f) << 25) | ((rs2 & 0x1f) << 20) | ((rs1 & 0x1f) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1f) << 7) | (opcode & 0x7f)

def encode_I(imm, funct3, opcode, rd, rs1):
    imm12 = mask(imm, 12)
    return ((imm12 & 0xfff) << 20) | ((rs1 & 0x1f) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1f) << 7) | (opcode & 0x7f)

def encode_S(imm, funct3, opcode, rs1, rs2):
    imm12 = mask(imm, 12)
    imm11_5 = (imm12 >> 5) & 0x7f
    imm4_0  = imm12 & 0x1f
    return ((imm11_5 & 0x7f) << 25) | ((rs2 & 0x1f) << 20) | ((rs1 & 0x1f) << 15) | ((funct3 & 0x7) << 12) | ((imm4_0 & 0x1f) << 7) | (opcode & 0x7f)

def encode_B(imm, funct3, opcode, rs1, rs2):
    imm12 = mask(imm, 13)
    bit12 = (imm12 >> 12) & 0x1
    bits10_5 = (imm12 >> 5) & 0x3f
    bits4_1 = (imm12 >> 1) & 0x0f
    bit11 = (imm12 >> 11) & 0x1
    return (bit12 << 31) | (bits10_5 << 25) | ((rs2 & 0x1f) << 20) | ((rs1 & 0x1f) << 15) | ((funct3 & 0x7) << 12) | (bits4_1 << 8) | (bit11 << 7) | (opcode & 0x7f)

def encode_U(imm, opcode, rd):
    if imm % 4096 == 0: imm20 = mask(imm >> 12, 20)
    else: imm20 = mask(imm, 20)
    return (imm20 << 12) | ((rd & 0x1f) << 7) | (opcode & 0x7f)

def encode_J(imm, opcode, rd):
    imm20 = mask(imm, 21)
    bit20 = (imm20 >> 20) & 0x1
    bits10_1 = (imm20 >> 1) & 0x3ff
    bit11 = (imm20 >> 11) & 0x1
    bits19_12 = (imm20 >> 12) & 0xff
    return (bit20 << 31) | (bits19_12 << 12) | (bit11 << 20) | (bits10_1 << 21) | ((rd & 0x1f) << 7) | (opcode & 0x7f)

# --- Constants ---
OPC = {
    'LUI': 0x37, 'AUIPC': 0x17, 'JAL': 0x6f, 'JALR': 0x67, 'BRANCH': 0x63,
    'LOAD': 0x03, 'STORE': 0x23, 'OP-IMM': 0x13, 'OP': 0x33,
}
FUNCT3 = {
    'ADD_SUB': 0x0, 'SLL': 0x1, 'SLT': 0x2, 'SLTU':0x3, 'XOR': 0x4,
    'SRL_SRA':0x5, 'OR': 0x6, 'AND':0x7,
    'BEQ':0x0,'BNE':0x1,'BLT':0x4,'BGE':0x5,'BLTU':0x6,'BGEU':0x7,
    'LB':0x0,'LH':0x1,'LW':0x2,'LBU':0x4,'LHU':0x5, 'SB':0x0,'SH':0x1,'SW':0x2
}

def assemble_line(line):
    line = line.split('#',1)[0].strip()
    if not line: return None
    line = line.replace(',', ' ').replace('(', ' ( ').replace(')', ' ) ')
    toks = line.split()
    op = toks[0].lower()
    try:
        if op == 'lui':
            rd = regnum(toks[1]); imm = parse_imm(toks[2])
            word = encode_U(imm, OPC['LUI'], rd)
        elif op == 'auipc':
            rd = regnum(toks[1]); imm = parse_imm(toks[2])
            word = encode_U(imm, OPC['AUIPC'], rd)
        elif op == 'jal':
            rd = regnum(toks[1]); imm = parse_imm(toks[2])
            word = encode_J(imm, OPC['JAL'], rd)
        elif op == 'jalr':
            rd = regnum(toks[1]); rs1 = regnum(toks[2]); imm = parse_imm(toks[3])
            word = encode_I(imm, 0x0, OPC['JALR'], rd, rs1)
        elif op in ('addi','xori','ori','andi'):
            rd = regnum(toks[1]); rs1 = regnum(toks[2]); imm = parse_imm(toks[3])
            f3 = {'addi':0x0, 'xori':0x4, 'ori':0x6, 'andi':0x7}[op]
            word = encode_I(imm, f3, OPC['OP-IMM'], rd, rs1)
        elif op in ('slli','srli','srai'):
            rd = regnum(toks[1]); rs1 = regnum(toks[2]); sh = parse_imm(toks[3])
            funct3 = 0x1 if op=='slli' else 0x5
            funct7 = 0x00 if op=='slli' or op=='srli' else 0x20
            imm12 = (funct7 << 5) | (sh & 0x1f)
            word = ((imm12 & 0xfff) << 20) | ((rs1 & 0x1f) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1f) << 7) | (OPC['OP-IMM'] & 0x7f)
        elif op in ('add','sub','sll','slt','sltu','xor','srl','sra','or','and'):
            rd = regnum(toks[1]); rs1 = regnum(toks[2]); rs2 = regnum(toks[3])
            funct3 = {'add':0x0,'sub':0x0,'sll':0x1,'slt':0x2,'sltu':0x3,'xor':0x4,'srl':0x5,'sra':0x5,'or':0x6,'and':0x7}[op]
            funct7 = 0x20 if op in ('sub','sra') else 0x00
            word = encode_R(funct7, funct3, OPC['OP'], rd, rs1, rs2)
        elif op in ('lw','lb','lh','lbu','lhu'):
            rd = regnum(toks[1])
            if '(' in toks:
                i = toks.index('(')
                imm = parse_imm(toks[2]) if i==2 else parse_imm(toks[i-1])
                rs1 = regnum(toks[i+1])
            else:
                imm = parse_imm(toks[2]); rs1 = regnum(toks[3])
            funct3 = FUNCT3['LW'] if op=='lw' else FUNCT3.get(op.upper(), 0)
            word = encode_I(imm, funct3, OPC['LOAD'], rd, rs1)
        elif op in ('sw','sb','sh'):
            rs2 = regnum(toks[1])
            if '(' in toks:
                i = toks.index('(')
                imm = parse_imm(toks[2]) if i==2 else parse_imm(toks[i-1])
                rs1 = regnum(toks[i+1])
            else:
                imm = parse_imm(toks[2]); rs1 = regnum(toks[3])
            funct3 = FUNCT3['SW']
            word = encode_S(imm, funct3, OPC['STORE'], rs1, rs2)
        elif op in ('beq','bne','blt','bge','bltu','bgeu'):
            rs1 = regnum(toks[1]); rs2 = regnum(toks[2]); imm = parse_imm(toks[3])
            funct3 = FUNCT3[op.upper()]
            word = encode_B(imm, funct3, OPC['BRANCH'], rs1, rs2)
        elif op in ('div','divu','rem','remu','mul'):
            rd = regnum(toks[1]); rs1 = regnum(toks[2]); rs2 = regnum(toks[3])
            funct3 = {'mul':0x0,'div':0x4,'divu':0x5,'rem':0x6,'remu':0x7}[op]
            funct7 = 0x01
            word = encode_R(funct7, funct3, OPC['OP'], rd, rs1, rs2)
        else:
            raise ValueError(f"Unsupported opcode '{op}'")
        return mask(word, 32)
    except Exception as e:
        raise ValueError(f"Error assembling line '{line}': {e}")

# --- RISC-V SIMULATOR CLASS ---
class RISCVSimulator:
    def __init__(self, instructions):
        self.regs = [0] * 32
        self.pc = 0
        self.memory = {} # byte addressable sparse memory
        self.instr_mem = instructions # List of 32-bit integers
        self.max_steps = 1000 # Tránh lặp vô hạn

    def get_reg(self, n):
        if n == 0: return 0
        return self.regs[n]

    def set_reg(self, n, val):
        if n != 0:
            # Mask to 32 bits and handle signed/unsigned view in Python
            self.regs[n] = mask(val, 32)

    def get_signed_reg(self, n):
        val = self.get_reg(n)
        return sign_extend(val, 32)

    def run(self):
        steps = 0
        print("-" * 40)
        print("Bắt đầu mô phỏng (Simulation)...")
        
        while steps < self.max_steps:
            # Fetch
            pc_word_idx = self.pc // 4
            if pc_word_idx >= len(self.instr_mem) or pc_word_idx < 0:
                print(f"PC ngoài vùng lệnh ({self.pc}). Dừng.")
                break
            
            inst = self.instr_mem[pc_word_idx]
            steps += 1
            
            # Decode simple fields
            opcode = inst & 0x7F
            rd = (inst >> 7) & 0x1F
            funct3 = (inst >> 12) & 0x7
            rs1 = (inst >> 15) & 0x1F
            rs2 = (inst >> 20) & 0x1F
            funct7 = (inst >> 25) & 0x7F
            
            # Execute logic (Decoder ngược lại của assembler)
            next_pc = self.pc + 4
            
            try:
                # 1. OP-IMM (ADDI, etc.)
                if opcode == OPC['OP-IMM']:
                    imm_i = sign_extend(inst >> 20, 12)
                    val_rs1 = self.get_signed_reg(rs1)
                    res = 0
                    if funct3 == 0x0: # ADDI
                        res = val_rs1 + imm_i
                    elif funct3 == 0x4: # XORI
                        res = val_rs1 ^ imm_i
                    elif funct3 == 0x6: # ORI
                        res = val_rs1 | imm_i
                    elif funct3 == 0x7: # ANDI
                        res = val_rs1 & imm_i
                    elif funct3 == 0x1: # SLLI
                        shamt = imm_i & 0x1F
                        res = val_rs1 << shamt
                    elif funct3 == 0x5: # SRLI/SRAI
                        shamt = imm_i & 0x1F
                        if (inst >> 30) & 1: # SRAI
                            res = val_rs1 >> shamt 
                        else: # SRLI
                            # Python shifts are arithmetic for signed ints, need logical
                            u_rs1 = self.get_reg(rs1)
                            res = u_rs1 >> shamt
                    self.set_reg(rd, res)

                # 2. OP (ADD, SUB, etc.)
                elif opcode == OPC['OP']:
                    val_rs1 = self.get_signed_reg(rs1)
                    val_rs2 = self.get_signed_reg(rs2)
                    u_rs1 = self.get_reg(rs1)
                    u_rs2 = self.get_reg(rs2)
                    res = 0
                    if funct7 == 0x00:
                        if funct3 == 0x0: res = val_rs1 + val_rs2 # ADD
                        elif funct3 == 0x1: res = val_rs1 << (val_rs2 & 0x1f) # SLL
                        elif funct3 == 0x2: res = 1 if val_rs1 < val_rs2 else 0 # SLT
                        elif funct3 == 0x3: res = 1 if self.get_reg(rs1) < self.get_reg(rs2) else 0 # SLTU
                        elif funct3 == 0x4: res = val_rs1 ^ val_rs2 # XOR
                        elif funct3 == 0x5: res = self.get_reg(rs1) >> (val_rs2 & 0x1f) # SRL
                        elif funct3 == 0x6: res = val_rs1 | val_rs2 # OR
                        elif funct3 == 0x7: res = val_rs1 & val_rs2 # AND
                    elif funct7 == 0x20:
                        if funct3 == 0x0: res = val_rs1 - val_rs2 # SUB
                        elif funct3 == 0x5: res = val_rs1 >> (val_rs2 & 0x1f) # SRA
                    elif funct7 == 0x01: 
                        if funct3 == 0x0: res = val_rs1 * val_rs2 # MUL
                        elif funct3 == 0x4: # DIV
                            if val_rs2 == 0: res = -1
                            elif val_rs1 == -2147483648 and val_rs2 == -1: res = -2147483648
                            else: res = int(float(val_rs1) / val_rs2)
                        elif funct3 == 0x5: # DIVU
                            if u_rs2 == 0: res = 0xFFFFFFFF
                            else: res = u_rs1 // u_rs2
                        elif funct3 == 0x6: # REM
                            if val_rs2 == 0: res = val_rs1
                            else: 
                                div_res = int(float(val_rs1) / val_rs2)
                                res = val_rs1 - (div_res * val_rs2)
                        elif funct3 == 0x7: # REMU
                            if u_rs2 == 0: res = u_rs1
                            else: res = u_rs1 % u_rs2
                    self.set_reg(rd, res)
                
                # 3. LUI
                elif opcode == OPC['LUI']:
                    imm_u = mask(inst, 32) & 0xFFFFF000
                    self.set_reg(rd, imm_u)

                # 4. BRANCH (BEQ, etc.)
                elif opcode == OPC['BRANCH']:
                    # Reconstruct B-immediate
                    imm_12 = (inst >> 31) & 1
                    imm_10_5 = (inst >> 25) & 0x3F
                    imm_4_1 = (inst >> 8) & 0xF
                    imm_11 = (inst >> 7) & 1
                    imm_b = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1)
                    offset = sign_extend(imm_b, 13)
                    
                    val_rs1 = self.get_signed_reg(rs1)
                    val_rs2 = self.get_signed_reg(rs2)
                    take = False
                    if funct3 == 0x0: take = (val_rs1 == val_rs2) # BEQ
                    elif funct3 == 0x1: take = (val_rs1 != val_rs2) # BNE
                    elif funct3 == 0x4: take = (val_rs1 < val_rs2) # BLT
                    elif funct3 == 0x5: take = (val_rs1 >= val_rs2) # BGE
                    elif funct3 == 0x6: take = (self.get_reg(rs1) < self.get_reg(rs2)) # BLTU
                    elif funct3 == 0x7: take = (self.get_reg(rs1) >= self.get_reg(rs2)) # BGEU
                    
                    if take:
                        next_pc = self.pc + offset

                # 5. JAL
                elif opcode == OPC['JAL']:
                    # Reconstruct J-immediate
                    imm_20 = (inst >> 31) & 1
                    imm_10_1 = (inst >> 21) & 0x3FF
                    imm_11 = (inst >> 20) & 1
                    imm_19_12 = (inst >> 12) & 0xFF
                    imm_j = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1)
                    offset = sign_extend(imm_j, 21)
                    
                    self.set_reg(rd, self.pc + 4)
                    next_pc = self.pc + offset

                # 6. LOAD (Simple simulation, assumes memory is empty or just returns 0 if not set)
                elif opcode == OPC['LOAD']:
                    imm_i = sign_extend(inst >> 20, 12)
                    addr = self.get_signed_reg(rs1) + imm_i
                    
                    # Lấy giá trị thô từ bộ nhớ (trong Python sim này, memory trả về int)
                    # Lưu ý: Mô phỏng này giả định load đúng địa chỉ đã store
                    raw_val = self.memory.get(addr, 0)
                    
                    res = 0
                    # Check funct3 để xử lý độ rộng bit
                    if funct3 == 0x0:   # LB (Load Byte Signed)
                        byte_val = raw_val & 0xFF
                        res = sign_extend(byte_val, 8)
                    elif funct3 == 0x1: # LH (Load Half Signed)
                        half_val = raw_val & 0xFFFF
                        res = sign_extend(half_val, 16)
                    elif funct3 == 0x2: # LW (Load Word)
                        res = raw_val
                    elif funct3 == 0x4: # LBU (Load Byte Unsigned) - Case của bạn
                        res = raw_val & 0xFF
                    elif funct3 == 0x5: # LHU (Load Half Unsigned)
                        res = raw_val & 0xFFFF
                    
                    self.set_reg(rd, res)

                # 7. STORE
                elif opcode == OPC['STORE']:
                    # Reconstruct S-immediate
                    imm_11_5 = (inst >> 25) & 0x7F
                    imm_4_0 = (inst >> 7) & 0x1F
                    imm_s = (imm_11_5 << 5) | imm_4_0
                    offset = sign_extend(imm_s, 12)
                    addr = self.get_signed_reg(rs1) + offset
                    val = self.get_reg(rs2) # Store word
                    self.memory[addr] = val # Simple word store

            except Exception as e:
                print(f"Lỗi mô phỏng tại PC={self.pc}: {e}")
                break
            
            self.pc = next_pc

        print(f"Mô phỏng hoàn tất sau {steps} bước.")
        self.dump_regs()

    def dump_regs(self):
        print("\n=== GIÁ TRỊ MÔ PHỎNG THANH GHI (x0 - x31) ===")
        # In thành 4 cột cho dễ nhìn
        for i in range(0, 32, 1):
            line = ""
            for j in range(1):
                reg_idx = i + j
                val = self.regs[reg_idx]
                # Format: x0 : 0 (0x00000000)
                # Chuyển sang signed int để hiển thị số âm cho dễ hiểu
                signed_val = sign_extend(val, 32)
                line += f"x{reg_idx:<2}:  (0x{val:08x}) | {signed_val:>6}"
            print(line.strip(' | '))
        print("="*40)


def assemble_file(infile, outfile='../mem_initial_contents.hex'):
    with open(infile, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    words = []
    print(f"[ASM] Đang lắp ráp {infile}...")
    for ln in lines:
        ln_strip = ln.strip()
        if not ln_strip or ln_strip.startswith('#') or ln_strip.startswith('//'):
            continue
        try:
            w = assemble_line(ln_strip)
            if w is not None:
                words.append(w)
        except Exception as e:
            print(f"Warning: {e}", file=sys.stderr)

    # --- CHÈN HALT VÀO DANH SÁCH ---
    # Vẫn chèn vào words để Simulator hiểu và dừng đúng lúc
    halt_instr = 0x00000073
    words.append(halt_instr)
    print(f"[ASM] Đã chèn lệnh HALT ({halt_instr:08x}) vào cuối chương trình.")

    # --- GHI FILE HEX KÈM COMMENT ---
    with open(outfile, 'w', encoding='utf-8') as fo:
        for i, w in enumerate(words):
            # Kiểm tra xem đây có phải là phần tử cuối cùng (lệnh HALT vừa thêm) hay không
            if i == len(words) - 1 and w == halt_instr:
                # Ghi lệnh kèm comment
                fo.write(f"{w:08x} # Lệnh halt là bắt buộc, nếu ko có thì tb không dừng\n")
            else:
                # Ghi lệnh bình thường
                fo.write(f"{w:08x}\n")
                
    print(f"[ASM] Đã ghi {len(words)} lệnh vào {outfile}")
    
    return words

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="RISC-V assembler + simulator")
    parser.add_argument("--input", "-i", default="testcases/case0.asm", help="File ASM input")
    parser.add_argument("--output", "-o", default="../mem_initial_contents.hex", help="File HEX output")
    parser.add_argument("--no-sim", action="store_true", help="Không chạy mô phỏng")

    args = parser.parse_args()

    infile = args.input
    outfile = args.output

    # 1) Assemble
    words = assemble_file(infile, outfile)

    # 2) Simulate (nếu có lệnh)
    if words and not args.no_sim:
        sim = RISCVSimulator(words)
        sim.run()