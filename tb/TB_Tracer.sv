//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_Tracer.sv
// Description     : Testbench for Tracer module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;

// --------------------------------------------------------------------
// Transactions
// --------------------------------------------------------------------
// Input transaction on FPGA side.
class InTX;
   logic mode;
   bit [TRB_NTRACE_BITS-1:0] num_traces;
   logic                     pre_trigger_event;

   rand logic [TRB_MAX_TRACES-1:0] trace;
   rand logic                           trigger;
   rand logic                           read;


   rand logic [TRB_WIDTH-1:0]           data_in;
   logic                           load;

   function void display(string name);
      $display("------------------------");
      $display("- %s ", name);
      $display("------------------------");
      if (mode) begin
         $display("- mode: tracer");
      end
      else begin
         $display("- mode: stream");
      end
      $display("- num_traces %0d ", num_traces);
      $display("- pre_trigger_event %0d ", pre_trigger_event);

      $display("- trace = %8b ", trace);
      $display("- trigger %0b ", trigger);
      $display("- read = %0b ", read );

      $display("- data_in = %8h", data_in);
      $display("- load = %0b ", load );
      $display("------------------------");
   endfunction // display


class OutTX;

   logic [$clog2(TRB_WIDTH)-1:0] event_pos;
   logic                       trigger_event;

   logic [TRB_MAX_TRACES-1:0]    stream;
   logic                         trigger;

   logic [TRB_WIDTH -1:0]     data_out;
   logic                      store;
   logic                      request;

   function void display(string name);
      $display("------------------------");
      $display("- %s ", name);
      $display("------------------------");
      $display("- event_pos %0d ", event_pos);
      $display("- trigger_event %0d ", trigger_event);

      $display("- stream = %32b ", stream);
      $display("- trigger = %0b ", trigger);

      $display("- data_out = %8h", data_out);
      $display("- store = %0b ", store );
      $display("- request = %0b ", request );
      $display("------------------------");
   endfunction // display
endclass // OutTX

// --------------------------------------------------------------------
// Interfaces
// --------------------------------------------------------------------

interface Interface(
                    input logic clk,reset
                    );
   // Control signals
   logic                        enable;
   logic                        mode;
   bit [TRB_NTRACE_BITS-1:0]    num_traces;
   logic                        pre_trigger_event;

   logic [$clog2(TRB_WIDTH)-1:0] event_pos;
   logic                         trigger_event;

   //FPGA signals
   logic                         trigger;
   logic [TRB_MAX_TRACES-1:0]    trace;
   logic                         trigger_out;
   logic                         read;
   logic [TRB_MAX_TRACES-1:0]    stream;

   // Memory interface signals
   logic [TRB_WIDTH-1:0]      data_out;
   logic                      store;
   logic                      req;

   logic [TRB_WIDTH-1:0]      data_in;
   logic                      load;

endinterface // intf

// --------------------------------------------------------------------
// Generator
// --------------------------------------------------------------------
class Generator;
   rand InTX trans;
   mailbox gen2driv;
   event   ended;

   int     repeat_count;

   function new(mailbox gen2driv);
      this.gen2driv = gen2driv;
   endfunction // new

   task test_tracemode_ntrace();
      $display("[ Generator ] ------------------")
      for (int ntrace=0; ntrace < TRB_MAX_TRACES; ntrace++) begin
         for (int bits=0; bits < TRB_WIDTH; bits = bits + 2**ntrace) begin
            trans = new();
            trans.randomize();
            trans.mode = 0;
            trans.num_traces = ntrace;
            trans.pre_trigger_event = 0;
            trans.trigger = rand();
            trans.read = 0;
            trans.data_in = '0;
            trans.load = 0;

            gen2driv.put(trans);
         end
      end
   endtask // test01


   task main();
      repeat(repeat_count) begin
         trans = new();
         if( !trans.randomize() ) begin
            $fatal("Gen:: trans randomization failed");
         end
         gen2driv.put(trans);
      end
      -> ended;
   endtask // main

endclass // Generator

// --------------------------------------------------------------------
// Driver
// --------------------------------------------------------------------
class Driver;

   virtual                    Interface vif;
   mailbox                    gen2driv;
   int                        num_transactions;
   semaphore                  s;

   function new(virtual intf vif, mailbox gen2driv);
      this.vif = vif;
      this.gen2driv = gen2driv;
      num_transactions = 0;
   endfunction // new

   task reset;
      wait(vif.reset);
      $display("[ DRIVER ] ----- Reset Start -----");
      vif.trace = '0;
      vif.enable = 0;
      vif.mode = 0;
      vif.num_traces = 0;
      wait(!vif.reset);
      $display("[ DRIVER ] -----  Reset End  -----");
   endtask // reset

   task main;
      forever begin
         InTX trans;
         gen2driv.get(trans);
         vif.num_traces = trans.num_traces;
         @(posedge vif.clk);
         vif.enable = 1;
         for (int i =0; i<TRB_WIDTH; i=i+2**vif.num_traces) begin
            for (int j = 0; j< TRB_MAX_TRACES; j++) begin
               if ( j< vif.num_traces ) begin
                  vif.trace[j] = trans.trace[i+j];
               end
               else begin
                  vif.trace[j] = 0;
               end
            end
            s.put();
            @(posedge vif.clk);
         end
         trans.data = vif.data;
         trans.store = vif.store;
         vif.enable = 0;
         @(posedge vif.clk);
         trans.display("[ Driver ]");
         num_transactions++;
      end // forever begin
   endtask // drive

