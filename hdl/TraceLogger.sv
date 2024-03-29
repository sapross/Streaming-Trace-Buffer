//                              -*- Mode: SystemVerilog -*-
// Filename        : CDC_TraceLogger.sv
// Description     : Module combining Tracer and Logger into one functional unit.
//                   Signals between components are synchronized w. CDC techniques.
// Author          : Stephan Proß
// Created On      : Thu Dec  1 13:37:07 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 13:37:07 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

`include "../lib/STB_PKG.svh"
// `define CDC

module TraceLogger (
    // --- Interface Ports ---
    input logic CLK_I,
    input logic RST_NI,

    input  logic [TRB_CONTROL_BITS-1:0] CONTROL_I,
    input  logic                        CONTROL_UPDATE_I,
    output logic [ TRB_STATUS_BITS-1:0] STATUS_O,

    // Read & Write strobe. Indicates that a write operation
    // can be performed in the current cycle.
    input  logic RW_TURN_I,
    // Signal write intend to memory.
    output logic WRITE_O,
    // Signals to indicate whether reading/writing is possible.
    input  logic WRITE_ALLOW_I,
    input  logic READ_ALLOW_I,

    // Read&Write Pointers with associated data ports.
    output logic [TRB_ADDR_WIDTH-1:0] READ_PTR_O,
    input  logic [     TRB_WIDTH-1:0] DMEM_I,

    output logic [TRB_ADDR_WIDTH-1:0] WRITE_PTR_O,
    output logic [     TRB_WIDTH-1:0] DMEM_O,

    // ---- FPGA signals ----
    input  logic                      FPGA_CLK_I,
    // Valid/Trigger signal. Exact function depends on CSR values.
    input  logic                      FPGA_TRACE_VALID_I,
    // Write ready for writing of the trace signal. Can be used as
    // the delayed trigger signal.
    output logic                      FPGA_TRACE_READY_O,
    // Trace input
    input  logic [TRB_MAX_TRACES-1:0] FPGA_TRACE_I,

    // Ready signal for data stream to FPGA.
    input  logic                      FPGA_STREAM_READY_I,
    // Valid signal from FPGA.
    output logic                      FPGA_STREAM_VALID_O,
    // Stream output.
    output logic [TRB_MAX_TRACES-1:0] FPGA_STREAM_O

);

  // -----------------------------------------------------------------
  // ---- Store Permission Synchronization ----
  // -----------------------------------------------------------------
  logic log_store_perm;
  logic trc_store_perm;
`ifdef CDC
  CDC_OL_SYNC store_sync (
      .CLK_A_I(CLK_I),
      .A_I    (log_store_perm),
      .CLK_B_I(FPGA_CLK_I),
      .B_O    (trc_store_perm)
  );
`else
  always_ff @(posedge FPGA_CLK_I) begin
    trc_store_perm <= log_store_perm;
  end
`endif

  // -----------------------------------------------------------------
  // ---- Load Request Synchronization ----
  // -----------------------------------------------------------------
  logic log_load_request;
  logic trc_load_request;
  // CDC not neccessary at this point since load_request is held for more
  // than one cycle in FPGA domain with slower or equal frequency.
  always_ff @(posedge CLK_I) begin
    log_load_request <= trc_load_request;
  end

  // -----------------------------------------------------------------
  //  --- Control Signal Group ---
  // -----------------------------------------------------------------
  //  -- Data signals
  // Logger
  logic [  TRB_MODE_BITS-1:0] log_mode;
  bit   [TRB_NTRACE_BITS-1:0] log_num_traces;
  // Tracer
  logic [  TRB_MODE_BITS-1:0] trc_mode;
  bit   [TRB_NTRACE_BITS-1:0] trc_num_traces;
  //  -- Synchronizing signal
  logic                       log_control_update;
  assign log_control_update = CONTROL_UPDATE_I;

  logic trc_control_update;

`ifdef CDC
  CDC_MCP_TOGGLE #(
      .WIDTH(TRB_MODE_BITS + TRB_NTRACE_BITS)
  ) cdc_control (
      .RST_A_NI(RST_NI),
      .CLK_A_I (CLK_I),
      .DATA_A_I({log_mode, log_num_traces}),
      .SYNC_A_I(log_control_update),

      .CLK_B_I (FPGA_CLK_I),
      .DATA_B_O({trc_mode, trc_num_traces}),
      .SYNC_B_O(trc_control_update)
  );
`else
  always_ff @(posedge FPGA_CLK_I) begin : REGISTER_CONTROL
    trc_control_update <= log_control_update;
    if (trc_control_update) begin
      trc_mode <= log_mode;
      trc_num_traces <= log_num_traces;
    end
  end
`endif

  // -----------------------------------------------------------------
  //  --- Trace & Status Signal Group ---
  // -----------------------------------------------------------------
  //  -- Data signals
  // Tracer
  logic                         trc_trg_event;
  logic [$clog2(TRB_WIDTH)-1:0] trc_event_pos;
  logic [        TRB_WIDTH-1:0] trc_data_out;
  // Logger
  logic                         log_trg_event;
  logic [$clog2(TRB_WIDTH)-1:0] log_event_pos;
  logic [        TRB_WIDTH-1:0] log_data_in;
  //  -- Synchronizing signal
  logic                         trc_store;
  logic                         log_store;
