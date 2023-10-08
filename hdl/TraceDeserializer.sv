//                             -*- Mode: Verilog -*-
// Filename        : TraceDeserializer.sv
// Description     : Trace
// Author          : Stephan Proß
// Created On      : Thu Nov 24 13:09:49 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 24 13:09:49 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!
`include "STB_PKG.svh"

module TraceDeserializer (

    input logic CLK_I,
    input logic RST_I,

    // Exponent of the number of traces captured in parallel.
    // Actual number is 2 ** EXP_TRACE_I
    input bit [TRB_NTRACE_BITS-1:0] EXP_TRACES_I,

    // ---- Memory IO -----
    // Trace register to be stored in memory.
    output logic [TRB_WIDTH-1:0] DATA_O,
    // Trigger storing of data and status.
    output logic                 STORE_O,
    // Indicator for store permission.
    input  logic                 STORE_PERM_I,

    // Valid/Trigger signal. Exact function depends on CSR values.
    input  logic                      TRACE_VALID_I,
    // Write ready for writing of the trace signal. Can be used as
    // the delayed trigger signal.
    output logic                      TRACE_READY_O,
    // Trace input
    input  logic [TRB_MAX_TRACES-1:0] TRACE_I
);


  logic [          TRB_WIDTH -1 : 0] trace_reg;
  bit   [     $clog2(TRB_WIDTH)-1:0] trace_pos;
  bit   [$clog2(TRB_MAX_TRACES)-1:0] num_traces;
  always_comb begin
    if (2 ** EXP_TRACES_I < TRB_MAX_TRACES) begin
      num_traces = 2 ** EXP_TRACES_I;
    end else begin
      num_traces = TRB_MAX_TRACES;
    end
  end

  logic store_request;

  always_ff @(posedge CLK_I) begin : TRACE_CAPTURE_PROCESS
    if (RST_I) begin
      trace_reg <= '0;
      trace_pos <= 0;
      store_request <= 0;

      TRACE_READY_O <= 0;
      DATA_O <= '0;
      STORE_O <= 0;
    end else begin

      TRACE_READY_O <= 1;
      STORE_O <= 0;

      // Deserialize dependent on trace_pos
      for (int i = 0; i < num_traces; i++) begin
        if (trace_pos + i < TRB_WIDTH) begin
          trace_reg[trace_pos+i] <= TRACE_I[i];
        end
      end

      if (trace_pos + num_traces < TRB_WIDTH) begin
        // trace_pos increment only if incoming data is valid.
        if (TRACE_VALID_I == 1) begin
          trace_pos <= (trace_pos + num_traces);
        end
      end else begin
        // Register trace_data, set store request.
        if (store_request == 0) begin
          // trace_pos is only reset if no outstanding request
          // is present.
          store_request <= 1;
          DATA_O <= trace_reg;
          trace_pos <= 0;
        end else begin
          TRACE_READY_O <= 0;
        end
      end  // else: !if(trace_pos + num_traces < TRB_WIDTH)

      // Deassert store_request only if store permission is granted and oulse STORE_O
      // once.
      if (trace_pos + num_traces >= TRB_WIDTH || store_request == 1) begin
        if (STORE_PERM_I == 1) begin
          STORE_O <= 1;
          store_request <= 0;
        end
      end

    end
  end

endmodule
