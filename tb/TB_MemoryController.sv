//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_MemoryController.sv
// Description     : Testbench for MemoryController module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

// --------------------------------------------------------------------
// Testbench Module
// --------------------------------------------------------------------
module TB_MEMORYCONTROLLER (/*AUTOARG*/ ) ;

   localparam integer unsigned WRITE_WIDTH = 8;
   localparam integer unsigned READ_WIDTH = 8;

   logic clk;
   logic rst_n;

   logic rw_turn;
   logic [TRB_ADDR_WIDTH-1:0] read_ptr;
   logic [TRB_ADDR_WIDTH-1:0] write_ptr;
   logic                      logger_write;
   logic [TRB_WIDTH-1:0]      logger_data_in;
   logic [TRB_WIDTH-1:0]      logger_data_out;

   logic                      read_only;
   logic [TRB_WIDTH-1:0]      read_data;
   logic                      read;
   logic [TRB_WIDTH-1:0]      write_data;
   logic                      write;

   logic                      write_allow;
   logic                      read_allow;


   initial begin
      clk = 0;
   end
   always begin
      #5 clk = ~clk;
   end

   initial begin
      rst_n = 0;

      read_only = 0;
      read_ptr = '0;
      write_ptr = '0;
      logger_write = 0;
      logger_data_in = '0;

      read = 0;
      write_data = '0;
      write = 0;
      #20 rst_n = 1;
   end

   MemoryController DUT (
                         .CLK_I              (clk),
                         .RST_NI             (rst_n),
                         .RW_TURN_O          (rw_turn),
                         .READ_PTR_I         (read_ptr),
                         .WRITE_PTR_I        (write_ptr),
                         .LOGGER_WRITE_I     (logger_write),
                         .LOGGER_DATA_I      (logger_data_in),
                         .LOGGER_DATA_O      (logger_data_out),
                         .READ_ONLY_I        (read_only),
                         .READ_DATA_O        (read_data),
                         .READ_I             (read),
                         .WRITE_DATA_I       (write_data),
                         .WRITE_I            (write),
                         .WRITE_ALLOW_O      (write_allow),
                         .READ_ALLOW_O       (read_allow)
                         );

   // Trigger reset and set DUT inputs to defaults.
   task reset_to_default;
      rst_n = 0;

      read_only = 0;
      read_ptr = '0;
      write_ptr = '0;
      logger_write = 0;
      logger_data_in = '0;

      read = 0;
      write_data = '0;
      write = 0;
   endtask // reset_to_default

   task test_random_rw;

      $display("[ %0t ] Test: Random Read & Write.", $time);
      reset_to_default();
      @(posedge clk);
      rst_n <= 1;
      read_ptr = 1;
      write_ptr = 0;
      @(posedge clk);
      for (int i = 0; i < 100;) begin
         // Logger Sim
         logger_write <= 0;
         if ((read_ptr +1) % TRB_WIDTH  != write_ptr && read_allow && rw_turn) begin
            read_ptr = (read_ptr + $urandom_range(1)) % TRB_WIDTH;
         end
         if (write_ptr != read_ptr && write_allow && rw_turn) begin
            if ($urandom_range(1)) begin
               write_ptr = (write_ptr + 1) % TRB_WIDTH;
               logger_write <= 1;
               logger_data_in <= $random;
            end
         end

         // System Interface sim.
         write <= 0;
         read <= 0;
         if(read_allow && !rw_turn) begin
            read = $random;
         end
         if(write_allow && !rw_turn) begin
            if ($urandom_range(1)) begin
               write_data <= $random;
               write <= 1;
            end
         end
         @(posedge clk);

      end
   endtask // test_random_read

   initial begin
      #20
        test_random_rw();
      $display("[ %0t ] All tests done.", $time);

      $dumpfile("TB_MEMORYCONTROLLER_DUMP.vcd");
      $dumpvars;
   end

endmodule // TB_MEMORYCONTROLLER
