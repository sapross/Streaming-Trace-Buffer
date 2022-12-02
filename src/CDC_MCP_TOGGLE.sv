//                              -*- Mode: Verilog -*-
// Filename        : CDC_MCP_TOGGLE.sv
// Description     : Clock domain crossing with multi cycle path formulation.
//                   Makes use of toggle pulse generation.
//                   See Cummings2008 p.25 (http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf)
// Author          : Stephan Proß
// Created On      : Thu Dec  1 09:18:48 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 09:18:48 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


module CDC_MCP_TOGGLE #(
                        parameter integer unsigned WIDTH = 5
                        ) (
                           // Signals from clock domain A.
                           input logic              CLKA_I,
                           // Data to be synchronized.
                           input logic [WIDTH-1:0]  DA_I,
                           // Store signal for synchronization.
                           input logic              STA_I,

                           // Signals from clock domain B.
                           input logic              CLKB_I,
                           output logic [WIDTH-1:0] DB_O
                           ) ;

   // Register input DA_I in reg_a
   logic [WIDTH-1:0]                                reg_a;
   always_ff @(posedge CLKA_I) begin
      if (STA_I) begin
         reg_a = DA_I;
      end
   end

   //Turn pulse in STA_I into toggle signal.
   logic                                            toggle_st;
   always_ff @(posedge CLKA_I) begin : PULSE_GEN
      toggle_st = STA_I ^ toggle_st;
   end

   // Using toggle_st, produce a synchronized pulse.
   logic [2:0] q_b;
   always_ff @(posedge CLKB_I) begin : PULSE_SYNCHRONIZER
      q_b = {q_b[2:1],toggle_st};
   end
   logic       ld_b;
   assign ld_b = q_b[2] ^ q_b[1];

   // Register reg_a in clock domain B using synchronized pulse.
   logic [WIDTH-1:0]                                reg_b;
   always_ff @(posedge CLKB_I) begin
      if (ld_b) begin
         reg_b = reg_a;
      end
   end
   assign DB_O = reg_b;

endmodule // CDC_MCP_TOGGLE
