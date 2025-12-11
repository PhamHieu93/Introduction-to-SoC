# --- Case 1: Phép cộng cơ bản (ADD, ADDI) ---
addi x1, x0, 10      # x1 = 10
addi x2, x0, 20      # x2 = 20
add  x3, x1, x2      # x3 = 30

# --- Case 2: Phép trừ (SUB) ---
sub  x4, x3, x1      # x4 = 30 - 10 = 20
sub  x5, x1, x2      # x5 = 10 - 20 = -10 (Kiểm tra số âm)

# --- Case 3: Số âm với ADDI (Negative Immediate) ---
addi x6, x0, -5      # x6 = -5
add  x7, x6, x1      # x7 = -5 + 10 = 5

# --- Case 4: LUI (Load Upper Immediate) ---
# Nạp 0x12345 vào 20 bit cao của x8 -> x8 = 0x12345000
lui  x8, 0x12345     

# --- Case 5: AUIPC (Add Upper Immediate to PC) ---
# PC hiện tại đang chạy dòng này. x9 = PC + (0x1 << 12)
# auipc x9, 1