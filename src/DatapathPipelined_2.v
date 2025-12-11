`timescale 1ns / 1ns

// registers are 32 bits in RV32
`define REG_SIZE 31

// inst. are 32 bits in RV32IM
`define INST_SIZE 31

// RV opcodes are 7 bits
`define OPCODE_SIZE 6

`define DIVIDER_STAGES 8

// Don't forget your old codes
//`include "cla.v"
//`include "DividerUnsignedPipelined.v"

`timescale 1ns / 1ns

`define REG_SIZE 31
`define INST_SIZE 31
`define OPCODE_SIZE 6
`define DIVIDER_STAGES 8

module RegFile (
  input      [        4:0] rd,
  input      [`REG_SIZE:0] rd_data,
  input      [        4:0] rs1,
  output reg [`REG_SIZE:0] rs1_data,
  input      [        4:0] rs2,
  output reg [`REG_SIZE:0] rs2_data,
  input                    clk,
  input                    we,
  input                    rst
);
  localparam NumRegs = 32;
  reg [`REG_SIZE:0] regs[0:NumRegs-1];
  integer i;

  always @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < NumRegs; i = i + 1) regs[i] <= 0;
    end else if (we && rd != 0) begin
      regs[rd] <= rd_data;
    end
  end

  always @(*) begin
    if (rd == rs1 && we && rd != 0) rs1_data = rd_data;
    else rs1_data = regs[rs1];

    if (rd == rs2 && we && rd != 0) rs2_data = rd_data;
    else rs2_data = regs[rs2];
  end
endmodule

module DatapathPipelined (
  input                     clk,
  input                     rst,
  output     [ `REG_SIZE:0] pc_to_imem,
  input      [`INST_SIZE:0] inst_from_imem,
  output reg [ `REG_SIZE:0] addr_to_dmem,
  input      [ `REG_SIZE:0] load_data_from_dmem,
  output reg [ `REG_SIZE:0] store_data_to_dmem,
  output reg [         3:0] store_we_to_dmem,
  output reg                halt,
  output reg [ `REG_SIZE:0] trace_writeback_pc,
  output reg [`INST_SIZE:0] trace_writeback_inst
);

  // Opcodes
  localparam [`OPCODE_SIZE:0] OpcodeLoad    = 7'b00_000_11;
  localparam [`OPCODE_SIZE:0] OpcodeStore   = 7'b01_000_11;
  localparam [`OPCODE_SIZE:0] OpcodeBranch  = 7'b11_000_11;
  localparam [`OPCODE_SIZE:0] OpcodeJalr    = 7'b11_001_11;
  localparam [`OPCODE_SIZE:0] OpcodeJal     = 7'b11_011_11;
  localparam [`OPCODE_SIZE:0] OpcodeRegImm  = 7'b00_100_11;
  localparam [`OPCODE_SIZE:0] OpcodeRegReg  = 7'b01_100_11;
  localparam [`OPCODE_SIZE:0] OpcodeEnviron = 7'b11_100_11;
  localparam [`OPCODE_SIZE:0] OpcodeAuipc   = 7'b00_101_11;
  localparam [`OPCODE_SIZE:0] OpcodeLui     = 7'b01_101_11;

  reg [`REG_SIZE:0] cycles_current;
  always @(posedge clk) begin
    if (rst) cycles_current <= 0;
    else cycles_current <= cycles_current + 1;
  end

  // --- Pipeline Registers & Signals ---
  wire stall_load_use;
  wire stall_div;
  wire stall_all;
  wire flush_branch;

  reg [`REG_SIZE:0] f_pc_current;
  wire [`REG_SIZE:0] f_inst;

  reg [`REG_SIZE:0] d_pc_current;
  reg [`INST_SIZE:0] d_inst;

  reg [`REG_SIZE:0] e_pc_current;
  reg [`INST_SIZE:0] e_inst; // KHAI BÁO MỚI
  reg [`REG_SIZE:0] e_rs1_data, e_rs2_data, e_imm;
  reg [4:0]         e_rs1, e_rs2, e_rd;
  reg [2:0]         e_funct3;
  reg e_alu_src1, e_alu_src2;
  reg [3:0] e_alu_op;

  reg e_mem_read, e_mem_write, e_reg_write, e_mem_to_reg, e_halt;
  reg e_is_branch, e_is_jump;

  reg [`REG_SIZE:0] m_pc_current;
  reg [`INST_SIZE:0] m_inst; // KHAI BÁO MỚI
  reg [`REG_SIZE:0] m_alu_result, m_rs2_data;
  reg [4:0] m_rd;
  reg [2:0] m_funct3;
  reg m_mem_read, m_mem_write, m_reg_write, m_mem_to_reg, m_halt;

  reg [`REG_SIZE:0] w_pc_current;
  reg [`INST_SIZE:0] w_inst; // KHAI BÁO MỚI
  reg [`REG_SIZE:0] w_alu_result, w_mem_data;
  reg [4:0] w_rd;
  reg w_reg_write, w_mem_to_reg, w_halt;

  // --- DIVIDER TRACKING ---
  // Shift register theo dõi: [Rd, Valid, Opcode(Div/Rem), Signed, NegA, NegB]
  reg [4:0] div_rd_pipe    [0:7];
  reg       div_valid_pipe [0:7];
  reg [2:0] div_info_pipe  [0:7]; // Bit 2: is_rem, Bit 1: a_neg, Bit 0: b_neg
  integer k;
  
  // Logic Stall cho Divider
  wire div_busy = div_valid_pipe[0] | div_valid_pipe[1] | div_valid_pipe[2] | div_valid_pipe[3] |
                  div_valid_pipe[4] | div_valid_pipe[5] | div_valid_pipe[6] | div_valid_pipe[7];

  wire [6:0] inst_opcode = d_inst[6:0];
  wire [6:0] inst_funct7 = d_inst[31:25];
  wire [2:0] inst_funct3 = d_inst[14:12];
  wire [4:0] inst_rs1    = d_inst[19:15];
  wire [4:0] inst_rs2    = d_inst[24:20];
  wire [4:0] inst_rd     = d_inst[11:7];

  wire is_id_div = (inst_opcode == OpcodeRegReg) && (inst_funct7 == 7'b0000001) && (inst_funct3[2] == 1'b0);

  reg div_raw_hazard;
  always @(*) begin
      div_raw_hazard = 0;
      for(k=0; k<8; k=k+1) begin
          if (div_valid_pipe[k] && div_rd_pipe[k] != 0 && 
             (div_rd_pipe[k] == inst_rs1 || div_rd_pipe[k] == inst_rs2))
             div_raw_hazard = 1;
      end
  end

  assign stall_div = div_raw_hazard;
  assign stall_all = stall_load_use || stall_div || div_valid_pipe[6];

  // --- FETCH ---
  wire [`REG_SIZE:0] pc_target;
  wire pc_cond;
  
  always @(posedge clk) begin
    if (rst) f_pc_current <= 32'd0;
    else if (!stall_all) begin
      if (pc_cond) f_pc_current <= pc_target;
      else f_pc_current <= f_pc_current + 4;
    end
  end
  assign pc_to_imem = f_pc_current;
  assign f_inst = inst_from_imem;

  // --- MISSING IF/ID REGISTER BLOCK ---
  always @(posedge clk) begin
    if (rst || flush_branch) begin 
      d_pc_current <= 32'd0;
      d_inst       <= 32'h00000013; // NOP
    end
    else if (!stall_all) begin 
      d_pc_current <= f_pc_current;
      d_inst       <= f_inst;
    end
    // Nếu Stall: Giữ nguyên giá trị cũ (không làm gì)
  end
  // ------------------------------------
  // --- DECODE ---
  wire [11:0] imm_i = d_inst[31:20];
  wire [11:0] imm_s = {inst_funct7, inst_rd};
  wire [12:0] imm_b = {inst_funct7[6], inst_rd[0], inst_funct7[5:0], inst_rd[4:1], 1'b0};
  wire [20:0] imm_j = {d_inst[31], d_inst[19:12], d_inst[20], d_inst[30:21], 1'b0};
  wire [`REG_SIZE:0] imm_i_sext = {{20{imm_i[11]}}, imm_i};
  wire [`REG_SIZE:0] imm_s_sext = {{20{imm_s[11]}}, imm_s};
  wire [`REG_SIZE:0] imm_b_sext = {{19{imm_b[12]}}, imm_b};
  wire [`REG_SIZE:0] imm_j_sext = {{11{imm_j[20]}}, imm_j};
  wire [`REG_SIZE:0] imm_u_sext = {d_inst[31:12], 12'b0};

  wire [`REG_SIZE:0] rs1_data_raw, rs2_data_raw;
  wire [`REG_SIZE:0] wb_rd_data; 
  wire wb_we;
  wire [4:0] wb_rd;

  RegFile rf (
    .clk(clk), 
    .rst(rst), 
    .we(wb_we), 
    .rd(wb_rd), 
    .rd_data(wb_rd_data), 
    .rs1(inst_rs1), 
    .rs2(inst_rs2), 
    .rs1_data(rs1_data_raw), 
    .rs2_data(rs2_data_raw));

  // Control Unit (Rút gọn cho ngắn, bạn giữ logic cũ của bạn ở đây)
  reg c_alu_src1; 
  reg c_alu_src2;
  reg [3:0] c_alu_op;
  reg c_mem_read, c_mem_write, c_reg_write, c_mem_to_reg, c_halt; 
  reg c_is_branch, c_is_jump;
  reg [`REG_SIZE:0] c_imm;
  
  //  Logic simplest Load-Use Hazard Detection:
  assign stall_load_use = (e_mem_read) && ((e_rd == inst_rs1) || (e_rd == inst_rs2)) && (e_rd != 0);

  always @(*) begin
    // Paste logic Control Unit cũ của bạn vào đây
    // Default assignments
    c_alu_src1 = 0; 
    c_alu_src2 = 0; 
    c_alu_op = 4'b0000; 
    c_mem_read = 0; 
    c_mem_write = 0;
    c_reg_write = 0; 
    c_mem_to_reg = 0; 
    c_halt = 0; 
    c_is_branch = 0; 
    c_is_jump = 0; 
    c_imm = 0;
    
    case (inst_opcode)
      OpcodeRegReg: begin 
          c_reg_write = 1; 
          if(inst_funct7== 7'b0000001) c_alu_op=(inst_funct3[2])?4'b1011:4'b1010; // DIV / MUL
          else begin // Standard ALU
             case(inst_funct3)
                3'b000: c_alu_op = (inst_funct7[5]) ? 4'b0001 : 4'b0000; // SUB/ADD
                3'b001: c_alu_op = 4'b0010; //SLL
                3'b010: c_alu_op = 4'b0011; //SLT
                3'b011: c_alu_op = 4'b0100; //SLTU
                3'b100: c_alu_op = 4'b0101; //XOR
                3'b101: c_alu_op = (inst_funct7[5]) ? 4'b0111 : 4'b0110; // SRA/SRL
                3'b110: c_alu_op = 4'b1000; //OR
                3'b111: c_alu_op = 4'b1001; //AND
             endcase
          end
      end
      OpcodeRegImm: 
      begin 
      c_reg_write = 1; c_alu_src2 = 1; c_imm = imm_i_sext; 
          case(inst_funct3)
            3'b000: c_alu_op=4'b0000; //ADDI
            3'b010: c_alu_op=4'b0011; //SLTI
            3'b011: c_alu_op=4'b0100; //SLTIU
            3'b100: c_alu_op=4'b0101; //XORI
            3'b110: c_alu_op=4'b1000; //ORI
            3'b111: c_alu_op=4'b1001; //ANDI
            3'b001: begin 
                c_alu_op=4'b0010; 
                c_imm={27'd0, d_inst[24:20]}; 
              end //SLLI
            3'b101: begin 
                c_alu_op=(inst_funct7[5])?4'b0111:4'b0110; 
                c_imm={27'd0, d_inst[24:20]}; 
              end // SRAI/SRLI
          endcase
      end
      OpcodeLoad: begin 
          c_reg_write=1; 
          c_mem_read=1; 
          c_mem_to_reg=1; 
          c_alu_src2=1; 
          c_imm=imm_i_sext; 
        end
      OpcodeStore: begin 
          c_mem_write=1; 
          c_alu_src2=1; 
          c_imm=imm_s_sext; 
        end
      OpcodeBranch: begin 
          c_is_branch=1; 
          c_alu_op= 4'b0001; 
          c_imm=imm_b_sext; // ALU SUB for compare
          // Funct3 will be processed EX to define the jump
        end
      OpcodeJal: 
        begin 
          c_is_jump=1; 
          c_reg_write=1; 
          c_imm=imm_j_sext; 
          c_alu_src1=1; //PC
          c_alu_src2=1; //Imm

        // JAL need: PC_next = PC + Imm. Rd = PC + 4.
        // Here we use ALU to calculate PC+Imm (for jump).
        // Write PC+4 to Rd will be process speacialy or use cla to sum.
        // Simplest: ALU calculate PC+Imm. Rd take PC+4.
        end
      OpcodeJalr: begin 
          c_is_jump=1; 
          c_reg_write=1; 
          c_imm=imm_i_sext; 
          c_alu_src2=1; 
          c_alu_op = 4'b0000; // ADD (rs1 + imm)
        end
      OpcodeLui: 
        begin 
          c_reg_write=1; 
          c_imm=imm_u_sext; 
          // LUI: Rd = Imm. Can use  ALU: A=0, B=Imm, Op=ADD.
        // Here we defined LUI is handled by direct assignment .
          c_alu_src2=1; 
          c_alu_op=4'b1100; 
        end
      OpcodeAuipc: 
        begin 
          c_reg_write=1; 
          c_alu_src1=1; 
          c_alu_src2=1; 
          c_alu_op = 4'b0000; 
          c_imm=imm_u_sext; 
        end
      OpcodeEnviron: if(d_inst[31:7] == 0) c_halt = 1;
    endcase
  end

  //Mux Inputs for ALU
  // Forwarding Wires declare
  reg [`REG_SIZE:0] alu_in_a_val, alu_in_b_val_fwd;

  // Update ID/EX
  always @(posedge clk) begin
    if (rst || flush_branch || stall_load_use) begin
       e_pc_current <= 0; e_inst <= 32'h13; // NOP
       e_imm <= 0; 
       e_rd <= 0; 
       e_rs1 <= 0; 
       e_rs2 <= 0; 
       e_funct3 <= 0;
       e_rs1_data <= 0; 
       e_rs2_data <= 0;
       e_alu_src1 <= 0; 
       e_alu_src2 <= 0; 
       e_alu_op <= 0;

       e_mem_read <= 0; 
       e_mem_write <= 0; 
       e_reg_write <= 0; 
       e_mem_to_reg <= 0;
       e_halt <= 0;

       e_is_branch <= 0; 
       e_is_jump <= 0;
    end else if (!stall_div) begin
       e_pc_current <= d_pc_current; 
       e_inst <= d_inst;
       e_rs1_data <= rs1_data_raw;
       e_rs2_data <= rs2_data_raw; 
       e_imm <= c_imm;
       e_rs1 <= inst_rs1; 
       e_rs2 <= inst_rs2; 
       e_rd <= inst_rd; 
       e_funct3 <= inst_funct3;

       e_alu_src1 <= c_alu_src1; 
       e_alu_src2 <= c_alu_src2; 
       e_alu_op <= c_alu_op;
       e_mem_read <= c_mem_read; 
       e_mem_write <= c_mem_write; 
       e_reg_write <= c_reg_write; 
       e_mem_to_reg <= c_mem_to_reg; 
       e_halt <= c_halt; 
       e_is_branch <= c_is_branch; 
       e_is_jump <= c_is_jump;
    end else begin
       // Capture forwarding logic when stalling for Divider
       // when Stall, all commend before (WB/MEM) will run away.
       // we need to capture the current value Forwarding into the reg for not being lost.
       e_rs1_data <= alu_in_a_val;
       e_rs2_data <= alu_in_b_val_fwd;
    end
  end

  // =========================================
  // EXECUTE STAGE (EX)
  // =========================================
  // Forwarding Unit
  reg [1:0] fwd_a, fwd_b;
  always @(*) begin
    if (m_reg_write && m_rd!=0 && m_rd==e_rs1) fwd_a=2'b10; // from MEM
    else if (w_reg_write && w_rd!=0 && w_rd==e_rs1) fwd_a=2'b01; // from WB
    else fwd_a=0;
    
    if (m_reg_write && m_rd!=0 && m_rd==e_rs2) fwd_b=2'b10;
    else if (w_reg_write && w_rd!=0 && w_rd==e_rs2) fwd_b=2'b01;
    else fwd_b=0;
  end

  always @(*) begin
    case(fwd_a) 
      2'b00: alu_in_a_val=e_rs1_data; 
      2'b10: alu_in_a_val=m_alu_result; 
      2'b01: alu_in_a_val=wb_rd_data; 
      default: alu_in_a_val=e_rs1_data; 
    endcase
    case(fwd_b) 
      2'b00: alu_in_b_val_fwd=e_rs2_data; 
      2'b10: alu_in_b_val_fwd=m_alu_result; 
      2'b01: alu_in_b_val_fwd=wb_rd_data; 
      default: alu_in_b_val_fwd=e_rs2_data; 
    endcase
  end
  // Select final source (PC or rs1? Imm or rs2?)
  wire [`REG_SIZE:0] alu_a = (e_alu_src1) ? e_pc_current : alu_in_a_val;
  wire [`REG_SIZE:0] alu_b = (e_alu_src2) ? e_imm : alu_in_b_val_fwd;

 // --- Instantiate ALU & Divider ---
  // ALU Instantiation (Combinational Only)
  wire [`REG_SIZE:0] alu_result_comb;

  ALU alu_inst (
    .clk(clk), 
    .rst(rst), 
    .a_alu(alu_a), 
    .b_alu(alu_b), 
    .alu_op(e_alu_op), 
    .funct3(e_funct3), 
    .result(alu_result_comb));
  wire [`REG_SIZE:0] final_ex_result = alu_result_comb;

  // --- DIVIDER LOGIC (MOVED TO DATAPATH) ---
  wire is_div_op_ex = (e_alu_op == 4'b1011);
  wire is_signed_ex = is_div_op_ex && (~e_funct3[0]); // Check bit 0 funct3
  wire is_rem_ex    = is_div_op_ex && (e_funct3[1]);  // Check bit 1 funct3 (REM/REMU)
  
  // Calculate ABS values for inputs
  wire a_neg_ex = is_signed_ex && alu_in_a_val[31];
  wire b_neg_ex = is_signed_ex && alu_in_b_val_fwd[31];
  wire [31:0] div_in_a = a_neg_ex ? (~alu_in_a_val + 1) : alu_in_a_val;
  wire [31:0] div_in_b = b_neg_ex ? (~alu_in_b_val_fwd + 1) : alu_in_b_val_fwd;
  wire [31:0] div_quot_out, div_rem_out;

  DividerUnsignedPipelined divider(
    .clk(clk), 
    .rst(rst), 
    .stall(1'b0), 
    .i_dividend(div_in_a), 
    .i_divisor(div_in_b), 
    .o_quotient(div_quot_out), 
    .o_remainder(div_rem_out)
  );

  // Update Shift Register for Divider
  always @(posedge clk) begin
      if (rst) begin
          for(k=0; k<8; k=k+1) begin
              div_rd_pipe[k] <= 0; 
              div_valid_pipe[k] <= 0; 
              div_info_pipe[k] <= 0;
          end
      end else begin
          for(k=7; k>0; k=k-1) begin
              div_rd_pipe[k] <= div_rd_pipe[k-1];
              div_valid_pipe[k] <= div_valid_pipe[k-1];
              div_info_pipe[k] <= div_info_pipe[k-1];
          end
          if (!stall_div && is_div_op_ex) begin 
              div_rd_pipe[0] <= e_rd;
              div_valid_pipe[0] <= 1'b1;
              div_info_pipe[0] <= {is_rem_ex, a_neg_ex, b_neg_ex}; // Store sign info
          end else begin
              div_rd_pipe[0] <= 0; div_valid_pipe[0] <= 0; div_info_pipe[0] <= 0;
          end
      end
  end

    // Logic Prepare Div Result (Sign Restore)
  wire is_rem_wb = div_info_pipe[7][2];
  wire a_neg_wb  = div_info_pipe[7][1];
  wire b_neg_wb  = div_info_pipe[7][0];
  
  wire [31:0] quot_correct = (a_neg_wb ^ b_neg_wb) ? (~div_quot_out + 1) : div_quot_out;
  wire [31:0] rem_correct  = (a_neg_wb) ? (~div_rem_out + 1) : div_rem_out;
  wire [31:0] div_final_res = is_rem_wb ? rem_correct : quot_correct;

  // Branch Logic (Simplified)
  // Check jump condition based on ALU result
  wire is_equal = (alu_result_comb == 0);
  wire is_less_signed = alu_result_comb[31];
  wire is_less_unsigned = (alu_a[31] != alu_b[31]) ? (!alu_a[31]) : alu_result_comb[31];
  reg branch_taken;
  always @(*) begin
     branch_taken = 0;
     if (e_is_branch) begin
        case(e_funct3)
            3'b000: branch_taken = is_equal;
            3'b001: branch_taken = !is_equal;
            3'b100: branch_taken = is_less_signed;
            3'b101: branch_taken = !is_less_signed;
            3'b110: branch_taken = is_less_unsigned;
            3'b111: branch_taken = !is_less_unsigned;
        endcase
     end
  end
  assign pc_cond = e_is_jump || branch_taken;
  assign pc_target = (e_is_jump && !e_alu_src1) ? (alu_a + e_imm) & ~1 : (e_pc_current + e_imm);
  assign flush_branch = pc_cond;

  // --- MEMORY STAGE ---
  always @(posedge clk) begin
    if (rst) begin
       m_pc_current <= 0; 
       m_inst <= 0; 
       m_alu_result <= 0; 
       m_rs2_data <= 0; 
       m_rd <= 0; 
       m_funct3 <= 0;
       m_mem_read <= 0; 
       m_mem_write <= 0; 
       m_reg_write <= 0; 
       m_mem_to_reg <= 0; 
       m_halt <= 0;
    end
    else if (div_valid_pipe[7]) begin // DIV COMPLETE
       m_pc_current <= 0; m_inst <= 0; // Don't trace div here
       m_alu_result <= div_final_res;
       m_rd <= div_rd_pipe[7]; 
       m_reg_write <= 1;
       m_mem_read <= 0; 
       m_mem_write <= 0; 
       m_mem_to_reg <= 0; 
       m_halt <= 0; 
       m_rs2_data <= 0; 
       m_funct3 <= 0;
    end
    else if (stall_all) begin // STALL
       m_mem_read <= 0; 
       m_mem_write <= 0; 
       m_reg_write <= 0; 
       m_halt <= 0; 
       m_pc_current <= 0;
       m_inst <= 32'h13; 
       m_rd <= 0;
    end
    else begin // NORMAL
       m_pc_current <= e_pc_current; m_inst <= e_inst;
       m_alu_result <= (e_is_jump) ? e_pc_current + 4 : final_ex_result;
       m_rs2_data <= alu_in_b_val_fwd; 
       m_rd <= e_rd; 
       m_funct3 <= e_funct3;
       m_mem_read <= e_mem_read; 
       m_mem_write <= e_mem_write; 
       m_reg_write <= e_reg_write; 
       m_mem_to_reg <= e_mem_to_reg; 
       m_halt <= e_halt;
    end
  end


  // MEMORY STAGE (MEM)
  // Logic Store & Load (Copy logic cũ của bạn, rút gọn ở đây để vừa frame)
  // ... [STORE LOGIC] ...
  always @(*) begin
      store_we_to_dmem = 0; 
      store_data_to_dmem = 0;
       addr_to_dmem = m_alu_result;
      if(m_mem_write) begin
          case(m_funct3)
             3'b000: begin 
                store_data_to_dmem={4{m_rs2_data[7:0]}}; 
                store_we_to_dmem=4'b0001<<m_alu_result[1:0]; 
              end
             3'b001: begin 
                store_data_to_dmem={2{m_rs2_data[15:0]}}; 
                store_we_to_dmem=4'b0011<<{m_alu_result[1],1'b0}; 
              end
             3'b010: begin 
                store_data_to_dmem=m_rs2_data; 
                store_we_to_dmem=4'b1111; 
              end
          endcase
      end
  end

  reg [`REG_SIZE:0] mem_data_fmt;
  // ... [LOAD LOGIC] ...
  always @(*) begin
      mem_data_fmt = load_data_from_dmem;
      case(m_funct3)
          3'b000: case(m_alu_result[1:0]) 
               2'b00: mem_data_fmt={{24{load_data_from_dmem[7]}},load_data_from_dmem[7:0]};
               2'b01: mem_data_fmt={{24{load_data_from_dmem[15]}},load_data_from_dmem[15:8]};
               2'b10: mem_data_fmt={{24{load_data_from_dmem[23]}},load_data_from_dmem[23:16]};
               2'b11: mem_data_fmt={{24{load_data_from_dmem[31]}},load_data_from_dmem[31:24]}; 
             endcase
          3'b001: case(m_alu_result[1]) 
               1'b0: mem_data_fmt={{16{load_data_from_dmem[15]}},load_data_from_dmem[15:0]};
               1'b1: mem_data_fmt={{16{load_data_from_dmem[31]}},load_data_from_dmem[31:16]}; 
             endcase

          3'b010: mem_data_fmt = load_data_from_dmem; // LW
          3'b100: case(m_alu_result[1:0]) // LBU
               2'b00: mem_data_fmt={24'b0, load_data_from_dmem[7:0]};
               2'b01: mem_data_fmt={24'b0, load_data_from_dmem[15:8]};
               2'b10: mem_data_fmt={24'b0, load_data_from_dmem[23:16]};
               2'b11: mem_data_fmt={24'b0, load_data_from_dmem[31:24]}; 
             endcase
          3'b101: case(m_alu_result[1]) // LHU
               1'b0: mem_data_fmt={16'b0, load_data_from_dmem[15:0]};
               1'b1: mem_data_fmt={16'b0, load_data_from_dmem[31:16]};
             endcase
      endcase
  end

  // --- WRITEBACK ---
  always @(posedge clk) begin
    if (rst) begin
       w_pc_current <= 0; 
       w_inst <= 0; 
       w_alu_result <= 0; 
       w_mem_data <= 0; 
       w_rd <= 0;
       w_reg_write <= 0; 
       w_mem_to_reg <= 0; 
       w_halt <= 0;
    end else begin
       w_pc_current <= m_pc_current; 
       w_inst <= m_inst;
       w_alu_result <= m_alu_result; 
       w_mem_data <= mem_data_fmt;
       w_rd <= m_rd; 
       w_reg_write <= m_reg_write; 
       w_mem_to_reg <= m_mem_to_reg; 
       w_halt <= m_halt;
    end
  end

  assign wb_rd_data = (w_mem_to_reg) ? w_mem_data : w_alu_result;
  assign wb_rd = w_rd;
  assign wb_we = w_reg_write;

  always @(*) begin
      trace_writeback_pc   = w_pc_current;
      trace_writeback_inst = w_inst; // SỬA LỖI TRACE OUTPUT
      halt                 = w_halt;
  end

endmodule


module MemorySingleCycle #(
    parameter NUM_WORDS = 512
) (
    input                    rst,                 // rst for both imem and dmem
    input                    clk,                 // clock for both imem and dmem
	                                              // The memory reads/writes on @(negedge clk)
    input      [`REG_SIZE:0] pc_to_imem,          // must always be aligned to a 4B boundary
    output reg [`REG_SIZE:0] inst_from_imem,      // the value at memory location pc_to_imem
    input      [`REG_SIZE:0] addr_to_dmem,        // must always be aligned to a 4B boundary
    output reg [`REG_SIZE:0] load_data_from_dmem, // the value at memory location addr_to_dmem
    input      [`REG_SIZE:0] store_data_to_dmem,  // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
    // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
    // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
    input      [        3:0] store_we_to_dmem
);

  // memory is arranged as an array of 4B words
  reg [`REG_SIZE:0] mem_array[0:NUM_WORDS-1];
  integer i;
  // preload instructions to mem_array
  initial begin
    for (i = 0; i < NUM_WORDS; i = i + 1) begin
        mem_array[i] = 32'd0; 
    end

    //$readmemh("C:/BKEL/SoC/Assignment/05_pipelined/mem_initial_contents.hex", mem_array);
    $readmemh("mem_initial_contents.hex", mem_array);
  end

  localparam AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam AddrLsb = 2;

  always @(negedge clk) begin
    inst_from_imem <= mem_array[{pc_to_imem[AddrMsb:AddrLsb]}];
  end

  always @(negedge clk) begin
    if (store_we_to_dmem[0]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
    end
    if (store_we_to_dmem[1]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
    end
    if (store_we_to_dmem[2]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
    end
    if (store_we_to_dmem[3]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
    end
    // dmem is "read-first": read returns value before the write
    load_data_from_dmem <= mem_array[{addr_to_dmem[AddrMsb:AddrLsb]}];
  end
endmodule

/* This design has just one clock for both processor and memory. */
module Processor (
    input                 clk,
    input                 rst,
    output                halt,
    output [ `REG_SIZE:0] trace_writeback_pc,
    output [`INST_SIZE:0] trace_writeback_inst
);

  wire [`INST_SIZE:0] inst_from_imem;
  wire [ `REG_SIZE:0] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [         3:0] mem_data_we;

  // This wire is set by cocotb to the name of the currently-running test, to make it easier
  // to see what is going on in the waveforms.
  wire [(8*32)-1:0] test_case;

  MemorySingleCycle #(
      .NUM_WORDS(8192)
  ) memory (
    .rst                 (rst),
    .clk                 (clk),
    // imem is read-only
    .pc_to_imem          (pc_to_imem),
    .inst_from_imem      (inst_from_imem),
    // dmem is read-write
    .addr_to_dmem        (mem_data_addr),
    .load_data_from_dmem (mem_data_loaded_value),
    .store_data_to_dmem  (mem_data_to_write),
    .store_we_to_dmem    (mem_data_we)
  );

  DatapathPipelined datapath (
    .clk                  (clk),
    .rst                  (rst),
    .pc_to_imem           (pc_to_imem),
    .inst_from_imem       (inst_from_imem),
    .addr_to_dmem         (mem_data_addr),
    .store_data_to_dmem   (mem_data_to_write),
    .store_we_to_dmem     (mem_data_we),
    .load_data_from_dmem  (mem_data_loaded_value),
    .halt                 (halt),
    .trace_writeback_pc   (trace_writeback_pc),
    .trace_writeback_inst (trace_writeback_inst)
  );

endmodule
