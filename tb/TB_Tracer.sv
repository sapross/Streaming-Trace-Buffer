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

   always begin
      #5 clk = 0;
      #5 clk = 1;
   end
   initial begin
      clk = 1;
      reset = 1;
      pre_trg_event = 0;
      data_in = 0;
      load = 0;
      trg_in = 0;
      read = 0;
      #20 reset = 0;
   end

   logic enable;
   logic mode;

   logic [TRB_NTRACE_BITS-1:0] num_traces;
   logic                       pre_trg_event;
   logic [TRB_WIDTH-1:0]       data_in;
   logic                       load;

   logic [$clog2(TRB_WIDTH)-1:0] event_pos;
   logic                         trg_event;
   logic [TRB_WIDTH-1:0]         data_out;
   logic                         store;
   logic                         request;
   logic                         trg_in;
   logic [TRB_MAX_TRACES-1:0]    trace;
   logic                         trg_out;
   logic [TRB_MAX_TRACES-1:0]    stream;
   logic                         read;

   Tracer DUT (
               .RST_I           (reset),
               .EN_I            (enable),
               .MODE_I          (mode),
               .NTRACE_I        (num_traces),
               .TRG_EVENT_I     (pre_trg_event),
               .DATA_I          (data_in),
               .LOAD_I          (load),
               .EVENT_POS_O     (event_pos),
               .TRG_EVENT_O     (trg_event),
               .DATA_O          (data_out),
               .STORE_O         (store),
               .REQ_O           (request),
               .FPGA_CLK_I      (clk),
               .FPGA_TRIG_I     (trg_in),
               .FPGA_TRACE_I    (trace),
               .FPGA_READ_I     (read),
               .FPGA_STREAM_O   (stream),
               .FPGA_TRIG_O     (trg_out)
               );
   task exec_reset;

      reset = 1;
      enable = 0;
      mode = 0;
      num_traces = 0;
      pre_trg_event = 0;
      data_in = 0;
      load = 0;
      trg_in = 0;
      trace = '0;
      read = 0;
      @(posedge clk);
      reset = 0;
   endtask // exec_reset

   task test_trace_to_mem;
      logic [TRB_WIDTH-1:0]    data;
      bit [$clog2(TRB_WIDTH)-1:0] trig_pos;

      $display("[ %0t ] Test: Trace to Memory w. variable ntrace & trigger.", $time);
      for (int m = 0; m < 2; m++) begin
         mode = m;
         for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
            exec_reset();
            randomize(data);
            randomize(trig_pos);
            num_traces = ntrace;
            @(posedge clk);
            enable = 1;
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
               // Wait a moment to let combinational signals propagate.
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
            assert (store == 1 && data_out == data)
              else
                $error("%m Deserialization failed for ntrace = %0d.\n expected data=%8h, got data_out=%8h", ntrace, data, data_out);
         end

      end //
   endtask // test_trace_to_mem

   task test_mem_to_trace;
      logic [TRB_WIDTH-1:0]    data;
      logic [TRB_WIDTH-1:0]    outp;

      $display("[ %0t ] Test: Memory to Stream w. variable ntrace & trigger.", $time);
      for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
         // Setup
         exec_reset();
         randomize(data);
         outp = '0;
         num_traces = ntrace;
         @(posedge clk);
         // Test start
         enable = 1;
         #1 assert (request)
           else
             $error("[%m] Expected request.");
         @(posedge clk);
         // Answer request one cycle after.
         load = 1;
         data_in = data;
         @(posedge clk);
         // Tracer will load value into stream register after full deserialization.
         for (int i =2**ntrace; i< TRB_WIDTH; i =i+2**ntrace) begin
            load = 0;
            @(posedge clk);
         end
         // New request will be issued.
         #1 assert (request)
           else
             $error("[%m] Expected request.");
         @(posedge clk);
         for (int i =0; i< TRB_WIDTH; i =i+2**ntrace) begin
            if(i==0) begin
               load = 1;
               data_in = '0;
            end
            else begin
               load = 0;
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
   endtask // test_mem_to_trace

   task test_pre_trigger_event;
      $display("[ %0t ] Test: Pre-Trigger Event propagation.", $time);
      exec_reset();
      @(posedge clk);
      enable = 1;
      @(posedge clk);
      assert (trg_out == 0)
      pre_trg_event = 1;
      @(posedge clk);
      assert (trg_out == 1);
   endtask // test_pre_trigger_event

   task test_stream_mode;
      logic [TRB_WIDTH-1:0] data;

      $display("[ %0t ] Test: Streaming mode.", $time);
      for ( int ntrace = 0; ntrace < $clog2(TRB_MAX_TRACES); ntrace++) begin
         exec_reset();
         mode = 1;
         num_traces = ntrace;
         @(posedge clk);
         enable = 1;
         // Directly after reset a request to the memory device is expected.
         #1 assert (request == 1) else $error("[%m] Expected Request.");
         // Stream output should be marked as invalid.
         assert (trg_out == 0) else $error("[%m] Expected invalid signal.");
         @(posedge clk);
         load = 1;
         randomize(data);
         data_in = data;
         @(posedge clk);
         load = 0;
         // One cycle later, data has been copied into internal register
         // Stream output should hold valid data now.
         #1 assert (trg_out) else $error("[%m] Expected valid signal.");
         assert (request) else $error("[%m] Expected Request.");
         @(posedge clk);
         // A new request is expected one cycle later.

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

   endtask // test_stream_mode

   initial begin
      #20
      test_trace_to_mem();
      test_mem_to_trace();
      test_pre_trigger_event();
      test_stream_mode();
      $dumpfile("TB_TRACER_DUMP.vcd");
      $dumpvars;
   end

endmodule // TB_TRACER
