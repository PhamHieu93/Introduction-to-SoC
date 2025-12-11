# --- TEST M-EXTENSION (MUL/DIV/REM) ---
# Quy ước thanh ghi kết quả:
# x3-x9  : Phép chia cơ bản
# x10-x15: Chia cho 0 (Corner case)
# x16-x19: Tràn số (Overflow)
# x20-x25: Phép chia lấy dư (REM)

# 1. Chuẩn bị dữ liệu
addi x1, x0, 20      # x1 = 20
addi x2, x0, 6       # x2 = 6
addi x4, x0, -20     # x4 = -20 (0xFFFFFFEC)
addi x5, x0, -6      # x5 = -6  (0xFFFFFFFA)

# 2. Phép chia có dấu (DIV)
div  x3, x1, x2      # x3 = 20 / 6 = 3
div  x6, x4, x2      # x6 = -20 / 6 = -3
div  x7, x4, x5      # x7 = -20 / -6 = 3

# 3. Phép chia không dấu (DIVU)
# x4 (-20) được hiểu là số dương rất lớn (4,294,967,276)
divu x8, x1, x2      # x8 = 20 / 6 = 3 (Giống DIV vì số dương)
divu x9, x4, x2      # x9 = 4294967276 / 6 = 715827879 (0x2AAAAAA7)

# 4. Trường hợp đặc biệt: CHIA CHO 0 (Division by Zero)
# Theo chuẩn RISC-V:
# DIV  cho 0 -> Kết quả = -1 (0xFFFFFFFF)
# DIVU cho 0 -> Kết quả = MAX_UINT (0xFFFFFFFF)
# REM  cho 0 -> Kết quả = Số bị chia (Dividend)
# REMU cho 0 -> Kết quả = Số bị chia (Dividend)

div  x10, x1, x0     # x10 = 20 / 0 = -1
divu x11, x1, x0     # x11 = 20 / 0 = 0xFFFFFFFF
rem  x12, x1, x0     # x12 = 20 % 0 = 20 (x1)
remu x13, x1, x0     # x13 = 20 % 0 = 20 (x1)

# 5. Trường hợp đặc biệt: TRÀN SỐ (Overflow)
# Chỉ xảy ra khi lấy Min_Int (-2^31) chia cho -1
lui  x16, 0x80000    # x16 = -2147483648 (0x80000000)
addi x17, x0, -1     # x17 = -1
div  x18, x16, x17   # x18 = -2^31 / -1 = -2^31 (Vẫn là 0x80000000)
rem  x19, x16, x17   # x19 = 0 (Chia hết)

# 6. Phép chia lấy dư (REM) - Lưu ý dấu
# Dấu của REM phụ thuộc vào Số bị chia (Dividend)
rem  x20, x1, x2     # x20 = 20 % 6 = 2
rem  x21, x4, x2     # x21 = -20 % 6 = -2 (Dấu theo -20)
rem  x22, x1, x5     # x22 = 20 % -6 = 2  (Dấu theo 20)
rem  x23, x4, x5     # x23 = -20 % -6 = -2 (Dấu theo -20)

# 7. Phép chia lấy dư không dấu (REMU)
remu x24, x1, x2     # x24 = 20 % 6 = 2
# -20 (0xFFFFFFEC) % 6 = 2
remu x25, x4, x2     # x25 = 4294967276 % 6 = 2 

# --- Kết thúc ---