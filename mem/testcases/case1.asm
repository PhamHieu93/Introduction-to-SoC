# --- Case 11: Lưu và Đọc Word (SW, LW) ---
addi x1, x0, 100     # Địa chỉ 100
addi x2, x0, 555     # Giá trị
sw   x2, 0(x1)       # Ghi 555 vào Mem[100]
lw   x3, 0(x1)       # Đọc từ Mem[100] vào x3 -> x3 = 555

# --- Case 12: Byte có dấu (SB, LB) ---
addi x4, x0, 200     # Địa chỉ 200
addi x5, x0, -1      # x5 = 0xFFFFFFFF
sb   x5, 0(x4)       # Ghi 0xFF vào Mem[200]
lb   x6, 0(x4)       # Đọc lên và mở rộng dấu -> x6 vẫn là -1 (0xFFFFFFFF)

# --- Case 13: Byte không dấu (LBU) ---
lbu  x7, 0(x4)       # Đọc lên nhưng không mở rộng dấu -> x7 = 255 (0x000000FF)

# --- Case 14: Half-word (SH, LH) ---
addi x8, x0, 300
addi x9, x0, 0x1234
sh   x9, 0(x8)       # Ghi 2 byte 0x34, 0x12
lh   x10, 0(x8)      # Đọc lên -> x10 = 0x1234

# --- Case 15: Offset trong Load/Store ---
sw   x2, 4(x1)       # Ghi vào địa chỉ 100 + 4 = 104
lw   x11, 4(x1)      # Đọc từ 104 -> x11 = 555