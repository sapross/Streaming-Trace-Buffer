//                              -*- Mode: Verilog -*-
// Filename        : MemoryController.sv
// Description     : Memory Controller for YOSYS BlockRAM_1KB.sv blackbox used in Streaming Trace Buffer.
// Author          : Stephan Proß
// Created On      : Thu Dec 29 15:28:43 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec 29 15:28:43 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;

module MemoryController (
                         input logic                      CLK_I,
                         input logic                      RST_NI,

                         // Signals for TraceLogger
                         output logic                     RW_TURN_O,
                         input logic [TRB_ADDR_WIDTH-1:0] READ_PTR_I,
                         input logic [TRB_ADDR_WIDTH-1:0] WRITE_PTR_I,
                         input logic                      LOGGER_WRITE_I,
                         input logic [TRB_WIDTH-1:0]      LOGGER_DATA_I,
                         output logic [TRB_WIDTH-1:0]     LOGGER_DATA_O,

                         // Signals for System Interface
                         input logic                      READ_ONLY_I,
                         output logic [TRB_WIDTH-1:0]     READ_DATA_O,
                         input logic                      READ_I,
                         input logic [TRB_WIDTH-1:0]      WRITE_DATA_I,
                         input logic                      WRITE_I,

                         // Signals for both
                         output logic                     WRITE_ALLOW_O,
                         output logic                     READ_ALLOW_O
                         );


   // ---------------------------------------------------------------------------------------
   // ---- RW Strobe/Turn generation ----
   // ---------------------------------------------------------------------------------------
   logic                    turn;
   assign RW_TURN_O = turn;
   always_ff @(posedge CLK_I) begin
      if (!RST_NI) begin
         turn <= 0;
      end
      else begin
         turn <= ~turn;
      end
   end

   // ---------------------------------------------------------------------------------------
   // ---- Read & write pointer management ----
   // ---------------------------------------------------------------------------------------
   bit [TRB_ADDR_WIDTH-1:0]           log_rptr, log_wptr;
   assign log_rptr = READ_PTR_I;
   assign log_wptr = WRITE_PTR_I;

   bit [TRB_ADDR_WIDTH-1:0]           sys_rptr, sys_wptr;

   logic                              read_allow;
   logic                              write_allow;
   assign read_allow = sys_rptr != log_wptr;
   assign write_allow = (sys_wptr +1) % TRB_DEPTH != log_rptr;
   assign READ_ALLOW_O = read_allow;
   assign WRITE_ALLOW_O = write_allow;

   always_ff @(posedge CLK_I) begin
      if (!RST_NI) begin
         sys_rptr <= 1;
      end
      else begin
         if (!turn) begin
            if (READ_I && read_allow) begin
               sys_rptr <= (sys_rptr + 1) % TRB_DEPTH;
            end
         end
      end
   end

   always_ff @(posedge CLK_I) begin
      if (!RST_NI) begin
         sys_wptr <= 0;
      end
      else begin
         if (!turn) begin
            if (WRITE_I && write_allow) begin
               sys_wptr <= (sys_wptr + 1) % TRB_DEPTH;
            end
         end
      end
   end


   // ---------------------------------------------------------------------------------------
   // ---- BRAM IO Multiplex ----
   // ---------------------------------------------------------------------------------------
   bit [TRB_ADDR_WIDTH-1:0] read_addr, write_addr;
   logic [TRB_WIDTH-1:0]     read_data, write_data;

   // Multiplex addresses and write data dependent on turn.
   always_comb begin : RW_STROBE_MUX
      if (!turn) begin
         read_addr = sys_rptr;
      end else begin
         read_addr = log_rptr;
      end
      // Prevent system interface to write to memory
      // if read only is set.
      if (!turn && !READ_ONLY_I) begin
         write_addr = sys_wptr;
         write_data = WRITE_DATA_I;
      end
      else begin
         write_addr = log_wptr;
         write_data = LOGGER_DATA_I;
      end
   end

   // Collect read data and multiplex to correct output.
   always_ff @(posedge CLK_I) begin : COLLECT_DATA
      if (!RST_NI) begin
         READ_DATA_O <= '0;
         LOGGER_DATA_O <= '0;
      end
      else begin
         if(!turn) begin
            READ_DATA_O <= read_data;
         end
         else begin
            LOGGER_DATA_O <= read_data;
         end
      end
   end

`ifndef SIM
   BlockRAM_1KB bram
     (
      .clk(CLK_I),
      .rd_addr(read_addr),
      .rd_data(read_data),
      .wr_addr(write_addr),
      .wr_data(write_data),
      .C0(0), // {C0,C1} = Write Mask
      .C1(0),
      .C2(0), // {C2,C3} = Read Mask
      .C3(0),
      .C4(1), // Always Write Enable
      .C5(0)  // Register output?
      );
`else
   SimBRAM_1KB bram
     (
      .clk(CLK_I),
      .rd_addr(read_addr),
      .rd_data(read_data),
      .wr_addr(write_addr),
      .wr_data(write_data),
      .C0(0), // {C0,C1} = Write Mask
      .C1(0),
      .C2(0), // {C2,C3} = Read Mask
      .C3(0),
      .C4(1), // Always Write Enable
      .C5(0)  // Register output?
      );
`endif

`include "../tb/TB_MemoryController_Assertions.svh"

endmodule // MemoryController
