//                              -*- Mode: SystemVerilog -*-
// Filename        : TOP_UART_STB.sv
// Description     : Top-Module testing STB using UART-DTM.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import uart_pkg::*;

module TOP_UART_STB (/*AUTOARG*/ ) ;

   localparam integer unsigned WIDTH = 41;
   // 40 ns
   localparam integer unsigned CLK_PERIOD = 40;
   // 1/(3MBd) ~ 333 ns
   localparam integer unsigned BAUD_PERIOD = 333;

   logic                       clk;
   logic                       reset_n;

   logic                       rx0, rx1;
   logic                       tx0,tx1;

   logic                       sw_channel;
   logic                       dmi_req_ready;
   logic                       dmi_req_valid;
   logic [40:0]                dmi_req_data;
   logic                       dmi_resp_ready;
   logic                       dmi_resp_valid;
   logic [33:0]                dmi_resp_data;

   logic                       stb0_data_read_valid;
   logic                       stb0_data_read_ready;
   logic [31:0]                stb0_data_read;
   logic                       stb0_data_write_valid;
   logic                       stb0_data_write_ready;
   logic [31:0]                stb0_data_write;

   logic                       stb0_status_valid;
   logic                       stb0_status_ready;
   logic [7:0]                 stb0_status;
   logic                       stb0_control_valid;
   logic                       stb0_control_ready;
   logic [7:0]                 stb0_control;

   logic                       stb1_data_read_valid;
   logic                       stb1_data_read_ready;
   logic [31:0]                stb1_data_read;
   logic                       stb1_data_write_valid;
   logic                       stb1_data_write_ready;
   logic [31:0]                stb1_data_write;

   logic                       stb1_status_valid;
   logic                       stb1_status_ready;
   logic [7:0]                 stb1_status;
   logic                       stb1_control_valid;
   logic                       stb1_control_ready;
   logic [7:0]                 stb1_control;



   DTM_UART
     #(
       .ESC(ESC),
       .CLK_RATE(25*10*6),
       .BAUD_RATE(3*10*6),
       .STB_CONTROL_WIDTH(8),
       .STB_STATUS_WIDTH(8),
       .STB_DATA_WIDTH(32)
       )
   DUT
     (
      .CLK_I(clk),
      .RST_NI(reset_n),
      .RX0_I(rx0),
      .RX1_O(rx1),
      .TX0_O(tx0),
      .TX1_I(tx1),
      .DMI_REQ_READY_I    (dmi_req_ready),
      .DMI_REQ_VALID_O    (dmi_req_valid),
      .DMI_REQ_O          (dmi_req_data),
      .DMI_RESP_READY_O   (dmi_resp_ready),
      .DMI_RESP_VALID_I   (dmi_resp_valid),
      .DMI_RESP_I         (dmi_resp_data),

      .STB0_STATUS_READY_O  (stb0_status_ready),
      .STB0_STATUS_VALID_I  (stb0_status_valid),
      .STB0_STATUS_I        (stb0_status),
      .STB0_CONTROL_READY_I (stb0_control_ready),
      .STB0_CONTROL_VALID_0 (stb0_control_valid),
      .STB0_CONTROL_O       (stb0_control      ),

      .STB0_DATA_READ_READY_I  (stb0_data_read_ready),
      .STB0_DATA_READ_VALID_O  (stb0_data_read_valid),
      .STB0_DATA_READ_O        (stb0_data_read),
      .STB0_DATA_WRITE_READY_O (stb0_data_write_ready),
      .STB0_DATA_WRITE_VALID_I (stb0_data_write_valid),
      .STB0_DATA_WRITE_I       (stb0_data_write),

      .STB1_STATUS_READY_O  (stb1_status_ready),
      .STB1_STATUS_VALID_I  (stb1_status_valid),
      .STB1_STATUS_I        (stb1_status),
      .STB1_CONTROL_READY_I (stb1_control_ready),
      .STB1_CONTROL_VALID_0 (stb1_control_valid),
      .STB1_CONTROL_O       (stb1_control      ),

      .STB1_DATA_READ_READY_I  (stb1_data_read_ready),
      .STB1_DATA_READ_VALID_O  (stb1_data_read_valid),
      .STB1_DATA_READ_O        (stb1_data_read),
      .STB1_DATA_WRITE_READY_O (stb1_data_write_ready),
      .STB1_DATA_WRITE_VALID_I (stb1_data_write_valid),
      .STB1_DATA_WRITE_I       (stb1_data_write),

      );