endclass // Driver

// --------------------------------------------------------------------
// Monitor
// --------------------------------------------------------------------
class Monitor;
   virtual intf vif;

   mailbox mon2scb;

   semaphore d;

   function new(virtual intf vif, mailbox mon2scb);
      this.vif =vif;
      this.mon2scb = mon2scb;
   endfunction // new

   task main;
      forever begin

         InTX trans;
         trans = new();

         wait(vif.enable);
         for (int i =0; i< (TRB_WIDTH/2**vif.num_traces); i++) begin
            d.get();
            @(posedge vif.clk);
            for(int j = 0; j< TRB_MAX_TRACES; j++) begin
               trans.trace[j][i] = vif.trace[j];
            end
         end
         trans.store = vif.store;
         trans.data = vif.data;
         trans.num_traces = vif.num_traces;
         @(posedge vif.clk);
         mon2scb.put(trans);
         trans.display("[ Monitor ]");
      end
   endtask // main

endclass // Monitor

// --------------------------------------------------------------------
// Scoreboard
// --------------------------------------------------------------------
class Scoreboard;
   mailbox mon2scb;
   int     num_transactions;
   function new(mailbox mon2scb);
      this.mon2scb = mon2scb;
   endfunction // new

   logic [TRB_WIDTH-1:0] expectation= '0;
   task main;
      InTX trans;
      forever begin
         mon2scb.get(trans);
         for (int i = 0; i< TRB_WIDTH; i = i + 2**trans.num_traces) begin
            for (int j = 0; j<2**trans.num_traces; j++) begin
               expectation[i+j] = trans.trace[j][i];
            end
         end
         if(expectation == trans.data) begin
            $display("Result as expected.");
         end
         else begin
            $error("Incorrect result.\nExpected %0h, Actual %0h",expectation, trans.data);
         end
      end // forever begin
   endtask // main

endclass // Scoreboard

// --------------------------------------------------------------------
// Environment
// --------------------------------------------------------------------
class Environment;

   Generator gen;
   Driver driv;
   Monitor mon;
   Scoreboard scb;

   mailbox gen2driv;
   mailbox mon2scb;

   virtual intf vif;
   function new(virtual intf vif);
      this.vif = vif;

      gen2driv = new();
      mon2scb = new();

      gen = new(gen2driv);
      driv = new(vif,gen2driv);
      mon = new(vif, mon2scb);
      scb = new(mon2scb);

   endfunction // new

   task pre_test();
      driv.reset();
   endtask // pre_test

   task test();
      fork
         gen.main();
         driv.main();
         mon.main();
         scb.main();
      join_any
   endtask // test

   task post_test();
      wait(gen.ended.triggered);
      wait(gen.repeat_count == driv.num_transactions);
      wait(gen.repeat_count == scb.num_transactions);
   endtask // post_test

   task run;
      pre_test();
      test();
      post_test();
      $finish();
   endtask // run

endclass // Environment

// --------------------------------------------------------------------
// Test Program
// --------------------------------------------------------------------
program test(intf vif);

   Environment env;
   semaphore sema;

   initial begin
      env = new(vif);
      sema = new();
      env.driv.s = sema;
      env.mon.d = sema;
      env.gen.repeat_count = 10;
      env.run();
   end

endprogram // test

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
      reset = 1;
      #20 reset = 0;
   end

   intf i_intf(clk,reset);

   Tracer DUT (
               .RST_I(i_intf.reset),
               .EN_I(i_intf.enable),
               .MODE_I(i_intf.mode),
               .NTRACE_I(i_intf.num_traces),
               .TRG_EVENT_I( 0 ),
               .DATA_I('0 ),
               .LOAD_I( 0 ),
               .EVENT_POS_O( ),
               .TRG_EVENT_O( ),
               .DATA_O(i_intf.data),
               .STORE_O(i_intf.store),
               .REQ_O( ),
               .FPGA_CLK_I(i_intf.clk),
               .FPGA_TRIG_I( 0 ),
               .FPGA_TRACE_I(i_intf.trace),
               .FPGA_TRACE_O( ),
               .FPGA_TRIG_O( )
               );

   test t1(i_intf);
   initial begin
      $dumpfile("TB_TRACER_DUMP.vcd");
      $dumpvars;
   end

endmodule // TB_TRACER
