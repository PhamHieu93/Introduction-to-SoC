# --- TEST BRANCH & JUMP ---

# 1. Test BEQ (Nhảy nếu bằng)
addi x1, x0, 5
addi x2, x0, 5
beq  x1, x2, 8       # 5==5 -> Nhảy qua lệnh addi kế tiếp (PC+8)
addi x3, x0, 999     # Lệnh này PHẢI bị bỏ qua (x3 vẫn là 0)
addi x4, x0, 10      # Điểm đến -> x4 = 10

# 2. Test BNE (Nhảy nếu khác)
addi x5, x0, 100
addi x6, x0, 200
bne  x5, x6, 8       # 100!=200 -> Nhảy (PC+8)
addi x7, x0, 999     # Phải bị bỏ qua
addi x8, x0, 20      # Điểm đến -> x8 = 20

# 3. Test JAL (Nhảy không điều kiện)
jal  x9, 12          # Nhảy qua 2 lệnh (PC+12). Lưu PC+4 vào x9
addi x10, x0, 999    # Bị bỏ qua 1
addi x11, x0, 999    # Bị bỏ qua 2
addi x12, x0, 30     # Điểm đến -> x12 = 30. Kiểm tra x9 xem có đúng địa chỉ ko.

# 4. Test JALR (Nhảy gián tiếp - Khó nhất)
# Mục tiêu: Nhảy đến nhãn 'TARGET' bên dưới
auipc x13, 0         # x13 = PC hiện tại
addi  x13, x13, 20   # Cộng thêm 12 byte (3 lệnh) để trỏ tới lệnh 'addi x15...'
jalr  x14, x13, 0    # Nhảy tới địa chỉ trong x13. Lưu PC+4 vào x14
addi  x30, x0, 999   # Lệnh này PHẢI bị bỏ qua (x30 vẫn 0)
addi  x31, x0, 999   # Lệnh này PHẢI bị bỏ qua (x31 vẫn 0)

# TARGET:
addi  x15, x0, 40    # Điểm đến -> x15 = 40

# 5. Test x0 (Hardwired Zero)
addi x0, x0, 123
addi x16, x0, 0      # x16 = x0. Nếu x0 bị ghi đè thì x16 sẽ là 123. Nếu đúng, x16 = 0.

# -----------------------------------------------------------
# Python script sẽ tự động chèn 0x00000073 (HALT) vào đây
# CPU chạy đến đây sẽ gặp ECALL -> Halt = 1 -> Testbench dừng và in kết quả.