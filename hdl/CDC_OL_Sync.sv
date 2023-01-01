//                              -*- Mode: Verilog -*-
// Filename        : CDC_OL_Sync.sv
// Description     : Single signal open-loop synchronizer for clock domain crossing.
//                   See Cummings2008 p.16 (http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf)
// Author          : Stephan Proß
// Created On      : Thu Dec  1 09:18:48 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 09:18:48 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

module CDC_OL_SYNC
  (
   // Signals from clock domain A.
   input logic  CLK_A_I,
   input logic  A_I,

   // Signals from clock domain B.
   input logic  CLK_B_I,
   output logic B_O
   );

   logic        reg_a;
   // Register input A in its clock domain.
   always_ff @(posedge CLK_A_I) begin
      reg_a <= A_I;
   end

   logic [1:0]  reg_b;
   assign B_O = reg_b[1];
   // Sample reg_a in clock domain b using a double buffer
   // to deal with meta-stability.
   always_ff @(posedge CLK_B_I) begin
      reg_b[0] <= reg_a;
      reg_b[1] <= reg_b[0];
   end

endmodule // CDC_OL_SYNC
