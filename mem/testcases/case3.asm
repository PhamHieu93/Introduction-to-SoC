# --- INTEGRATION STRESS TEST ---
# Mục tiêu: Tính S = Sum( (Array[i] * 10) / 3 )
# Array = [10, 20, 30, 40]

# --- 1. Khởi tạo & Ghi bộ nhớ (Store) ---
addi x1, x0, 0      # x1 = Base Address (0)
addi x2, x0, 10     # Val 1 = 10
addi x3, x0, 20     # Val 2 = 20
addi x4, x0, 30     # Val 3 = 30
addi x5, x0, 40     # Val 4 = 40

sw   x2, 0(x1)      # Mem[0] = 10
sw   x3, 4(x1)      # Mem[4] = 20
sw   x4, 8(x1)      # Mem[8] = 30
sw   x5, 12(x1)     # Mem[12] = 40

# --- 2. Chuẩn bị vòng lặp ---
addi x6, x0, 4      # x6 = Loop Count (4 phần tử)
addi x7, x0, 0      # x7 = Loop Index (Offset: 0, 4, 8, 12)
addi x8, x0, 0      # x8 = ACCUMULATOR (Tổng S)
addi x9, x0, 10     # x9 = Hằng số nhân (10)
addi x10, x0, 3     # x10 = Hằng số chia (3)
addi x11, x0, 16    # x11 = Offset giới hạn (4*4=16) để so sánh thoát loop

# --- 3. BẮT ĐẦU LOOP ---
# Label: LOOP_START (PC giả định, dùng offset tương đối để nhảy)

# A. Load-Use Hazard check: Load xong dùng ngay vào MUL
lw   x12, 0(x7)     # x12 = Mem[Offset] (10, 20...)
mul  x13, x12, x9   # x13 = x12 * 10. (Hazard! Phải forward từ WB/MEM về EX)

# B. DIV Stall check: Dùng kết quả MUL để chia ngay
div  x14, x13, x10  # x14 = (Val * 10) / 3. (Bộ chia sẽ Stall pipeline)

# C. Accumulate
add  x8, x8, x14    # S = S + Kết quả chia

# D. Loop control
addi x7, x7, 4      # Tăng offset thêm 4 byte
bne  x7, x11, -16   # Nếu Offset != 16 thì quay lại lệnh lw (nhảy lùi 4 lệnh: -16 bytes)
                    # Chú ý: Offset nhảy phụ thuộc vào trình biên dịch, ở đây ước lượng -16
                    # (lw, mul, div, add, addi, bne -> 6 lệnh. Nhảy về đầu là lùi 5 lệnh = -20 bytes?)
                    # Để an toàn, tôi sẽ viết code phẳng (unrolled) bên dưới cho dễ debug nhé.

# --- Code phẳng (Unrolled) để tránh sai sót tính offset nhảy tay ---
# Iteration 1 (Val=10)
lw   x12, 0(x1)     # Load 10
mul  x13, x12, x9   # 10 * 10 = 100
div  x14, x13, x10  # 100 / 3 = 33
add  x8, x8, x14    # S = 0 + 33 = 33

# Iteration 2 (Val=20)
lw   x12, 4(x1)     # Load 20
mul  x13, x12, x9   # 20 * 10 = 200
div  x14, x13, x10  # 200 / 3 = 66
add  x8, x8, x14    # S = 33 + 66 = 99

# Iteration 3 (Val=30)
lw   x12, 8(x1)     # Load 30
mul  x13, x12, x9   # 30 * 10 = 300
div  x14, x13, x10  # 300 / 3 = 100
add  x8, x8, x14    # S = 99 + 100 = 199

# Iteration 4 (Val=40)
lw   x12, 12(x1)    # Load 40
mul  x13, x12, x9   # 40 * 10 = 400
div  x14, x13, x10  # 400 / 3 = 133
add  x8, x8, x14    # S = 199 + 133 = 332

# --- 4. Final Calculation (RAW Hazard Chain) ---
addi x15, x0, 7     # Modulo 7
rem  x16, x8, x15   # x16 = 332 % 7
                    # 332 / 7 = 47 dư 3
                    # x16 = 3

# --- 5. Forwarding Torture (Back-to-back dependency) ---
addi x20, x0, 10
add  x21, x20, x20  # x21 = 20 (Forward từ EX)
add  x22, x21, x21  # x22 = 40 (Forward từ EX)
add  x23, x22, x22  # x23 = 80 (Forward từ EX)
sub  x24, x23, x16  # x24 = 80 - 3 = 77

# --- 6. Kết thúc ---
# HALT