`timescale 1ns / 1ns

module DividerUnsignedPipelined (
    input             clk, rst, stall,
    input      [31:0] i_dividend,
    input      [31:0] i_divisor,
    output reg [31:0] o_remainder,
    output reg [31:0] o_quotient
);

    wire [31:0] w_dividend  [0:7][0:4];
    wire [31:0] w_remainder [0:7][0:4];
    wire [31:0] w_quotient  [0:7][0:4];

    // Pipeline registers store results between stages
    // There are 8 register stages (0 to 7)
    reg [31:0] r_dividend  [0:7];
    reg [31:0] r_remainder [0:7];
    reg [31:0] r_quotient  [0:7];
    reg [31:0] r_divisor   [0:7]; 

    genvar s, i; // s = stage (0-7), i = iteration (0-3)

    generate
        for (s = 0; s < 8; s = s + 1) begin : gen_stages

            // First, connect inputs to the stage
            if (s == 0) begin
                // First stage takes input from module inputs
                assign w_dividend[s][0]  = i_dividend;
                assign w_remainder[s][0] = 32'b0; // Initial remainder is 0
                assign w_quotient[s][0]  = 32'b0; // Initial quotient is 0
            end else begin
                // Subsequent stages take data from the previous stage's registers
                assign w_dividend[s][0]  = r_dividend[s-1];
                assign w_remainder[s][0] = r_remainder[s-1];
                assign w_quotient[s][0]  = r_quotient[s-1];
            end

            // 2. Instantiate 4 "divu_1iter" instances in series
            for (i = 0; i < 4; i = i + 1) begin : gen_iters
                divu_1iter u_iter (
                    .i_dividend  (w_dividend[s][i]),
                    .i_divisor   ((s == 0) ? i_divisor : r_divisor[s-1]), 
                    .i_remainder (w_remainder[s][i]),
                    .i_quotient  (w_quotient[s][i]),
                    
                    .o_dividend  (w_dividend[s][i+1]),
                    .o_remainder (w_remainder[s][i+1]),
                    .o_quotient  (w_quotient[s][i+1])
                );
            end

            // 3. PIPELINE REGISTER LOGIC (STORE RESULTS AFTER 4 ITERATIONS)
            always @(posedge clk) begin
                if (rst) begin
                    r_dividend[s]  <= 0;
                    r_remainder[s] <= 0;
                    r_quotient[s]  <= 0;
                    r_divisor[s]   <= 0;
                end else begin
                    // Store the final output (position 4) of the logic chain into registers
                    r_dividend[s]  <= w_dividend[s][4];
                    r_remainder[s] <= w_remainder[s][4];
                    r_quotient[s]  <= w_quotient[s][4];
                    
                    // Pass divisor to the register of this stage
                    if (s == 0) 
                        r_divisor[s] <= i_divisor;
                    else 
                        r_divisor[s] <= r_divisor[s-1];
                end
            end
        end
    endgenerate

    // 4. OUTPUT OF MODULE IS OUTPUT OF FINAL STAGE REGISTER (Stage 7)
    always @(*) begin
        o_quotient  = r_quotient[7];
        o_remainder = r_remainder[7];
    end

endmodule

// ============================================================
// MODULE divu_1iter 
// ============================================================
module divu_1iter (
    input      [31:0] i_dividend,
    input      [31:0] i_divisor,
    input      [31:0] i_remainder,
    input      [31:0] i_quotient,
    output     [31:0] o_dividend,
    output     [31:0] o_remainder,
    output     [31:0] o_quotient
);
    reg [31:0] remainder_r;
    reg [31:0] quotient_r;
    reg [31:0] dividend_r;

    always @(*) begin
        // Shift remainder left by 1 bit, bring MSB of dividend into LSB of remainder
        remainder_r = (i_remainder << 1) | ((i_dividend >> 31) & 1'b1);
        
        // compare remainder with divisor
        if (remainder_r < i_divisor) begin
            quotient_r = i_quotient << 1;       // Cannot subtract, shift 0 into quotient
        end else begin
            quotient_r = (i_quotient << 1) | 1'b1; // Can subtract, shift 1 into quotient
            remainder_r = remainder_r + (~i_divisor + 1'b1);; // Update remainder
        end
        
        dividend_r = i_dividend << 1; // Shift dividend preparing for next iteration
    end

    assign o_dividend  = dividend_r;
    assign o_remainder = remainder_r;
    assign o_quotient  = quotient_r;

endmodule