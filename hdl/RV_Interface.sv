//                              -*- Mode: Verilog -*-
// Filename        : RV_Interface.sv
// Description     : Ready-Valid-Bus register.
// Author          : Stephan Proß
// Created On      : Wed Dec 28 13:04:23 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 28 13:04:23 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


module RV_INTERFACE
  #(
    parameter integer unsigned WRITE_WIDTH = 8,
    parameter integer unsigned READ_WIDTH = 8
    ) (
       input logic                    CLK_I,
       input logic                    RST_NI,

       // Ready-Valid signals
       input logic                    READ_ENABLE_I,
       input logic                    READ_READY_I,
       output logic                   READ_VALID_O,
       output logic [READ_WIDTH-1:0]  READ_DATA_O,

       input logic                    WRITE_ENABLE_I,
       output logic                   WRITE_READY_O,
       input logic                    WRITE_VALID_I,
       input logic [WRITE_WIDTH-1:0]  WRITE_DATA_I,

       // Other signals
       output logic                   UPDATE_O,
       output logic [WRITE_WIDTH-1:0] DATA_O,

       input logic                    CHANGE_I,
       input logic [READ_WIDTH-1:0]   DATA_I
       );

   // -----------------------------------------------------------------------
   // --- Read Process  -----
   // -----------------------------------------------------------------------

   logic                              pending_read;

   assign READ_DATA_O = DATA_I;
   assign READ_VALID_O = pending_read;

   always_ff @(posedge CLK_I) begin : READ_PROC
      if(!RST_NI) begin
         pending_read <= 0;
      end
      else begin
         if (READ_ENABLE_I && READ_READY_I || CHANGE_I) begin
            pending_read <= 1;
         end;
         if (pending_read && READ_READY_I) begin
            pending_read <= 0;
         end
      end
   end

   // -----------------------------------------------------------------------
   // --- Write State Machine -----
   // -----------------------------------------------------------------------

   typedef enum {st_write_idle, st_write_finish} write_state_t;
   write_state_t wstate, wstate_next;

   assign DATA_O = WRITE_DATA_I;
   always_ff @(posedge CLK_I) begin : WRITE_FSM_CORE
      if(!RST_NI) begin
         wstate <= st_write_idle;
      end
      else begin
         wstate <= wstate_next;
      end
   end

   always_comb begin : WRITE_FSM
      wstate_next = wstate;
      if(!RST_NI) begin
         wstate_next = st_write_idle;
         WRITE_READY_O = 0;
         UPDATE_O = 0;
      end
      else begin
         case (wstate)
           st_write_idle : begin
              WRITE_READY_O = WRITE_ENABLE_I;
              UPDATE_O = 0;

              if ( WRITE_VALID_I && WRITE_ENABLE_I ) begin
                 wstate_next = st_write_finish;
              end
           end
           st_write_finish: begin
              UPDATE_O = 1;
              WRITE_READY_O = 0;

              wstate_next = st_write_idle;
           end
         endcase // case (wstate)
      end
   end
endmodule // RV_INTERFACE
