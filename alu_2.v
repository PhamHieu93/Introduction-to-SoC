
`timescale 1ns / 1ps
`define REG_SIZE 31

module ALU (
  input               clk, rst,
  input [`REG_SIZE:0] a_alu,
  input [`REG_SIZE:0] b_alu,
  input [3:0]         alu_op,
  input [2:0]         funct3,
  output reg [`REG_SIZE:0] result
);
  // --- 1. Basic ALU Logic ---
  wire [`REG_SIZE:0] sum;
  wire is_sub = (alu_op == 4'b0001) || (alu_op == 4'b0011) || (alu_op == 4'b0100); 
  wire cin = (is_sub) ? 1'b1 : 1'b0;
  wire [`REG_SIZE:0] b_alu_inverted = (is_sub) ? ~b_alu : b_alu;

  cla cla_inst (
    .a(a_alu), 
    .b(b_alu_inverted), 
    .cin(cin), 
    .sum(sum)
  );

  wire check_equal = (a_alu == b_alu);
  wire check_less_signed = ($signed(a_alu) < $signed(b_alu));
  wire check_less_unsigned = (a_alu < b_alu);

  // --- 2. MULTIPLICATION Logic ---
  reg [63:0] multiply;
  always @(*) begin
      case (funct3)
          3'b000: multiply = a_alu * b_alu;                   // MUL
          3'b001: multiply = ($signed(a_alu) * $signed(b_alu)); // MULH
          3'b010: multiply = ($signed(a_alu) * $signed({1'b0, b_alu})); // MULHSU
          3'b011: multiply = (a_alu * b_alu);                 // MULHU
          default: multiply = 64'd0;
      endcase
  end

  // --- 3. Output MUX ---
  always @(*) begin
    case (alu_op)
      4'b0000: result = sum;                         // ADD
      4'b0001: result = sum;                         // SUB
      4'b0010: result = a_alu << b_alu[4:0];         // SLL
      4'b0011: result = {31'd0, check_less_signed};  // SLT
      4'b0100: result = {31'd0, check_less_unsigned};// SLTU
      4'b0101: result = a_alu ^ b_alu;               // XOR
      4'b0110: result = a_alu >> b_alu[4:0];         // SRL
      4'b0111: result = $signed(a_alu) >>> b_alu[4:0]; // SRA
      4'b1000: result = a_alu | b_alu;               // OR
      4'b1001: result = a_alu & b_alu;               // AND
      
      4'b1010: begin // MUL
          case (funct3)
             3'b000: result = multiply[31:0];
             3'b001: result = multiply[63:32];
             3'b010: result = multiply[63:32];
             3'b011: result = multiply[63:32];
             default: result = 0;
          endcase
      end
      
      4'b1100: result = b_alu; // LUI/COPY_B
      default: result = 32'd0;
    endcase
  end
endmodule