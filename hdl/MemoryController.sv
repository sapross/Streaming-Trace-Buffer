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
                         output logic                     LOGGER_WRITE_ALLOW_O,
                         output logic                     LOGGER_READ_ALLOW_O,
                         input logic [TRB_ADDR_WIDTH-1:0] LOGGER_READ_PTR_I,
                         input logic [TRB_ADDR_WIDTH-1:0] LOGGER_WRITE_PTR_I,
                         input logic                      LOGGER_WRITE_I,
                         input logic [TRB_WIDTH-1:0]      LOGGER_DATA_I,
                         output logic [TRB_WIDTH-1:0]     LOGGER_DATA_O,
                         input logic                      TRG_EVENT_I,

                         // Signals for System Interface
                         input logic                      MODE_I,
                         output logic                     WRITE_ALLOW_O,
                         output logic                     READ_ALLOW_O,
                         output logic [TRB_WIDTH-1:0]     READ_DATA_O,
                         input logic                      READ_I,
                         input logic [TRB_WIDTH-1:0]      WRITE_DATA_I,
                         input logic                      WRITE_I
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


   function logic incmod_unequal(input int unsigned a, input int unsigned b);
      return (a+1)%TRB_DEPTH != b;
   endfunction // incmod_unequal

   bit [TRB_ADDR_WIDTH-1:0]           log_rptr, log_wptr;
   assign log_rptr = LOGGER_READ_PTR_I;
   assign log_wptr = LOGGER_WRITE_PTR_I;

   bit [TRB_ADDR_WIDTH-1:0]           sys_rptr, sys_wptr;

   logic                              log_read_allow;
   assign LOGGER_READ_ALLOW_O = log_read_allow;
   logic                              log_write_allow;
   assign LOGGER_WRITE_ALLOW_O = log_write_allow;
   logic                              sys_read_allow;
   assign READ_ALLOW_O = sys_read_allow;
   logic                              sys_write_allow;
   assign WRITE_ALLOW_O = sys_write_allow;


   assign log_read_allow = log_rptr != sys_wptr;
   assign log_write_allow = incmod_unequal(log_wptr, log_rptr);

   assign sys_read_allow = sys_rptr != log_wptr;
   assign sys_write_allow = incmod_unequal(sys_wptr, sys_rptr);



   always_ff @(posedge CLK_I) begin : READ_POINTER_INC
      if (!RST_NI) begin
         sys_rptr <= TRB_DEPTH/2-1;
      end
      else begin
         if (!MODE_I && !TRG_EVENT_I) begin
            // In Trace-Mode, read pointer follows write pointer from Logger
            // until trigger event is registered.
            sys_rptr <= (log_wptr + 1 ) & TRB_DEPTH;
         end
         else begin
            // In either streaming mode or trace mode with trigger event,
            // increment sys_rptr on read from system interface.
            if (!turn) begin
               if (READ_I) begin
                  if (sys_read_allow && sys_rptr != sys_wptr) begin
                     sys_rptr <= (sys_rptr + 1) % TRB_DEPTH;
                  end
               end
            end
         end
      end
   end

   always_ff @(posedge CLK_I) begin : WRITE_POINTER_INC
      if (!RST_NI) begin
         sys_wptr <= 0;
      end
      else begin
         if (MODE_I) begin
            // Writing is disabled when in Trace-Mode.
            if (!turn) begin
               if (WRITE_I) begin
                  if (sys_write_allow && (sys_wptr + 1) % TRB_DEPTH != sys_rptr) begin
                     sys_wptr <= (sys_wptr + 1) % TRB_DEPTH;
                  end
               end
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
      if (!turn && !MODE_I) begin
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
