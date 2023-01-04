//                              -*- Mode: SystemVerilog -*-
// Filename        : DTB_PKG.sv
// Description     : Package containing definitions and constants for the Data Trace Buffer.
// Author          : Stephan Proß
// Created On      : Thu Nov 24 13:12:41 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 24 13:12:41 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!
package DTB_PKG;
   // Constants defining BRAM write width and depth.
   localparam integer unsigned  TRB_WIDTH = 32;

   localparam integer unsigned  TRB_ADDR_WIDTH = 8;
   localparam integer unsigned  TRB_DEPTH = 32;

   localparam integer unsigned  TRB_MAX_TRACES = 16;
   localparam integer unsigned  TRB_NTRACE_BITS = $clog2($clog2(TRB_MAX_TRACES));
   typedef enum logic[1:0]
                {
                 trace_mode     = 2'b00,
                 rw_stream_mode = 2'b01,
                 r_stream_mode  = 2'b10,
                 w_stream_mode  = 2'b11
                 } trg_mode_t;

   localparam integer unsigned  TRB_DELAY_BITS = 8 - $bits(trg_mode_t) - TRB_NTRACE_BITS;

   typedef struct               packed {
      trg_mode_t                  trg_mode;
      logic [TRB_NTRACE_BITS-1:0] trg_num_traces;
      logic [TRB_DELAY_BITS-1:0]  trg_delay;
   } control_t;

   localparam                     control_t CONTROL_DEFAULT = '{
                                                              trg_mode:trace_mode,
                                                              trg_num_traces:0,
                                                              trg_delay:'1
                                                              };


   typedef struct                 packed {
      logic                       trg_event;
      bit [ $clog2(TRB_WIDTH)-1:0 ] event_pos;
      logic [7 - $clog2(TRB_WIDTH) - 1:0] zero;
      // bit [ $clog2(TRB_DEPTH)-1:0 ] event_addr;
   } status_t;

   localparam                       status_t STATUS_DEFAULT = '{trg_event:0,event_pos:'0,zero:'0};

endpackage : DTB_PKG // DTB_PKG
