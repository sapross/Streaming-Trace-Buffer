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
   // - Test different trigger delays w. random simultaneous read and write.
   // - Test reading until read invalid w. random read_allow.
   // - Test writing until write invalid w. random write_allow.

   property outputs_after_reset_prop;
      @(posedge clk)
        (!reset_n) |-> ##1
          stat == STATUS_DEFAULT &&
                write == 0 &&
                read_ptr == 1 &&
                write_ptr == 0 &&
                dword_out == '0 &&
                mode == 0 &&
                data_out == '0 &&
                load_grant == 0 &&
                num_traces == 0;
   endproperty // outputs_after_reset_prop
   assert (outputs_after_reset)
     else
       $error("%m Output signals did not reset to correct values");


   property store_permission_prop;
      // Assert that the store is permitted under the right circumstances.
      @(posedge clk) disable iff(!reset_n)
        (write_allow &&
         write_ptr != read_ptr &&
         !trg_delayed) |-> store_perm == 1;
   endproperty // store_permission_prop
   assert(store_permission_prop)
     else
       $error ("%m Store permission expected");


   property store_to_memory_prop;
      // Assert that a store is followed by a write operation two cycles later
      // if store occured while TraceLogger has RW turn.
      @(posedge clk) disable iff(!reset_n || trg_delayed || !write_allow)
        (store) |-> ##[1:2]
          write == 1 &&
                 rw_turn == 1 &&
                 data_out == $past(dword_in);
   endproperty // store_to_memory_prop
   assert(store_to_memory_prop)
     else
       $error ("%m write operation did not occur on next rw_turn or is invalid.");

   property write_pointer_increment_prop;
      // Make sure that the write pointer is always incremented after a write operation.
      @(posedge clk) disable iff(!reset_n || trg_delayed || !write_allow)
        (write) |-> ##1
          write_ptr == ($past(write_ptr) + 1) % TRB_DEPTH;
   endproperty // write_pointer_increment_prop
   assert(write_pointer_increment_prop)
     else
       $error ("%m Write pointer did not increment after write operation");

   property write_disable_prop;
      // Ensure no write operation occurs if disallowed or the delayed trigger is set.
      @(posedge clk) disable iff(!reset_n)
        (trg_delayed || !write_allow) |->
          write == 0;
   endproperty // write_disable_prop

   assert(write_disable_prop)
     else
       $error ("%m write signal occured while disallowed or while delayed trigger is set.");

   int assert_delay;
   logic assert_first_trg;
   always_ff @(posedge clk) begin : trg_delay_assert_proc
      if (!reset_n) begin
         assert_delay = 0;
         assert_first_trg =0;
      end
      else begin
         if (trg_event) begin
            if(!assert_first_trg) begin
               assert_first_trg = 1;
               assert_delay = (conf.trg_delay*TRB_DEPTH)/ 2**(TRB_DELAY_BITS-1) -1;
            end
         end
         else begin
            assert (!trg_delayed)
              else
                $error("%m unexpected trg_delayed");
         end
         if(assert_first_trg && write) begin
            if (assert_delay > 0) begin
               assert_delay--;
               assert (!trg_delayed)
                 else
                   $error("%m unexpected trg_delayed");
            end
            else begin
               assert (trg_delayed)
                 else
                   $error("%m trg_delayed expected");
            end
         end
      end
   end


   // trigger_delay_prop;

   //   // Ensure that the delayed trigger actually has the correct delay.
   //   assert
   //   property (
   //             @(posedge clk) disable iff(!reset_n)
   //             (trg_event) |-> ##((conf.trg_delay*TRB_DEPTH)/ 2**(TRB_DELAY_BITS-1))
   //             trg_delayed
   //             )
   //     else
   //       $error ("%m write signal occured while disallowed or while delayed trigger is set.");


   task test_trigger_delay_rand_rw;
      int rw_count;
      logic [TRB_WIDTH-1:0] din, dout;
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
               randomize(din);
               randomize(dout);

               rptr <= read_ptr;
               wptr <= write_ptr;

               // Store request from Tracer.
               data_in <= din;
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
               dword_in <= dout;
               // Memory interface assertions
               // assert (write == 1)
               //      else
               //        $error("%m Expected write signal from TraceLogger.");

               // if (rw_count < (delay*TRB_DEPTH)/ 2**(TRB_DELAY_BITS-1) -1) begin
               //    #1 assert (read_ptr == (rptr + 1) % TRB_DEPTH)
               //      else
               //        $error("%m Read ptr did not increment!. Expected %8h, got %8h", (rptr + 1) % TRB_DEPTH, read_ptr);
               //    assert (write_ptr == (wptr + 1) % TRB_DEPTH)
               //      else
               //        $error("%m write ptr did not increment!. Expected %8h, got %8h", (wptr + 1) % TRB_DEPTH, write_ptr);
               //    assert (dword_out == din)
               //      else
               //        $error("%m Word written to memory invalid. Expected %8h, got %8h", din, dword_out);
               //    // Tracer interface assertions.
               //    assert (load_grant == 1)
               //      else
               //        $error("%m Expected load grant from TraceLogger");
               //    assert (data_out == dout)
               //      else
               //        $error("%m Word send to Tracer invalid. Expected %8h, got %8h", dout, data_out);
               // end
               // else begin
               //    #1 assert (write == 0)
               //      else
               //        $error("%m Unexpected write signal from TraceLogger after TRG_DELAY.");
               //    assert (read_ptr == (rptr + 1) % TRB_DEPTH)
               //      else
               //        $error("%m Read ptr shouldn't increment!. Expected %8h, got %8h", rptr, read_ptr);
               //    assert (write_ptr == (wptr + 1) % TRB_DEPTH)
               //      else
               //        $error("%m write ptr shouldn't increment!. Expected %8h, got %8h", wptr, write_ptr);
               //    // Tracer interface assertions.
               //    assert (load_grant == 0)
               //      else
               //        $error("%m Unexpected load grant from TraceLogger");
               // end

            end // if ($urandom_range(1))
            @(posedge clk);

         end // while (rw_count < delay)

      end // for (int delay <= 2**TRB_DELAY_BITS -1; delay > 0; delay--)

   endtask // test_trigger_delay_rand_rw


   initial begin
      #20
        test_trigger_delay_rand_rw();
      $dumpfile("TB_TRACER_DUMP.vcd");
      $dumpvars;
   end

endmodule // TB_TRACELOGGER
