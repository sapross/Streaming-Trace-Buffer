//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_RV_Interface.sv
// Description     : Testbench for RV_Register module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

// --------------------------------------------------------------------
// Testbench Module
// --------------------------------------------------------------------
module TB_RV_INTERFACE (/*AUTOARG*/ ) ;

   localparam integer unsigned WRITE_WIDTH = 8;
   localparam integer unsigned READ_WIDTH = 8;

   logic clk;
   logic rst_n;

   logic read_enable;
   logic read_ready;
   logic read_valid;
   logic [READ_WIDTH-1:0] read_data;

   logic write_enable;
   logic write_ready;
   logic write_valid;
   logic [WRITE_WIDTH-1:0] write_data;

   logic update;
   logic [WRITE_WIDTH-1:0] data_out;

   logic change;
   logic [READ_WIDTH-1:0] data_in;

   initial begin
      clk = 0;
   end
   always begin
      #5 clk = ~clk;
   end

   initial begin
      rst_n = 0;
      read_enable = 0;
      read_ready = 0;
      write_enable = 0;
      write_valid = 0;
      write_data = '0;

      update = 0;
      change = 0;
      data_in ='0;
      #20 rst_n = 1;
   end

   RV_INTERFACE DUT (
                    .CLK_I              (clk),
                    .RST_NI             (rst_n),

                    .READ_ENABLE_I      (read_enable),
                    .READ_READY_I       (read_ready),
                    .READ_VALID_O       (read_valid),
                    .READ_DATA_O        (read_data),

                    .WRITE_ENABLE_I     (write_enable),
                    .WRITE_READY_O      (write_ready),
                    .WRITE_VALID_I      (write_valid),
                    .WRITE_DATA_I       (write_data),


                    .UPDATE_O           (update),
                    .DATA_O             (data_out),

                    .CHANGE_I           (change),
                    .DATA_I             (data_in)
                    );

   // Trigger reset and set DUT inputs to defaults.
   task reset_to_default;
      rst_n = 0;
      read_enable = 0;
      read_ready = 0;
      write_enable = 0;
      write_valid = 0;
      write_data = '0;

      update = 0;
      change = 0;
      data_in ='0;
   endtask // reset_to_default

   task test_random_read;

      $display("[ %0t ] Test: Random Read.", $time);
      reset_to_default();
      @(posedge clk);
      rst_n <= 1;
      for (int i = 0; i < 10;) begin
         // Keep read_enable random
         read_enable <= $random;
         // Start read process at random point.
         if ($urandom_range(1)) begin
            read_ready <= 1;
            data_in <= $random;
            @(posedge clk);

            while(!read_valid) begin
               read_enable <= $random;
               @(posedge clk);
            end
            read_ready <= 0;
            i++;
            @(posedge clk);
         end
      end
   endtask // test_random_read

   task test_device_initiated_read;

      $display("[ %0t ] Test: Random Read Initiated by Device.", $time);
      reset_to_default();
      @(posedge clk);
      rst_n <= 1;
      for (int i = 0; i < 10;) begin
         // Reading is enabled during the test.
         read_enable <= 1;
         // Start read process at random point.
         if ($urandom_range(1)) begin
            // Indicate a change in data from device.
            change <= 1;
            data_in <= $random;
            @(posedge clk);
            change <= 0;
            @(posedge clk);
            while(read_valid && !read_ready) begin
               // At a random point read the data.
               read_ready <= $random;
               @(posedge clk);
            end
            read_ready <= 0;
            i++;
            @(posedge clk);
         end
      end
   endtask // test_random_read

   task test_random_write;

      $display("[ %0t ] Test: Random Write.", $time);
      reset_to_default();
      @(posedge clk);
      rst_n <= 1;
      for (int i = 0; i < 10;) begin
         // Keep read_enable random
         write_enable <= $random;
         // Start read process at random point.
         if ($urandom_range(1)) begin
            write_valid <= 1;
            write_data <= $random;
            @(posedge clk);

            while(!write_ready) begin
               write_enable <= $random;
               @(posedge clk);
            end
            write_valid <= 0;
            i++;
            @(posedge clk);
         end
      end
   endtask // test_random_write

   initial begin
      #20
        test_device_initiated_read();
      test_random_write();
      test_random_read();
      $display("[ %0t ] All tests done.", $time);

      $dumpfile("TB_RV_INTERFACE_DUMP.vcd");
      $dumpvars;
   end

`include "TB_RV_Interface_Assertions.svh"

endmodule // TB_RV_Interface
