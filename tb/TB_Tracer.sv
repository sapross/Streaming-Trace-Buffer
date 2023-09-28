//                              -*- Mode: Verilog -*-
// Filename        : TB_Tracer.sv
// Description     : Testbench for Tracer module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;

module TB_TRACER (  /*AUTOARG*/);

  logic                              clk;
  logic                              reset;

  trg_mode_t                         mode;
  logic      [  TRB_NTRACE_BITS-1:0] num_traces;
  logic      [$clog2(TRB_WIDTH)-1:0] event_pos;
  logic                              trg_event;
  logic                              trg_delayed;

  logic      [        TRB_WIDTH-1:0] data_in;
  logic                              load_request;
  logic                              load_grant;

  logic      [        TRB_WIDTH-1:0] data_out;
  logic                              store;
  logic                              store_perm;

  logic                              trace_valid;
  logic      [   TRB_MAX_TRACES-1:0] trace;
  logic                              trace_ready;

  logic                              stream_ready;
  logic      [   TRB_MAX_TRACES-1:0] stream;
  logic                              stream_valid;

  always begin
    #5 clk = 0;
    #5 clk = 1;
  end
  initial begin
    clk = 1;
    reset = 1;
    mode = trace_mode;
    num_traces = 0;
    trg_delayed = 0;
    data_in = 0;
    store_perm = 0;
    load_grant = 0;
    trace_valid = 0;
    trace = '0;
    stream_ready = 0;
    #20 reset = 0;
  end

  Tracer DUT (
      .RST_I              (reset),
      .MODE_I             (mode),
      .NTRACE_I           (num_traces),
      .EVENT_POS_O        (event_pos),
      .TRG_EVENT_O        (trg_event),
      .TRG_DELAYED_I      (trg_delayed),
      .DATA_I             (data_in),
      .LOAD_REQUEST_O     (load_request),
      .LOAD_GRANT_I       (load_grant),
      .DATA_O             (data_out),
      .STORE_O            (store),
      .STORE_PERM_I       (store_perm),
      .FPGA_CLK_I         (clk),
      .FPGA_TRACE_VALID_I (trace_valid),
      .FPGA_TRACE_READY_O (trace_ready),
      .FPGA_TRACE_I       (trace),
      .FPGA_STREAM_READY_I(stream_ready),
      .FPGA_STREAM_VALID_O(stream_valid),
      .FPGA_STREAM_O      (stream)
  );

  // Set control signals to default values and set reset signal.
  task reset_to_default;
    reset = 1;
    mode = trace_mode;
    num_traces = 0;
    trg_delayed = 0;
    data_in = 0;
    store_perm = 1;
    load_grant = 0;
    trace_valid = 0;
    trace = '0;
    stream_ready = 0;
  endtask  // reset_to_default

  // Test deserialization of traces to memory words. Also set the trigger randomly
  // during test run and assert validity of event position.
  task test_trace_to_mem;
    logic [        TRB_WIDTH-1:0] data;
    bit   [$clog2(TRB_WIDTH)-1:0] trig_pos;
    logic                         word_completed;

    $display("[ %0t ] Test: Trace to Memory w. variable ntrace & trigger.", $time);
    for (int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
      for (int perm = 0; perm < 2; perm++) begin
        reset_to_default();
        randomize(data);
        randomize(trig_pos);
        mode = trace_mode;
        num_traces = ntrace;
        store_perm = perm;
        @(negedge clk);
        for (int word_count = 0; word_count < 2; word_count++) begin
          word_completed = 0;
          for (int i = 0; i < TRB_WIDTH; i = i + 2 ** ntrace) begin
            @(negedge clk);
            reset = 0;
            // Set trigger at random trigger position.
            if (i < trig_pos) begin
              trace_valid = 0;
            end else if (i >= trig_pos && i < trig_pos + 2 ** ntrace) begin
              trace_valid = 1;
            end else begin
              // Trigger has random value after that.
              trace_valid = $urandom_range(0, 1);
            end

            // Load slice of data reg into trace input.
            for (int j = 0; j < TRB_MAX_TRACES; j++) begin
              if (i + j < TRB_WIDTH) begin
                trace[j] = data[i+j];
              end else begin
                trace[j] = 0;
              end
            end
            @(posedge clk);
            if (i > 0 && word_count == 0) begin
              if (i - 2 ** (ntrace) < trig_pos) begin
                assert (trg_event == 0)
                else $error("[%m] Unexpected trigger event at i=%0d, trig_pos=%0d.", i, trig_pos);
              end else begin
                assert (trg_event == 1)
                else $error("[%m] Trigger event expected at i=%0d, trig_pos=%0d,", i, trig_pos);
              end
            end
          end  // for (int i = 0; i < TRB_WIDTH; i = i + 2 ** ntrace)
          #1
          if (perm) begin
            assert (store == 1)
            else $error("%m Store signal expected!");
            if (store == 1) begin
              assert (data_out == data)
              else
                $error(
                    "%m Deserialization failed for ntrace = %0d.\n expected data=%8h, got data_out=%8h",
                    ntrace,
                    data,
                    data_out
                );
            end
          end else begin
            assert (store == 0)
            else $error("%m Store is not expected without store permission!");
          end  // else: !if(perm)
        end  // for (int word_count = 0; word_count < 2; word_count++)
      end  // for (int perm = 0; perm < 2; perm++)
    end  // for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++)

  endtask  // test_trace_to_mem

  // Test deserialization of traces to memory words. Also set the trigger randomly
  // during test run and assert validity of event position.
  task test_stream_to_mem;
    logic [        TRB_WIDTH-1:0] data;
    bit   [$clog2(TRB_WIDTH)-1:0] trig_pos;
    int                           stream_progress = 0;
    int                           i = 0;

    $display("[ %0t ] Test: Stream to Memory w. variable ntrace & trigger.", $time);
    for (int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
      for (int perm = 0; perm < 2; perm++) begin
        @(negedge clk);
        reset_to_default();
        randomize(trig_pos);
        mode = w_stream_mode;
        num_traces = ntrace;
        store_perm = perm;
        stream_progress = 0;
        @(negedge clk);



        while (stream_progress < 2) begin
          logic word_completed;
          word_completed = 0;

          reset = 0;
          @(negedge clk);
          if (i == 0) begin
            randomize(data);
            $display("[ %0t ] Streaming data = %8h", $time, data);
          end

          // Trigger is random in all other modes.
          trace_valid = $urandom_range(0, 1);

          // Load slice of data reg into trace input.
          // $display("[ %0t ] Slice data[%0d:%0d]", $time, i, i + 2 ** ntrace);
          for (int j = 0; j < TRB_MAX_TRACES; j++) begin
            if (j < 2 ** ntrace) begin
              trace[j] = data[i+j];
            end else begin
              trace[j] = 0;
            end
          end
          if (trace_valid == 1) begin
            i += 2 ** ntrace;
            if (i >= TRB_WIDTH) begin
              i = 0;
              word_completed = 1;
              stream_progress++;
            end
          end
          @(posedge clk);

          #1
          if (perm == 1 && trace_valid && word_completed) begin
            assert (store == 1)
            else $error("%m Store signal expected! i = %0d.", i);
            if (store == 1) begin
              assert (data_out == data)
              else
                $error(
                    "%m Deserialization failed for ntrace = %0d.\n expected data=%8h, got data_out=%8h",
                    ntrace,
                    data,
                    data_out
                );
            end
          end else begin
            assert (store == 0)
            else $error("%m Store is not expected! i = %0d", i);
          end  // else: !if(perm)
          // Only increment if trace_valid is high.
        end  // while (stream_progress < 2 * (TRB_WIDTH))
      end  // for (int perm = 0; perm < 2; perm++)
    end  // for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++)

  endtask  // test_trace_to_mem
  // Test serialization of a memory word in trace mode as well as correct issueing
  // of load requests.
  task test_mem_to_stream;
    logic [TRB_WIDTH-1:0] data;
    logic [TRB_WIDTH-1:0] outp;

    $display("[ %0t ] Test: Memory to Stream w. variable ntrace & trigger.", $time);
    for (int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
      // Setup
      reset_to_default();
      randomize(data);
      outp = '0;
      num_traces = ntrace;
      @(posedge clk);
      reset = 0;
      // Test start
      @(posedge clk);
      assert (load_request)
      else $error("[%m] Expected load_request.");
      // Answer load_request one cycle after.
      load_grant = 1;
      data_in = data;
      // Tracer will load value into stream register after full deserialization.
      for (int i = 0; i < TRB_WIDTH; i = i + 2 ** ntrace) begin
        @(posedge clk);
        load_grant = 0;
      end
      // New load_request will be issued.
      assert (load_request)
      else $error("[%m] Expected load_request.");
      for (int i = 0; i < TRB_WIDTH; i = i + 2 ** ntrace) begin
        if (i == 0) begin
          load_grant = 1;
          data_in = '0;
        end else begin
          load_grant = 0;
        end
        // Begin deserializing stream into outp to check with original value.
        for (int j = 0; j < TRB_MAX_TRACES; j++) begin
          if (j < 2 ** ntrace) begin
            outp[i+j] = stream[j];
          end
        end
        @(posedge clk);
      end
      assert (outp == data)
      else $error("[%m] Stream invalid, expected = %8h, got %8h", data, outp);
    end
  endtask  // test_mem_to_stream

  // Test propagation of delayed trigger event to FPGA side.
  task test_pre_trigger_event;
    $display("[ %0t ] Test: Pre-Trigger Event propagation.", $time);
    reset_to_default();
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    assert (stream_valid == 0);
    trg_delayed = 1;
    @(posedge clk);
    assert (stream_valid == 1);
  endtask  // test_pre_trigger_event

  // Test stream mode memory to serialization.
  // Bits are randomly stream_ready on the FPGA side with correct progress through the
  // memory word checked.
  // Additionally, signalling of data validity is checked by not servicing the
  // the second load request.
  task test_stream_mode_serialization;
    logic [TRB_WIDTH-1:0] data;
    logic [TRB_WIDTH-1:0] buffer;
    $display("[ %0t ] Test: Streaming mode.", $time);
    for (int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
      reset_to_default();
      mode = r_stream_mode;
      num_traces = ntrace;
      @(posedge clk);
      reset = 0;
      // Directly after reset a load_request to the memory device is expected.
      #1
      assert (load_request == 1)
      else $error("[%m] Expected load_Request.");
      // Stream output should be marked as invalid.
      assert (stream_valid == 0)
      else $error("[%m] Expected invalid signal.");
      @(posedge clk);
      load_grant = 1;
      randomize(data);
      data_in = data;
      @(posedge clk);
      load_grant = 0;
      // One cycle later, data has been copied into internal register
      // Stream output should hold valid data now.
      #1
      assert (stream_valid)
      else $error("[%m] Expected valid signal.");
      assert (load_request)
      else $error("[%m] Expected load_Request.");
      // A new load_request is expected one cycle later.

      @(posedge clk);
      for (int i = 0; i < TRB_WIDTH;) begin
        // Random stream_ready to simulate FPGA processing of data.
        if ($urandom_range(1)) begin
          stream_ready = 1;
          if (stream_valid) begin
            for (int j = 0; j < 2 ** ntrace; j++) begin
              buffer[i+j] = stream[j];
            end
          end

          i = i + 2 ** ntrace;
        end else begin
          stream_ready = 0;
        end
        @(posedge clk);
      end
      assert (buffer == data)
      else $error("[%m] Stream data did not match input! Expected %8h got %8h", data, buffer);
      // With one word from memory processed, output becomes invalid again.
      assert (!stream_valid)
      else $error("[%m] Stream expected to be invalid");
    end

  endtask  // test_stream_mode_serialization

  initial begin
    #20 test_trace_to_mem();
    test_stream_to_mem();
    test_mem_to_stream();
    test_pre_trigger_event();
    test_stream_mode_serialization();
    $dumpfile("TB_TRACER_DUMP.vcd");
    $dumpvars;
    $finish();

  end

endmodule  // TB_TRACER
// Local Variables:
// verilog-library-flags:("-f ../include.vc")
// End:
