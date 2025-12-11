# --- ULTIMATE RISC-V PIPELINE TEST ---
# Bài toán: 
# 1. Tính Factorial(6) = 720
# 2. Thực hiện các phép chia/dư trên kết quả
# 3. Chạy qua chuỗi Hazard Load-Use & Forwarding

# ============================================================
# PHẦN 1: TÍNH GIAI THỪA (FACTORIAL LOOP)
# ============================================================
# x10: Accumulator (Kết quả)
# x11: Loop Counter (i)
# x12: Limit (6)

addi x10, x0, 1      # Result = 1
addi x11, x0, 1      # i = 1
addi x12, x0, 6      # N = 6

LOOP_START:
    mul  x10, x10, x11  # Result = Result * i
    addi x11, x11, 1    # i++
    
    # Logic so sánh: nếu i <= N (i < N+1) thì lặp
    # Dùng SLT để kiểm tra: (N+1) < i ? Nếu sai thì i <= N
    addi x13, x12, 1    # x13 = 7
    slt  x14, x11, x13  # Nếu i < 7 -> x14 = 1
    bne  x14, x0, -16   # Nếu x14 != 0 (True) -> Quay lại mul (lùi 4 lệnh)
                        # Offset ước tính: -16 bytes (mul, addi, addi, slt)

# KẾT QUẢ KỲ VỌNG SAU PHẦN 1:
# x10 = 720 (0x2D0)

# ============================================================
# PHẦN 2: MATH & M-EXTENSION STRESS
# ============================================================
# Sử dụng x10 (720) để test chia/dư

addi x15, x0, 10
div  x16, x10, x15    # x16 = 720 / 10 = 72
rem  x17, x10, x15    # x17 = 720 % 10 = 0

addi x18, x0, 7
div  x19, x10, x18    # x19 = 720 / 7  = 102
rem  x20, x10, x18    # x20 = 720 % 7  = 6

# Test Unsigned với số âm giả
addi x21, x0, -10     # x21 = 0xFFFFFFF6
divu x22, x21, x18    # x22 = (Large Unsigned) / 7 = 613566756

# KẾT QUẢ KỲ VỌNG SAU PHẦN 2:
# x16 = 72, x17 = 0, x19 = 102, x20 = 6

# ============================================================
# PHẦN 3: THE HAZARD TORTURE CHAMBER (Quan trọng nhất)
# ============================================================
# Mục đích: Kiểm tra xem Stall và Forwarding có chạy đúng không
# khi các lệnh phụ thuộc nhau dồn dập.

# Chuẩn bị bộ nhớ
addi x1, x0, 0        # Base Address
addi x2, x0, 100      # Value 100
sw   x2, 0(x1)        # Mem[0] = 100

# BẮT ĐẦU CHUỖI HAZARD:
lw   x3, 0(x1)        # x3 = 100 (Load từ Mem)
                      # --- STALL PHẢI XẢY RA TẠI ĐÂY (Load-Use) ---
add  x4, x3, x3       # x4 = 100 + 100 = 200 (Phải đợi lw xong hoặc forward từ WB)
add  x5, x4, x4       # x5 = 200 + 200 = 400 (Forward EX->EX từ x4)
sub  x6, x5, x3       # x6 = 400 - 100 = 300 (Forward EX->EX từ x5, MEM->EX từ x3)
xor  x7, x6, x4       # x7 = 300 ^ 200
                      # 300 = 0x12C (100101100)
                      # 200 = 0x0C8 (011001000)
                      # XOR = 0x1E4 (111100100) = 484

# KẾT QUẢ KỲ VỌNG SAU PHẦN 3:
# x3=100, x4=200, x5=400, x6=300, x7=484

# ============================================================
# PHẦN 4: FINAL STORE (Kiểm tra ghi kết quả cuối cùng)
# ============================================================
sw   x10, 4(x1)       # Lưu 720 vào Mem[4]
sw   x7,  8(x1)       # Lưu 484 vào Mem[8]

# HALT TỰ ĐỘNG (ECALL hoặc Loop vô tận)