//-----------------------------------------------------------------------------
// Title         : TB_TraceDeserializer
// Project       : StreamingTraceBuffer
//-----------------------------------------------------------------------------
// File          : TB_TraceDeserializer.sv
// Author        : Stephan Proß  <spross@S-PC>
// Created       : 04.07.2023
// Last modified : 04.07.2023
//-----------------------------------------------------------------------------
// Description : TestBench for the TraceDeserializer component.
//-----------------------------------------------------------------------------
// Modification history :
// 04.07.2023 : created
//-----------------------------------------------------------------------------
`include "STB_PKG.svh"

interface TraceDeserializer_Assertion (  /*AUTOARG*/
    input logic CLK_I,
    input logic RST_I,
    input bit [TRB_NTRACE_BITS-1:0] EXP_TRACES_I,
    input logic TRACE_READY_O,
    input logic TRACE_VALID_I,
    input logic [TRB_MAX_TRACES-1:0] TRACE_I,
    input logic STORE_PERM_I,
    input logic STORE_O,
    input logic [TRB_WIDTH-1:0] DATA_O
);

  property no_store_without_permission;
    @(posedge CLK_I) disable iff (RST_I) !STORE_PERM_I -> !STORE_O;
  endproperty  // no_store_without_permission
  assert property (no_store_without_permission)
  else $error("%m Store asserted without permission.");

endinterface  // TraceDeserializer_Assertion



module TB_TraceDeserializer (  /*AUTOARG*/);
  /*AUTOWIRE*/
  // Beginning of automatic wires (for undeclared instantiated-module outputs)
  logic [      TRB_WIDTH-1:0] DATA_O;  // From DUT of TraceDeserializer.v
  logic                       STORE_O;  // From DUT of TraceDeserializer.v
  logic                       TRACE_READY_O;  // From DUT of TraceDeserializer.v
  // End of automatics
  /*AUTOREGINPUT*/
  // Beginning of automatic reg inputs (for undeclared instantiated-module inputs)
  logic                       CLK_I;  // To DUT of TraceDeserializer.v
  bit   [TRB_NTRACE_BITS-1:0] EXP_TRACES_I;  // To DUT of TraceDeserializer.v
  logic                       RST_I;  // To DUT of TraceDeserializer.v
  logic                       STORE_PERM_I;  // To DUT of TraceDeserializer.v
  logic [ TRB_MAX_TRACES-1:0] TRACE_I;  // To DUT of TraceDeserializer.v
  logic                       TRACE_VALID_I;  // To DUT of TraceDeserializer.v
  // End of automatics
  TraceDeserializer DUT (  /*AUTOINST*/
      // Outputs
      .DATA_O       (DATA_O[TRB_WIDTH-1:0]),
      .STORE_O      (STORE_O),
      .TRACE_READY_O(TRACE_READY_O),
      // Inputs
      .CLK_I        (CLK_I),
      .RST_I        (RST_I),
      .EXP_TRACES_I (EXP_TRACES_I[TRB_NTRACE_BITS-1:0]),
      .STORE_PERM_I (STORE_PERM_I),
      .TRACE_VALID_I(TRACE_VALID_I),
      .TRACE_I      (TRACE_I[TRB_MAX_TRACES-1:0])
  );

  function static void reset(input int unsigned exp_traces);
    RST_I = 1;

    EXP_TRACES_I = exp_traces;

    STORE_PERM_I = 0;
    TRACE_VALID_I = 0;
    TRACE_I = '0;
  endfunction  // reset

  const integer unsigned CLK_PERIOD = 5;
  always begin
    #CLK_PERIOD CLK_I = 0;
    #CLK_PERIOD CLK_I = 1;
  end

  // Scoreboards
  logic [TRB_WIDTH-1:0] sb_monitor[$];
  logic [TRB_WIDTH-1:0] sb_driver [$];

  always_ff @(posedge CLK_I) begin : MONITOR_PROCESS
    if (!RST_I) begin
      if (STORE_PERM_I == 1 && STORE_O == 1) begin
        sb_monitor.insert(0, DATA_O);
        assert (sb_monitor[0] == sb_driver[0])
        else $error("%m Deserialization failed. Output does not equate input.");
      end
    end
  end

  task automatic test_trace_serialization_over_exp_traces;
    localparam int NumRep = 2;
    // Serial trace data to be deserialized.
    logic [TRB_WIDTH-1:0] serial_data[NumRep];

    $display("[ %0t ] Test: Trace deserialization with varying number of traces.", $time);

    for (int partrc = 0; partrc < $clog2(TRB_MAX_TRACES) + 1; partrc++) begin
      $display("[ %0t ] Test with %0d parallel traces.", $time, 2 ** partrc);
      reset(partrc);
      randomize(serial_data);
      STORE_PERM_I <= 1;
      #CLK_PERIOD;
      RST_I <= 0;
      for (int i = 0; i < NumRep; i++) begin
        for (int j = 0; j < TRB_WIDTH; j = j + 2 ** EXP_TRACES_I) begin
          TRACE_VALID_I = 1;
          for (int k = 0; k < 2 ** EXP_TRACES_I; k++) begin
            TRACE_I <= serial_data[i][j+k];
          end
          #CLK_PERIOD;
        end
        sb_driver.insert(0, serial_data[i]);
      end
    end
  endtask  // test_trace_serialization_over_exp_traces


  initial begin
    CLK_I = 1;
    reset(0);
    #CLK_PERIOD;
    test_trace_serialization_over_exp_traces();
    $display("Tests finished.");
    $dumpfile("TB_TraceDeserializer.vcd");
    $dumpvars;
    $finish();
  end

endmodule  // TB_TraceDeserializer
// Local Variables:
// verilog-library-flags:("-F ../input.vc")
// End:
