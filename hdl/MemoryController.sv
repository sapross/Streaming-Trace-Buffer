//                              -*- Mode: Verilog -*-
// Filename        : MemoryController.sv
// Description     : Memory Controller for YOSYS BlockRAM_1KB.sv blackbox used in Streaming Trace Buffer.
// Author          : Stephan Proß
// Created On      : Thu Dec 29 15:28:43 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec 29 15:28:43 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

`include "../lib/STB_PKG.svh"

module MemoryController (
                         input logic                      CLK_I,
                         input logic                      RST_NI,

                         // Signals for/from TraceLogger
                         output logic                     RW_TURN_O,
                         output logic                     LOGGER_WRITE_ALLOW_O,
                         output logic                     LOGGER_READ_ALLOW_O,
                         input logic [TRB_ADDR_WIDTH-1:0] LOGGER_READ_PTR_I,
                         input logic [TRB_ADDR_WIDTH-1:0] LOGGER_WRITE_PTR_I,
                         input logic                      LOGGER_WRITE_I,
                         input logic [TRB_WIDTH-1:0]      LOGGER_DATA_I,
                         output logic [TRB_WIDTH-1:0]     LOGGER_DATA_O,
                         input logic                      TRG_EVENT_I,

                         // Signals for/from System Interface
                         input logic [1:0]                MODE_I,
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
   logic                    write_turn, read_turn;
   assign read_turn = ~ write_turn;
   assign RW_TURN_O = write_turn;
   // System has write turn on turn = 0
   always_ff @(posedge CLK_I) begin
      if (!RST_NI) begin
         write_turn <= 0;
      end
      else begin
            write_turn <= ~write_turn;
      end
   end

   // ---------------------------------------------------------------------------------------
   // ---- Read & write pointer management ----
   // ---------------------------------------------------------------------------------------


   function logic incmod_unequal(input int unsigned a, input int unsigned b);
      int unsigned next;
      next = ((a + 1) % TRB_DEPTH);
      return (next != b);
   endfunction // incmod_unequal

   bit [TRB_ADDR_WIDTH-1:0]           log_rptr, log_wptr;
   bit [TRB_ADDR_WIDTH-1:0]           log_wptr_next;
   assign log_rptr = LOGGER_READ_PTR_I;
   assign log_wptr = LOGGER_WRITE_PTR_I;
   assign log_wptr_next = (log_wptr + 1) % TRB_DEPTH;


   bit [TRB_ADDR_WIDTH-1:0]           sys_rptr, sys_wptr;
   bit [TRB_ADDR_WIDTH-1:0]           sys_wptr_next;
   assign sys_wptr_next = (sys_wptr + 1) % TRB_DEPTH;

   logic                              log_read_allow;
   assign LOGGER_READ_ALLOW_O = log_read_allow;
   logic                              log_write_allow;
   assign LOGGER_WRITE_ALLOW_O = log_write_allow;
   logic                              sys_read_allow;
   assign READ_ALLOW_O = sys_read_allow;
   logic                              sys_write_allow;
   assign WRITE_ALLOW_O = sys_write_allow;

   // Signals indicating whether io has been read/written to memory
   // after a address change..
   logic                              sys_read_valid;

   logic                              sys_write_valid;


   // Logger can ignore system write pointer if in trace or read-only stream mode.
   assign log_read_allow = MODE_I == trace_mode  ||
                           MODE_I == r_stream_mode ||
                           log_rptr != sys_wptr;

   // Logger can ignore system read pointer if in trace mode or write-only stream mode.
   assign log_write_allow = MODE_I == trace_mode ||
                            MODE_I == w_stream_mode ||
                            (log_wptr_next != log_rptr);

   // Conversely, the system can ignore logger write pointer when in trace mode
   // with trigger event. Otherwise the system read pointer must be behind the logger
   // write pointer if not in an write-only mode.
   always_comb begin
      sys_read_allow = 0;
      if (MODE_I == trace_mode) begin
        sys_read_allow = TRG_EVENT_I & !read_turn;
      end
      else if(MODE_I != w_stream_mode) begin
         if (sys_rptr != log_wptr) begin
            sys_read_allow = !read_turn;
         end
      end
   end

   // In write-only mode a collision with the system read pointer is irrelevant.
   // Only in RW-Stream mode does the potential pointer collision become relevant.
   always_comb begin
      sys_write_allow = 0;
      if (MODE_I == w_stream_mode) begin
        sys_write_allow = !write_turn;
      end
      else if(MODE_I == rw_stream_mode) begin
         if (sys_wptr_next != sys_rptr) begin
            sys_write_allow = !write_turn;
         end
      end
   end

   logic                              sys_pending_read;
   always_ff @(posedge CLK_I) begin : READ_POINTER_INC
      if (!RST_NI) begin
         sys_rptr <= TRB_DEPTH/2-1;
         sys_pending_read <= 0;
      end
      else begin
         if (MODE_I == trace_mode && !TRG_EVENT_I) begin
            // In Trace-Mode, read pointer follows write pointer from Logger
            // until trigger event is registered.
            sys_rptr <= log_wptr;
         end
         else begin
            // In either streaming mode or trace mode with trigger event,
            // increment sys_rptr on read from system interface.
            if (READ_I) begin
               sys_pending_read <= 1;
            end
            if (READ_I || sys_pending_read) begin
               if (sys_read_allow && (MODE_I == trace_mode || sys_rptr != sys_wptr)) begin
                  sys_rptr <= (sys_rptr + 1) % TRB_DEPTH;
                  sys_pending_read <= 0;
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
         if (!write_turn && WRITE_I) begin
            if (sys_write_allow) begin
               if ( MODE_I == rw_stream_mode && (sys_wptr + 1) % TRB_DEPTH != sys_rptr) begin
                  sys_wptr <= (sys_wptr + 1) % TRB_DEPTH;
               end
               else if(MODE_I == w_stream_mode) begin
                  sys_wptr <= (sys_wptr + 1) % TRB_DEPTH;
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

   // Multiplex addresses and write data dependent on write_turn.
   always_comb begin : RW_STROBE_MUX
      // Prevent system interface to write to memory
      // if read only is set.
      if(write_turn && LOGGER_WRITE_I) begin
         write_addr <= log_wptr;
         write_data <= LOGGER_DATA_I;
      end
      else begin
         write_data <= WRITE_DATA_I;
         write_addr <= sys_wptr;
      end
      // read_data to appropriate output is
      // one cycle delayed
      if(read_turn) begin
         read_addr <= log_rptr;
      end
      else begin
         read_addr <= sys_rptr;
      end
   end

   always_ff @(posedge CLK_I) begin: MUX_READ_DATA
      if (!RST_NI) begin
         LOGGER_DATA_O <= '0;
         READ_DATA_O <= '0;
      end
      else begin
         if(!read_turn) begin
            READ_DATA_O <= read_data;
         end
         else begin
            LOGGER_DATA_O <= read_data;
         end
      end
   end


`define SIM

`ifndef SIM
   BlockRAM_1KB bram
     (
      .clk(CLK_I),
      .rd_addr(read_addr),
      .rd_data(read_data),
      .wr_addr(write_addr),
      .wr_data(write_data),
      .C0(1'b0), // {C0,C1} = Write Mask
      .C1(1'b0),
      .C2(1'b0), // {C2,C3} = Read Mask
      .C3(1'b0),
      .C4(1'b1), // Always Write Enable
      .C5(1'b0)  // Register output?
      );
`else
   SimBRAM_1KB bram
     (
      .clk(CLK_I),
      .rd_addr(read_addr),
      .rd_data(read_data),
      .wr_addr(write_addr),
      .wr_data(write_data),
      .C0(1'b0), // {C0,C1} = Write Mask
      .C1(1'b0),
      .C2(1'b0), // {C2,C3} = Read Mask
      .C3(1'b0),
      .C4(1'b1), // Always Write Enable
      .C5(1'b0)  // Register output?
      );
`endif

// `ifdef SIM
//  `include "../tb/TB_MemoryController_Assertions.svh"
// `endif;

endmodule // MemoryController
