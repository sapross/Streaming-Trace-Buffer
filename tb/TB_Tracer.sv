//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_Tracer.sv
// Description     : Testbench for Tracer module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

// `include "Tracer/environment.sv"
import DTB_PKG::*;

// // --------------------------------------------------------------------
// // Test Program
// // --------------------------------------------------------------------
// program test(intf vif);

//    Environment env;
//    semaphore sema;

//    initial begin
//       env = new(vif);
//       sema = new();
//       env.driv.s = sema;
//       env.mon.d = sema;
//       env.gen.repeat_count = 10;
//       env.run();
//    end

// endprogram // test

// --------------------------------------------------------------------
// Testbench Module
// --------------------------------------------------------------------
module TB_TRACER (/*AUTOARG*/ ) ;

   logic clk;
   logic reset;

   logic mode;
   logic [TRB_NTRACE_BITS-1:0] num_traces;
   logic [$clog2(TRB_WIDTH)-1:0] event_pos;
   logic                         trg_event;
   logic                         trg_delayed;

   logic [TRB_WIDTH-1:0]       data_in;
   logic                       load_request;
   logic                       load_grant;

   logic [TRB_WIDTH-1:0]         data_out;
   logic                         store;
   logic                         store_perm;

   logic                         trg_in;
   logic [TRB_MAX_TRACES-1:0]    trace;
   logic                         write_valid;

   logic                         read;
   logic [TRB_MAX_TRACES-1:0]    stream;
   logic                         trg_out;

   always begin
      #5 clk = 0;
      #5 clk = 1;
   end
   initial begin
      clk = 1;
      reset = 1;
      mode = 0;
      num_traces = 0;
      trg_delayed = 0;
      data_in = 0;
      store_perm = 0;
      load_grant = 0;
      trg_in = 0;
      trace = '0;
      read = 0;
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
               .FPGA_TRIG_I        (trg_in),
               .FPGA_TRACE_I       (trace),
               .FPGA_WRITE_VALID_O (write_valid),
               .FPGA_READ_I        (read),
               .FPGA_STREAM_O      (stream),
               .FPGA_DELAYED_TRIG_O        (trg_out)
               );

   // Set control signals to default values and set reset signal.
   task reset_to_default;
      reset = 1;
      mode = 0;
      num_traces = 0;
      trg_delayed = 0;
      data_in = 0;
      store_perm = 1;
      load_grant = 0;
      trg_in = 0;
      trace = '0;
      read = 0;
   endtask // reset_to_default

   // Test deserialization of traces to memory words. Also set the trigger randomly
   // during test run and assert validity of event position.
   task test_trace_to_mem;
      logic [TRB_WIDTH-1:0]    data;
      bit [$clog2(TRB_WIDTH)-1:0] trig_pos;

      $display("[ %0t ] Test: Trace to Memory w. variable ntrace & trigger.", $time);
      for (int m = 0; m < 2; m++) begin
         for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
            for (int perm =0; perm < 2; perm++) begin
               reset_to_default();
               randomize(data);
               randomize(trig_pos);
               mode = m;
               num_traces = ntrace;
               store_perm = perm;
               @(posedge clk);
               reset = 0;
               @(posedge clk);
               for (int i =0; i< TRB_WIDTH; i =i+2**ntrace) begin
                  // Set trigger at random trigger position.
                  if (i < trig_pos) begin
                     trg_in = 0;
                  end
                  else if ( i >= trig_pos && i < trig_pos + 2**ntrace) begin
                     trg_in = 1;
                  end
                  else begin
                     // Trigger has random value after that.
                     trg_in = $urandom_range(0,1);
                  end

                  for ( int j =0; j<TRB_MAX_TRACES;j++ ) begin
                     if (j < 2**ntrace) begin
                        trace[j] = data[i+j];
                     end
                     else begin
                        trace[j] = 0;
                     end
                  end
                  @(posedge clk);
                  if (i < trig_pos) begin
                     assert (trg_event == 0)
                       else
                         $error("[%m] Unexpected trigger event at i=%0d, trig_pos=%0d.", i, trig_pos);
                  end
                  else begin
                     assert (trg_event == 1)
                       else
                         $error("[%m] Trigger event expected at i=%0d, trig_pos=%0d,", i, trig_pos );
                  end
                  if (i < TRB_WIDTH - 2**ntrace) begin
                     assert (store == 0) else $error("[%m] Unexpected store signal.");
                  end
               end
               if (perm) begin
                  assert (store == 1 && data_out == data)
                    else
                      $error("%m Deserialization failed for ntrace = %0d.\n expected data=%8h, got data_out=%8h", ntrace, data, data_out);
               end
               else begin
                  assert (store == 0)
                    else
                      $error("%m Store is not expected without store permission!");
                  store_perm =1;
                  @(posedge clk);
                  assert (store == 1 && data_out == data)
                    else
                      $error("%m Deserialization failed for ntrace = %0d.\n expected data=%8h, got data_out=%8h", ntrace, data, data_out);
               end
            end // for (int perm =0; perm < 2; perm++)
         end // for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++)
      end // for (int m = 0; m < 2; m++)

   endtask // test_trace_to_mem

   // Test serialization of a memory word in trace mode as well as correct issueing
   // of load requests.
   task test_mem_to_stream;
      logic [TRB_WIDTH-1:0]    data;
      logic [TRB_WIDTH-1:0]    outp;

      $display("[ %0t ] Test: Memory to Stream w. variable ntrace & trigger.", $time);
      for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
         // Setup
         reset_to_default();
         randomize(data);
         outp = '0;
         num_traces = ntrace;
         @(posedge clk);
         reset = 0;
         // Test start
         #1 assert (load_request)
           else
             $error("[%m] Expected load_request.");
         @(posedge clk);
         // Answer load_request one cycle after.
         load_grant = 1;
         data_in = data;
         @(posedge clk);
         // Tracer will load value into stream register after full deserialization.
         for (int i =2**ntrace; i< TRB_WIDTH; i =i+2**ntrace) begin
            load_grant = 0;
            @(posedge clk);
         end
         // New load_request will be issued.
         #1 assert (load_request)
           else
             $error("[%m] Expected load_request.");
         @(posedge clk);
         for (int i =0; i< TRB_WIDTH; i =i+2**ntrace) begin
            if(i==0) begin
               load_grant = 1;
               data_in = '0;
            end
            else begin
               load_grant = 0;
            end
            // Begin deserializing stream into outp to check with original value.
            for ( int j =0; j<TRB_MAX_TRACES;j++ ) begin
               if (j < 2**ntrace) begin
                  outp[i+j] = stream[j];
               end
            end
            @(posedge clk);
         end
         assert(outp == data)
           else
             $error("[%m] Stream invalid, expected = %8h, got %8h", data, outp);
      end
   endtask // test_mem_to_stream

   // Test propagation of delayed trigger event to FPGA side.
   task test_pre_trigger_event;
      $display("[ %0t ] Test: Pre-Trigger Event propagation.", $time);
      reset_to_default();
      @(posedge clk);
      reset = 0;
      @(posedge clk);
      assert (trg_out == 0)
      trg_delayed = 1;
      @(posedge clk);
      assert (trg_out == 1);
   endtask // test_pre_trigger_event

   // Test stream mode memory to serialization.
   // Bits are randomly read on the FPGA side with correct progress through the
   // memory word checked.
   // Additionally, signalling of data validity is checked by not servicing the
   // the second load request.
   task test_stream_mode_serialization;
      logic [TRB_WIDTH-1:0] data;

      $display("[ %0t ] Test: Streaming mode.", $time);
      for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
         reset_to_default();
         mode = 1;
         num_traces = ntrace;
         @(posedge clk);
         reset = 0;
         // Directly after reset a load_request to the memory device is expected.
         #1 assert (load_request == 1) else $error("[%m] Expected load_Request.");
         // Stream output should be marked as invalid.
         assert (trg_out == 0) else $error("[%m] Expected invalid signal.");
         @(posedge clk);
         load_grant = 1;
         randomize(data);
         data_in = data;
         @(posedge clk);
         load_grant = 0;
         // One cycle later, data has been copied into internal register
         // Stream output should hold valid data now.
         #1 assert (trg_out) else $error("[%m] Expected valid signal.");
         assert (load_request) else $error("[%m] Expected load_Request.");
         @(posedge clk);
         // A new load_request is expected one cycle later.

         for (int i =0; i< TRB_WIDTH;) begin
            for ( int j =0; j<TRB_MAX_TRACES;j++ ) begin
               if (j < 2**ntrace) begin
                  assert(stream[j] == data[i+j]) else
                    $error("[%m] Stream bit %0d invalid, expected %0d got %0d",j,data[i+j], stream[j]);
               end
            end
            // Random read to simulate FPGA processing of data.
            if ($urandom_range(1)) begin
               read = 1;
               i = i + 2**ntrace;
            end
            else begin
               read = 0;
            end;
            @(posedge clk);
         end
         // With one word from memory processed, output becomes invalid again.
         assert(!trg_out);
      end

   endtask // test_stream_mode_serialization

   initial begin
      #20
      test_trace_to_mem();
      test_mem_to_stream();
      test_pre_trigger_event();
      test_stream_mode_serialization();
      $dumpfile("TB_TRACER_DUMP.vcd");
      $dumpvars;
   end

endmodule // TB_TRACER
