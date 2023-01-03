//                              -*- Mode: Verilog -*-
// Filename        : RV_Interface.sv
// Description     : Ready-Valid-Bus register.
// Author          : Stephan Proß
// Created On      : Wed Dec 28 13:04:23 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 28 13:04:23 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


module RV_Interface
  #(
    parameter integer unsigned WRITE_WIDTH = 8,
    parameter integer unsigned READ_WIDTH = 8
    ) (
       input logic                    CLK_I,
       input logic                    RST_NI,

       // --- System Signals ---
       input logic                    READ_READY_I,
       output logic                   READ_VALID_O,
       output logic [READ_WIDTH-1:0]  READ_DATA_O,

       output logic                   WRITE_READY_O,
       input logic                    WRITE_VALID_I,
       input logic [WRITE_WIDTH-1:0]  WRITE_DATA_I,

       // --- Device signals ---
       input logic                    READ_ENABLE_I,
       input logic                    WRITE_ENABLE_I,

       // Indicates whether data_o has been updated.
       output logic                   UPDATE_O,
       output logic [WRITE_WIDTH-1:0] DATA_O,

       // Indicates whether data_i has changed.
       input logic                    CHANGE_I,
       input logic [READ_WIDTH-1:0]   DATA_I,
       // Indicates a successful read operation.
       output logic                   READ_O
       );

   // -----------------------------------------------------------------------
   // --- Read Process  -----
   // -----------------------------------------------------------------------

   logic                              pending_read;

   assign READ_DATA_O = DATA_I;
   assign READ_VALID_O = pending_read && READ_ENABLE_I;
   assign READ_O = ~pending_read & READ_READY_I;

   always_ff @(posedge CLK_I) begin : READ_PROC
      if(!RST_NI) begin
         pending_read <= 0;
      end
      else begin
         if (CHANGE_I || READ_ENABLE_I && READ_READY_I) begin
            pending_read <= 1;
         end
         if (pending_read && READ_READY_I) begin
            pending_read <= 0;
         end
      end
   end

   // -----------------------------------------------------------------------
   // --- Write Process -----
   // -----------------------------------------------------------------------

   logic pending_write;
   assign DATA_O = WRITE_DATA_I;
   assign WRITE_READY_O = pending_write;

   always_ff @(posedge CLK_I) begin : WRITE_PROC
      if(!RST_NI) begin
         pending_write <= 0;
         UPDATE_O <= 0;
      end
      else begin
         UPDATE_O <= 0;
         if (WRITE_VALID_I && WRITE_ENABLE_I) begin
            pending_write <= 1;
         end
         if (pending_write) begin
            UPDATE_O <= 1;
            pending_write <= 0;
         end
      end
   end

endmodule // RV_Interface
