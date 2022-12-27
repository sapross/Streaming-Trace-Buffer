//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_TraceLogger.sv
// Description     : Testbench for TracerLogger module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;

// --------------------------------------------------------------------
// Testbench Module
// --------------------------------------------------------------------
module TB_TRACELOGGER (/*AUTOARG*/ ) ;

   logic clk;
   logic reset_n;

   config_t conf;
   status_t stat;

   logic rw_turn;
   logic write;
   logic write_allow;
   logic read_allow;

   logic [$clog2(TRB_DEPTH)-1:0] read_ptr;
   logic [TRB_WIDTH-1:0]         dword_in;
   logic [$clog2(TRB_DEPTH)-1:0] write_ptr;
   logic [TRB_WIDTH-1:0]         dword_out;

   logic                         mode;
   logic [TRB_NTRACE_BITS-1:0]   num_traces;
   logic [$clog2(TRB_WIDTH)-1:0] event_pos;
   logic                         trg_event;
   logic                         trg_delayed;

   logic [TRB_WIDTH-1:0]         data_in;
   logic                         load_request;
   logic                         load_grant;

   logic [TRB_WIDTH-1:0]         data_out;
   logic                         store;
   logic                         store_perm;

   initial begin
      clk = 0;
   end
   always begin
      #5 clk = ~clk;
   end

   initial begin
      reset_n = 0;
      conf.trg_mode = 0;
      conf.trg_num_traces =0;
      conf.trg_delay = 0;
      rw_turn = 0;
      write_allow = 0;
      read_allow = 0;
      dword_in = 0;

      event_pos = 0;
      trg_event = 0;

      load_request =0;
      data_in = 0;
      store = 0;

      #20 reset_n = 1;
   end

   TraceLogger DUT (
                    .CLK_I              (clk),
                    .RST_NI             (reset_n),
                    .CONF_I             (conf),
                    .STAT_O             (stat),
                    .RW_TURN_I          (rw_turn),
                    .WRITE_O            (write),
                    .WRITE_ALLOW_I      (write_allow),
                    .READ_ALLOW_I       (read_allow),
                    .READ_PTR_O         (read_ptr),
                    .DMEM_I             (dword_in),
                    .WRITE_PTR_O        (write_ptr),
                    .DMEM_O             (dword_out),

                    .MODE_O             (mode),
                    .NTRACE_O           (num_traces),
                    .EVENT_POS_I        (event_pos),
                    .TRG_EVENT_I        (trg_event),
                    .TRG_DELAYED_O      (trg_delayed),

                    .DATA_O             (data_out),
                    .LOAD_REQUEST_I     (load_request),
                    .LOAD_GRANT_O       (load_grant),

                    .DATA_I             (data_in),
                    .STORE_I            (store),
                    .STORE_PERM_O       (store_perm)
                    );

   // Set control signals to default values and set reset signal.
   task reset_to_default;
      reset_n = 0;
      conf = CONFIG_DEFAULT;
      rw_turn = 0;
      write_allow = 0;
      read_allow = 0;
      dword_in = 0;

      event_pos = 0;
      trg_event = 0;

      load_request =0;
      data_in = 0;
      store = 0;
   endtask // reset_to_default

   // TODO: Testcases
   // - Test reading until read invalid w. random read_allow.
   // - Test writing until write invalid w. random write_allow.

   task test_trigger_delay_rand_rw;
      int rw_count;
      logic [$clog2(TRB_DEPTH)-1:0] rptr, wptr;

      $display("[ %0t ] Test: Trigger Delay w. random RW.", $time);
      for (int delay = 2**TRB_DELAY_BITS -1; delay >= 0; delay--) begin
         reset_to_default();
         read_allow <= 1;
         write_allow <= 1;
         conf.trg_delay <= delay;

         rw_count <= 0;
         @(posedge clk);
         reset_n <= 1;
         @(posedge clk);
         trg_event <= 1;
         event_pos <= $urandom_range(TRB_WIDTH - 1);
         @(posedge clk);
         while (rw_count < TRB_WIDTH + 5) begin
            // Invert rw_turn every cycle.
            rw_turn <= ~rw_turn;

            if ($urandom_range(1)) begin
               rw_count++;

               rptr <= read_ptr;
               wptr <= write_ptr;

               // Store request from Tracer.
               data_in <= $random;
               store <= 1;
               // Load request from Tracer.
               load_request <= 1;

               @(posedge clk);
               if (rw_turn == 1) begin
                  store <= 0;
                  rw_turn <= ~rw_turn;
                  load_request <= 0;
                  @(posedge clk);
               end
               load_request <= 0;
               store <= 0;

               rw_turn <= ~rw_turn;
               // Load answer from memory.
               dword_in <= $random;

            end // if ($urandom_range(1))
            @(posedge clk);

         end // while (rw_count < delay)

      end // for (int delay <= 2**TRB_DELAY_BITS -1; delay > 0; delay--)

   endtask // test_trigger_delay_rand_rw

   task test_rand_write;
      int rw_count;
      logic [$clog2(TRB_DEPTH)-1:0] rptr, wptr;

      $display("[ %0t ] Test: Trigger Delay w. random RW.", $time);
      for (int delay = 2**TRB_DELAY_BITS -1; delay >= 0; delay--) begin
         reset_to_default();
         read_allow <= 1;
         write_allow <= 1;
         conf.trg_delay <= delay;

         rw_count <= 0;
         @(posedge clk);
         reset_n <= 1;
         @(posedge clk);
         trg_event <= 1;
         event_pos <= $urandom_range(TRB_WIDTH - 1);
         @(posedge clk);
         while (rw_count < TRB_WIDTH + 5) begin
            // Invert rw_turn every cycle.
            rw_turn <= ~rw_turn;

            if ($urandom_range(1)) begin
               rw_count++;

               rptr <= read_ptr;
               wptr <= write_ptr;

               // Store request from Tracer.
               data_in <= $random;
               store <= 1;
               // Load request from Tracer.
               load_request <= 1;

               @(posedge clk);
               if (rw_turn == 1) begin
                  store <= 0;
                  rw_turn <= ~rw_turn;
                  load_request <= 0;
                  @(posedge clk);
               end
               load_request <= 0;
               store <= 0;

               rw_turn <= ~rw_turn;
               // Load answer from memory.
               dword_in <= $random;

            end // if ($urandom_range(1))
            @(posedge clk);

         end // while (rw_count < delay)

      end // for (int delay <= 2**TRB_DELAY_BITS -1; delay > 0; delay--)

   endtask // test_rand_write

   initial begin
      #20
        test_trigger_delay_rand_rw();
      $dumpfile("TB_TRACER_DUMP.vcd");
      $dumpvars;
   end

`include "TB_TraceLogger_Assertions.svh"

endmodule // TB_TRACELOGGER

