`timescale 1ns / 1ps

// Define parameters
`define REG_SIZE 31
`define INST_SIZE 31

module test_bench_processor;

  // --- 1. Signal Declaration ---
  reg clk;
  reg rst;
  wire halt;
  wire [`REG_SIZE:0] trace_wb_pc;
  wire [`INST_SIZE:0] trace_wb_inst;

  // Biến đếm số lệnh thực tế đã hoàn thành
  integer instructions_retired;
  
  // --- 2. Clock Generation ---
  initial begin
    clk = 0;
    forever #2 clk = ~clk; // Chu kỳ 4ns
  end

  integer i;

  // --- 3. Instantiate Processor (DUT) ---
  Processor dut (
    .clk(clk),
    .rst(rst),
    .halt(halt),
    .trace_writeback_pc(trace_wb_pc),
    .trace_writeback_inst(trace_wb_inst)
  );

  // --- 4. Variables for Verification ---
  integer cycle_count;
  integer max_cycles = 5000;

  // --- 5. Helper Strings for Debug ---
  reg [8*20:1] event_str; 

  // --- 6. Test Scenario ---
  initial begin
    $dumpfile("test_bench_processor.vcd");
    $dumpvars(0, test_bench_processor);
    
    // Init
    rst = 1;
    cycle_count = 0;
    instructions_retired = 0;

    // Reset 2 cycles
    repeat (2) @(posedge clk);
    rst = 0;
    
    // --- IN HEADER CÓ MÀU ---
    $display("\n=== START PIPELINE SIMULATION (COLORIZED) ===");
    $display("Testcase: %s", "M-Extension & Hazard Stress Test");
    $display("--------------------------------------------------------------------------------------------------------------------------");
    // Header: Cyan(IF) | Blue(ID) | Magenta(EX) | Yellow(MEM) | Green(WB) | Red(Event)
    $display(" Cyc | \033[1;36m   IF (PC)  \033[0m | \033[1;34m   ID (PC)  \033[0m | \033[1;35m   EX (PC)  \033[0m | \033[1;33m   MEM (PC) \033[0m | \033[1;32m   WB (PC)  \033[0m | \033[1;32m WB Data  \033[0m | \033[1;31m Events (Hazard) \033[0m");
    $display("-----+--------------+--------------+--------------+--------------+--------------+------------+-----------------------");

    // Loop
    while (!halt && cycle_count < max_cycles) begin
        // Chờ cạnh xuống để lấy dữ liệu ổn định
        @(negedge clk); 

        // 1. Xác định sự kiện Hazard (Tô màu ĐỎ cho sự kiện)
        event_str = "";
        if (dut.datapath.flush_branch) begin
            // \033[1;31m = Bold Red
            event_str = "FLUSH (Branch)";
        end else if (dut.datapath.stall_load_use) begin
            event_str = "STALL (Ld-Use)";
        end else if (dut.datapath.stall_div) begin
            event_str = "STALL (Divide)";
        end

        // 2. In Trace Pipeline với màu sắc
        // Format: %4d | Cyan | Blue | Magenta | Yellow | Green | Green | EventString
        $display("%4d | \033[36m 0x%8h \033[0m | \033[34m 0x%8h \033[0m | \033[35m 0x%8h \033[0m | \033[33m 0x%8h \033[0m | \033[32m 0x%8h \033[0m | \033[32m %8h \033[0m | \033[1m\033[31m %s \033[0m", 
            cycle_count,
            dut.datapath.f_pc_current,  // IF - Cyan
            dut.datapath.d_pc_current,  // ID - Blue
            dut.datapath.e_pc_current,  // EX - Magenta
            dut.datapath.m_pc_current,  // MEM - Yellow
            dut.datapath.w_pc_current,  // WB - Green
            dut.datapath.wb_rd_data,    // WB Data - Green
            event_str                   // Event - Red (Đã format ở trên)
        );
        $display("-----+--------------+--------------+--------------+--------------+--------------+------------+-----------------------");

        // Đếm số lệnh hoàn thành
        if (dut.datapath.w_pc_current != 0 && dut.datapath.w_reg_write) begin
            instructions_retired = instructions_retired + 1;
        end

        cycle_count = cycle_count + 1;
        
        @(posedge clk);
    end

    // --- Completion Report ---
    //$display("--------------------------------------------------------------------------------------------------------------------------");
    
    if (halt)
        $display("\n\033[1;32m>>> Processor HALTED at cycle %0d \033[0m", cycle_count);
    else
        $display("\n\033[1;31m>>> Timeout at cycle %0d \033[0m", max_cycles);

    // Tính toán hiệu năng
    if (instructions_retired > 0) begin
        $display(">>> Statistics:");
        $display("    Total Cycles       : %0d", cycle_count);
        $display("    Instr Retired      : %0d (Approx)", instructions_retired);
        $display("    CPI (Cycles/Instr) : %0.2f (Ideal = 1.0)", $itor(cycle_count)/$itor(instructions_retired));
    end

    $display("---------------------------------------------------");
    $display("State of Register File:");
    for (i = 0; i < 32; i = i + 1) begin
        if (i % 4 == 0) $write("\n");
        // Highlight thanh ghi khác 0 bằng màu trắng đậm
        if (dut.datapath.rf.regs[i] != 0)
            $write("x%02d: \033[1m\033[36m%8h\033[0m (%10d ) | ", i, dut.datapath.rf.regs[i], $signed(dut.datapath.rf.regs[i]));
        else
            $write("x%02d: %8h (%10d ) | ", i, dut.datapath.rf.regs[i], $signed(dut.datapath.rf.regs[i]));
    end
    $display("\n---------------------------------------------------");
    
    #100;
    $finish;
  end

endmodule