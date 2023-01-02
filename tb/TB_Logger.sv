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
module TB_LOGGER (/*AUTOARG*/ ) ;

   logic clk;
   logic reset_n;

   control_t control;
   status_t status;

   logic rw_turn;
   logic write;
   logic write_allow;
   logic read_allow;

   logic [TRB_ADDR_WIDTH-1:0] read_ptr;
   logic [TRB_WIDTH-1:0]      dword_in;
   logic [TRB_ADDR_WIDTH-1:0] write_ptr;
   logic [TRB_WIDTH-1:0]      dword_out;

   logic                      mode;
   logic [TRB_NTRACE_BITS-1:0] num_traces;
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
      control.trg_mode = 0;
      control.trg_num_traces =0;
      control.trg_delay = 0;
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

   Logger DUT (
               .CLK_I              (clk),
               .RST_NI             (reset_n),
               .CONTROL_I             (control),
               .STATUS_O             (status),
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
      control = CONTROL_DEFAULT;
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

      $display("[ %0t ] Test: Trigger Delay w. random RW.", $time);
      for (int delay = 2**TRB_DELAY_BITS -1; delay >= 0; delay--) begin
         // Control setup
         reset_to_default();
         read_allow <= 1;
         write_allow <= 1;
         control.trg_delay <= delay;
         @(posedge clk);
         // Lift reset.
         reset_n <= 1;
         @(posedge clk);
         // Launch trigger event.
         trg_event <= 1;
         event_pos <= $urandom_range(TRB_WIDTH - 1);
         @(posedge clk);
         // Start random rw.
         rw_count = 0;
         while (rw_count < TRB_WIDTH + 5) begin
            // Invert rw_turn every cycle.
            rw_turn <= ~rw_turn;

            if ($urandom_range(1)) begin
               rw_count++;
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

   task test_rand_read;
      int read_count;
      int max_num_reads;
      $display("[ %0t ] Test: Random read until reading is invalid.", $time);
      for (int mode = 0; mode < 2; mode++ ) begin
         // Control setup
         reset_to_default();
         store <= 0;
         control.trg_mode <= mode;
         max_num_reads <= 1;
         if(!mode) begin
            max_num_reads <= TRB_DEPTH;
         end
         @(posedge clk);
         // Lift reset.
         reset_n <= 1;
         rw_turn <= 0;

         read_count = 0;
         for (int read_count=0; read_count < max_num_reads;) begin
            @(posedge clk);
            rw_turn <= ~rw_turn;
            read_allow <= $random;
            if(rw_turn) begin
               dword_in <= $random;
            end
            if ($urandom_range(1)) begin
               load_request = 1;
               read_count++;
               while(!load_grant && (read_ptr +1)%TRB_DEPTH != write_ptr ) begin
                  @(posedge clk);
                  read_allow <= $random;
                  load_request = 0;
                  rw_turn <= ~rw_turn;
               end
            end
         end
      end
   endtask // test_rand_read

   task test_rand_write;
      int write_count;
      $display("[ %0t ] Test: Random write until writing is invalid.", $time);

      // Control setup
      reset_to_default();
      @(posedge clk);
      // Lift reset.
      reset_n <= 1;
      rw_turn <= 0;

      write_count = 0;
      for (int write_count=0; write_count < TRB_DEPTH;) begin
         @(posedge clk);
         store <= 0;
         rw_turn <= ~rw_turn;
         write_allow <= $random;
         if (write_allow && $urandom_range(1)) begin
            store <= 1;
            data_in <= $random;
            write_count++;
            while(!write && write_ptr != read_ptr) begin
               @(posedge clk);
               store <= 0;
               write_allow <= $random;
               rw_turn <= ~rw_turn;
            end
         end
      end
   endtask // test_rand_write
   initial begin
      #20
      test_trigger_delay_rand_rw();
      test_rand_write();
      test_rand_read();
      $display("All tests done.");

      $dumpfile("TB_TRACER_DUMP.vcd");
      $dumpvars;
   end

`include "TB_Logger_Assertions.svh"

endmodule // TB_LOGGER
