`timescale 1ns / 1ps

/**
 * @param a first 1-bit input
 * @param b second 1-bit input
 * @param g whether a and b generate a carry
 * @param p whether a and b would propagate an incoming carry
 */
module gp1(input wire a, b,
           output wire g, p);
   assign g = a & b;
   assign p = a ^ b;
endmodule

/**
 * Computes aggregate generate/propagate signals over a 4-bit window.
 * @param gin incoming generate signals
 * @param pin incoming propagate signals
 * @param cin the incoming carry
 * @param gout whether these 4 bits internally would generate a carry-out (independent of cin)
 * @param pout whether these 4 bits internally would propagate an incoming carry from cin
 * @param cout the carry outs for the low-order 3 bits
 */
module gp4(input wire [3:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [2:0] cout,
           output wire [3:0] sum
           );

   wire [3:0] g, p;

   genvar i;

   generate
      for (i = 0; i < 4; i = i + 1)
      begin
         gp1 gp(
            .a(gin[i]),
            .b(pin[i]),
            .g(g[i]),
            .p(p[i])
         );
      end
   endgenerate

   assign cout[0] = g[0] | p[0] & cin;
   assign cout[1] = g[1] | p[1] & cout[0];
   assign cout[2] = g[2] | p[2] & cout[1];
   
   assign gout = g[3] 
               | p[3] & g[2] 
               | p[3] & p[2] & g[1]
               | p[3] & p[2] & p[1] & g[0];
   assign pout = &p;

   assign sum[0] = p[0] ^ cin;
   assign sum[1] = p[1] ^ cout[0];
   assign sum[2] = p[2] ^ cout[1];
   assign sum[3] = p[3] ^ cout[2];
   
endmodule

/** Same as gp4 but for an 8-bit window instead */
module gp8(input wire [7:0] gin, pin,
           input wire cin,
           output wire gout, pout,
           output wire [6:0] cout,
           output wire [7:0] sum
           );

   wire gout_lower, pout_lower;
   wire gout_upper, pout_upper;
   
   gp4 lower_gp4(
      .gin(gin[3:0]),
      .pin(pin[3:0]),
      .cin(cin),
      .gout(gout_lower),
      .pout(pout_lower),
      .cout(cout[2:0]), // c1, c2, c3
      .sum(sum[3:0])
   );

   wire c4;
   assign c4 = gout_lower | (pout_lower & cin);
   assign cout[3] = c4;

   gp4 upper_gp4(
      .gin(gin[7:4]),
      .pin(pin[7:4]),
      .cin(c4),
      .gout(gout_upper),
      .pout(pout_upper),
      .cout(cout[6:4]), // c5, c6, c7
      .sum(sum[7:4])
   );

   assign gout = gout_upper | (pout_upper & gout_lower);
   assign pout = pout_upper & pout_lower;

endmodule

module cla
  (input wire [31:0]  a, b,
   input wire         cin,
   output wire [31:0] sum);

   // TODO: your code here
   wire gout0, gout1, gout2, gout3;
   wire pout0, pout1, pout2, pout3;
   wire [30:0] cout;

   gp8 gp8_0(
      .gin(a[7:0]),
      .pin(b[7:0]),
      .cin(cin),
      .gout(gout0),
      .pout(pout0),
      .cout(cout[6:0]), // c1 -> c7
      .sum(sum[7:0])
   );

   wire c8;
   assign c8 = gout0 | (pout0 & cin);
   assign cout[7] = gout0 | (pout0 & cin);

   gp8 gp8_1(
      .gin(a[15:8]),
      .pin(b[15:8]),
      .cin(c8),
      .gout(gout1),
      .pout(pout1),
      .cout(cout[14:8]), // c9 -> c15
      .sum(sum[15:8])
   );

   wire c16;
   assign c16 = gout1 | (pout1 & cin);
   assign cout[15] = gout1 | (pout1 & cin);

   gp8 gp8_2(
      .gin(a[23:16]),
      .pin(b[23:16]),
      .cin(c16),
      .gout(gout2),
      .pout(pout2),
      .cout(cout[22:16]), // c17 -> c23
      .sum(sum[23:16])
   );

   wire c24;
   assign c24 = gout2 | (pout2 & cin);
   assign cout[23] = gout2 | (pout2 & cin);

   gp8 gp8_3(
      .gin(a[31:24]),
      .pin(b[31:24]),
      .cin(c24),
      .gout(gout3),
      .pout(pout3),
      .cout(cout[30:24]), // c25 -> c31
      .sum(sum[31:24])
   );



endmodule
