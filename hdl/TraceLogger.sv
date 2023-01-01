//                              -*- Mode: SystemVerilog -*-
// Filename        : TraceLogger.sv
// Description     : Module combining Tracer and Logger into one functional unit.
// Author          : Stephan Proß
// Created On      : Thu Dec  1 13:37:07 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 13:37:07 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;


module TraceLogger (
                    // --- Interface Ports ---
                    input logic                        CLK_I,
                    input logic                        RST_NI,

                    input logic [$bits(config_t)-1:0]  CONF_I,
                    input logic                        CONF_UPDATE_I,
                    output logic [$bits(status_t)-1:0] STAT_O,

                    // Read & Write strobe. Indicates that a write operation
                    // can be performed in the current cycle.
                    input logic                        RW_TURN_I,
                    // Signal write intend to memory.
                    output logic                       WRITE_O,
                    // Signals to indicate whether reading/writing is possible.
                    input logic                        WRITE_ALLOW_I,
                    input logic                        READ_ALLOW_I,

                    // Read&Write Pointers with associated data ports.
                    output logic [TRB_ADDR_WIDTH-1:0]  READ_PTR_O,
                    input logic [TRB_WIDTH-1:0]        DMEM_I,

                    output logic [TRB_ADDR_WIDTH-1:0]  WRITE_PTR_O,
                    output logic [TRB_WIDTH-1:0]       DMEM_O,

                    // ---- FPGA signals ----
                    // Signals of the FPGA facing side.
                    input logic                        FPGA_CLK_I,
                    // Trigger signal.
                    input logic                        FPGA_TRIG_I,
                    // Trace input
                    input logic [TRB_MAX_TRACES-1:0]   FPGA_TRACE_I,
                    // Write valid. Only relevant during streaming mode.
                    output logic                       FPGA_WRITE_VALID_O,

                    // Read signal for streaming mode, irrelevant during trace mode.
                    input logic                        FPGA_READ_I,
                    // Stream output.
                    output logic [TRB_MAX_TRACES-1:0]  FPGA_STREAM_O,
                    // Set to high after trigger event with delay. Usable for daisy-chaining.
                    // Indicates whether data is valid in streaming mode.
                    output logic                       FPGA_TRIG_O

                    );


   // Other signals.
   logic                                               log_store_perm;
   logic                                               trc_store_perm;
   always_ff @(posedge FPGA_CLK_I) begin
      trc_store_perm <= log_store_perm;
   end

   logic                                               log_load_request;
   logic                                               trc_load_request;
   always_ff @(posedge CLK_I) begin
      log_load_request <= trc_load_request;
   end


   //  --- Control Signal Group ---
   //  -- Data signals
   // Logger
   logic                                               log_mode;
   bit [TRB_NTRACE_BITS-1:0]                           log_num_traces;
   // Tracer
   logic                                               trc_mode;
   bit [TRB_NTRACE_BITS-1:0]                           trc_num_traces;
   //  -- Synchronizing signal
   logic                                               conf_update;
   // -----------------------------
   always_ff @(posedge FPGA_CLK_I) begin : REGISTER_CONTROL
      if(conf_update) begin
         trc_mode <= log_mode;
         trc_num_traces <= log_num_traces;
      end
   end


   //  --- Trace & Status Signal Group ---
   //  -- Data signals
   // Logger
   logic [$clog(TRB_WIDTH)-1:0]                        log_event_pos;
   logic                                               log_trg_event;
   logic [TRB_WIDTH-1:0]                               log_data_in;
   // Tracer
   logic [$clog(TRB_WIDTH)-1:0]                        trc_event_pos;
   logic                                               trc_trg_event;
   logic [TRB_WIDTH-1:0]                               trc_data_out;
   //  -- Synchronizing signal
   logic                                               store;
   // -----------------------------
   always_ff @(posedge CLK_I) begin : REGISTER_TRACE_STATUS
      if(store) begin
         log_event_pos <= trc_event_pos;
         log_trg_event <= trc_trg_event;
         log_data_in <= trc_data_out;
      end
   end

   // --- Stream Signal Group ---
   //  -- Data signals
   // Logger
   logic                                               log_trg_delayed;
   logic [TRB_WIDTH-1:0]                               log_data_out;
   // Tracer
   logic                                               trc_trg_delayed;
   logic [TRB_WIDTH-1:0]                               trc_data_in;
   //  -- Synchronizing signal
   logic                                               load_grant;
   // -----------------------------
   always_ff @(posedge FPGA_CLK_I) begin : REGISTER_STREAM
      if(load_grant) begin
         trc_trg_delayed <= log_trg_delayed;
         trc_data_in <= log_data_out;
      end
   end


   Logger log_1
     (
      .CLK_I           (CLK_I),
      .RST_NI          (RST_NI),
      .CONF_I          (CONF_I),
      .STAT_O          (STAT_O),
      .RW_TURN_I       (RW_TURN_I),
      .WRITE_O         (WRITE_O),
      .WRITE_ALLOW_I   (WRITE_ALLOW_I),
      .READ_ALLOW_I    (READ_ALLOW_I),
      .READ_PTR_O      (READ_PTR_O),
      .DMEM_I          (DMEM_I),
      .WRITE_PTR_O     (WRITE_PTR_O),
      .DMEM_O          (DMEM_O),

      .MODE_O          (log_mode),
      .NTRACE_O        (log_num_traces),
      .EVENT_POS_I     (log_event_pos),
      .TRG_EVENT_I     (log_trg_event),
      .TRG_DELAYED_O   (log_trg_delayed),
      .DATA_O          (log_data_out),
      .LOAD_REQUEST_I  (load_request),
      .LOAD_GRANT_O    (load_grant),
      .DATA_I          (log_data_in),
      .STORE_I         (store),
      .STORE_PERM_O    (store_perm)
      );

   Tracer trc_1
     (
      .RST_I                (CONF_UPDATE_I),
      .MODE_I               (trc_mode),
      .NTRACE_I             (trc_num_traces),
      .EVENT_POS_O          (trc_event_pos),
      .TRG_EVENT_O          (trc_trg_event),
      .TRG_DELAYED_I        (trc_trg_delayed),

      .DATA_I               (trc_data_in),
      .LOAD_REQUEST_O       (load_request),
      .LOAD_GRANT_I         (load_grant),

      .DATA_O               (trc_data_out),
      .STORE_O              (store),
      .STORE_PERM_I         (store_perm),

      .FPGA_CLK_I           (FPGA_CLK_I),
      .FPGA_TRIG_I          (FPGA_TRIG_I),
      .FPGA_TRACE_I         (FPGA_TRACE_I),
      .FPGA_WRITE_VALID_O   (FPGA_WRITE_VALID_O),
      .FPGA_READ_I          (FPGA_READ_I),
      .FPGA_STREAM_O        (FPGA_STREAM_O),
      .FPGA_TRIG_O          (FPGA_TRIG_O)
      );

endmodule // TraceLogger