`define rv_echo(READY_OUT, VALID_IN, DATA_IN, READY_IN, VALID_OUT, DATA_OUT) \
  always_ff @(posedge clk) begin \
    if (!reset_n) begin \
      READY_OUT <= 0; \
      VALID_OUT <= 0; \
      DATA_OUT <= '0; \
    end \
    else begin \
      READY_OUT <= 1; \
      VALID_OUT <= 1; \
      if(VALID_IN) begin \
        READY_OUT <= 1; \
        DATA_OUT <= DATA_IN; \
      end \
      if(READY_IN) begin \
        VALID_OUT <= 1; \
      end \
    end \
  end

`rv_echo(dmi_req_ready, dmi_req_valid, dmi_req_data, dmi_resp_ready, dmi_resp_valid, dmi_resp_data)

   logic [TRB_MAX_TRACES-1:0] fpga_read;
   logic                      fpga_read_ready;
   logic                      fpga_read_valid;

   logic [TRB_MAX_TRACES-1:0] fpga_write;
   logic                      fpga_write_ready;
   logic                      fpga_write_valid;

   StreamTraceBuffer STB0
     (
      .CLK_I                 (clk),
      .RST_NI                (rst_n),
      .STATUS_READY_I        (stb0_status_ready),
      .STATUS_VALID_O        (stb0_status_valid),
      .STATUS_O              (stb0_status),
      .CONTROL_READY_O       (stb0_control_ready),
      .CONTROL_VALID_I       (stb0_control_valid),
      .CONTROL_I             (stb0_control),
      .DATA_READY_I          (stb0_data_read_ready),
      .DATA_VALID_O          (stb0_data_read_valid),
      .DATA_O                (stb0_data_read),
      .DATA_READY_O          (stb0_data_write_ready),
      .DATA_VALID_I          (stb0_data_write_valid),
      .DATA_I                (stb0_data_write),
      .FPGA_CLK_I            (fpga_clk),
      .FPGA_TRIG_I           (1'b0),
      .FPGA_TRACE_I          ('0),
      .FPGA_WRITE_READY_O    (),
      .FPGA_READ_I           (fpga_read_ready),
      .FPGA_STREAM_O         (fpga_read),
      .FPGA_DELAYED_TRIG_O   (fpga_read_valid)
      );

   StreamTraceBuffer STB1
     (
      .CLK_I                 (clk),
      .RST_NI                (rst_n),
      .STATUS_READY_I        (stb1_status_ready),
      .STATUS_VALID_O        (stb1_status_valid),
      .STATUS_O              (stb1_status),
      .CONTROL_READY_O       (stb1_control_ready),
      .CONTROL_VALID_I       (stb1_control_valid),
      .CONTROL_I             (stb1_control),
      .DATA_READY_I          (stb1_data_read_ready),
      .DATA_VALID_O          (stb1_data_read_valid),
      .DATA_O                (stb1_data_read),
      .DATA_READY_O          (stb1_data_write_ready),
      .DATA_VALID_I          (stb1_data_write_valid),
      .DATA_I                (stb1_data_write),
      .FPGA_CLK_I            (fpga_clk),
      .FPGA_TRIG_I           (fpga_write_valid),
      .FPGA_TRACE_I          (fpga_write),
      .FPGA_WRITE_READY_O    (fpga_write_ready),
      .FPGA_READ_I           (1'b1),
      .FPGA_STREAM_O         (),
      .FPGA_DELAYED_TRIG_O   ()
      );
endmodule // TOP_UART_STB