`ifdef CDC
  CDC_MCP_TOGGLE #(
      .WIDTH(1 + $clog2(TRB_WIDTH) + TRB_WIDTH)
  ) cdc_trace_status (
      .RST_A_NI(!trc_control_update),
      .CLK_A_I (FPGA_CLK_I),
      .DATA_A_I({trc_trg_event, trc_event_pos, trc_data_out}),
      .SYNC_A_I(trc_store),

      .CLK_B_I (CLK_I),
      .DATA_B_O({log_trg_event, log_event_pos, log_data_in}),
      .SYNC_B_O(log_store)
  );
`else
  always_ff @(posedge CLK_I) begin : REGISTER_TRACE_STATUS
    log_store <= trc_store;
    if (log_store) begin
      log_event_pos <= trc_event_pos;
      log_trg_event <= trc_trg_event;
      log_data_in   <= trc_data_out;
    end
  end
`endif


  // -----------------------------------------------------------------
  // --- Stream Signal Group ---
  // -----------------------------------------------------------------
  //  -- Data signals
  // Logger
  logic                 log_trg_delayed;
  logic [TRB_WIDTH-1:0] log_data_out;
  // Tracer
  logic                 trc_trg_delayed;
  logic [TRB_WIDTH-1:0] trc_data_in;
  //  -- Synchronizing signal
  logic                 log_load_grant;
  logic                 trc_load_grant;
`ifdef CDC
  CDC_MCP_TOGGLE #(
      .WIDTH(1 + TRB_WIDTH)
  ) cdc_stream (
      .RST_A_NI(RST_NI),
      .CLK_A_I (CLK_I),
      .DATA_A_I({log_trg_delayed, log_data_out}),
      .SYNC_A_I(log_load_grant),

      .CLK_B_I (FPGA_CLK_I),
      .DATA_B_O({trc_trg_delayed, trc_data_in}),
      .SYNC_B_O(trc_load_grant)
  );
`else
  always_ff @(posedge FPGA_CLK_I) begin : REGISTER_STREAM
    trc_load_grant <= log_load_grant;
    if (trc_load_grant) begin
      trc_trg_delayed <= log_trg_delayed;
      trc_data_in <= log_data_out;
    end
  end
`endif


  Logger log_1 (
      .CLK_I        (CLK_I),
      .RST_NI       (!CONTROL_UPDATE_I),
      .CONTROL_I    (CONTROL_I),
      .STATUS_O     (STATUS_O),
      .RW_TURN_I    (RW_TURN_I),
      .WRITE_O      (WRITE_O),
      .WRITE_ALLOW_I(WRITE_ALLOW_I),
      .READ_ALLOW_I (READ_ALLOW_I),
      .READ_PTR_O   (READ_PTR_O),
      .DMEM_I       (DMEM_I),
      .WRITE_PTR_O  (WRITE_PTR_O),
      .DMEM_O       (DMEM_O),

      .MODE_O        (log_mode),
      .NTRACE_O      (log_num_traces),
      .EVENT_POS_I   (log_event_pos),
      .TRG_EVENT_I   (log_trg_event),
      .TRG_DELAYED_O (log_trg_delayed),
      .DATA_O        (log_data_out),
      .LOAD_REQUEST_I(log_load_request),
      .LOAD_GRANT_O  (log_load_grant),
      .DATA_I        (log_data_in),
      .STORE_I       (log_store),
      .STORE_PERM_O  (log_store_perm)
  );

  Tracer trc_1 (
      .RST_I        (CONTROL_UPDATE_I),
      .MODE_I       (trc_mode),
      .NTRACE_I     (trc_num_traces),
      .EVENT_POS_O  (trc_event_pos),
      .TRG_EVENT_O  (trc_trg_event),
      .TRG_DELAYED_I(trc_trg_delayed),

      .DATA_I        (trc_data_in),
      .LOAD_REQUEST_O(trc_load_request),
      .LOAD_GRANT_I  (trc_load_grant),

      .DATA_O      (trc_data_out),
      .STORE_O     (trc_store),
      .STORE_PERM_I(trc_store_perm),

      .FPGA_CLK_I         (FPGA_CLK_I),
      .FPGA_TRACE_VALID_I (FPGA_TRACE_VALID_I),
      .FPGA_TRACE_READY_O (FPGA_TRACE_READY_O),
      .FPGA_TRACE_I       (FPGA_TRACE_I),
      .FPGA_STREAM_READY_I(FPGA_STREAM_READY_I),
      .FPGA_STREAM_VALID_O(FPGA_STREAM_VALID_O),
      .FPGA_STREAM_O      (FPGA_STREAM_O)
  );

endmodule  // TraceLogger
