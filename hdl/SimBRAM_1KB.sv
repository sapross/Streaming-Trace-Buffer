//                              -*- Mode: Verilog -*-
// Filename        : SimBRAM_1KB.sv
// Description     : BRAM implementation for simulation (& FPGA synthesis)
// Author          : Stephan Proß
// Created On      : Sat Dec 31 15:22:14 2022
// Last Modified By: Stephan Proß
// Last Modified On: Sat Dec 31 15:22:14 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;

module SimBRAM_1KB (
                    input logic                      clk,
                    input logic [TRB_ADDR_WIDTH-1:0] rd_addr,
                    output logic [TRB_WIDTH-1:0]     rd_data,
                    input logic [TRB_ADDR_WIDTH-1:0] wr_addr,
                    input logic [TRB_WIDTH-1:0]      wr_data,
                    input logic                      C0, // Dummy Configuration signals
                    input logic                      C1,
                    input logic                      C2,
                    input logic                      C3,
                    input logic                      C4,
                    input logic                      C5
) ;

   logic [TRB_DEPTH-1:0]                             ram [TRB_WIDTH-1:0] = '{default : '0};
   always_ff @(posedge clk) begin
      ram[wr_addr] <= wr_data;
      rd_data <= ram[rd_addr];
   end

endmodule // SimBRAM_1KB
