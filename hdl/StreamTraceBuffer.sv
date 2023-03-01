//                              -*- Mode: Verilog -*-
// Filename        : StreamTraceBuffer.sv
// Description     : Peripheral containing TraceLogger with System-Interface.
// Author          : Stephan Proß
// Created On      : Sun Jan  1 18:25:23 2023
// Last Modified By: Stephan Proß
// Last Modified On: Sun Jan  1 18:25:23 2023
// Update Count    : 0
// Status          : Unknown, Use with caution!
`include "../lib/STB_PKG.svh"

module StreamTraceBuffer
  (
   input logic                        CLK_I,
   input logic                        RST_NI,

   // Configuration & Status Interface
   input logic                        STATUS_READY_I,
   output logic                       STATUS_VALID_O,
   output logic [TRB_STATUS_BITS-1:0] STATUS_O,

   output logic                       CONTROL_READY_O,
   input logic                        CONTROL_VALID_I,
   input logic [TRB_CONTROL_BITS-1:0] CONTROL_I,

   // Data IO Interface
   input logic                        DATA_READY_I,
   output logic                       DATA_VALID_O,
   output logic [TRB_WIDTH-1:0]       DATA_O,

   output logic                       DATA_READY_O,
   input logic                        DATA_VALID_I,
   input logic [TRB_WIDTH-1:0]        DATA_I,

   // ---- FPGA signals ----
   // Signals of the FPGA facing side.
   input logic                        FPGA_CLK_I,
   // Trigger signal.
   input logic                        FPGA_TRIG_I,
   // Trace input
   input logic [TRB_MAX_TRACES-1:0]   FPGA_TRACE_I,
   // Write valid. Only relevant during streaming mode.
   output logic                       FPGA_WRITE_READY_O,

   // Read signal for streaming mode, irrelevant during trace mode.
   input logic                        FPGA_READ_I,
   // Stream output.
   output logic [TRB_MAX_TRACES-1:0]  FPGA_STREAM_O,
   // Set to high after trigger event with delay. Usable for daisy-chaining.
   // Indicates whether data is valid in streaming mode.
   output logic                       FPGA_DELAYED_TRIG_O

   );

   logic                              control_update;
   logic                              status_change;
   control_t control;
   status_t status;

   logic [1:0]                        redge_trigger;
   always_ff @(posedge CLK_I) begin
      if (!RST_NI) begin
         redge_trigger <= '0;
      end
      else begin
         redge_trigger <= {redge_trigger[0], status.trg_event};
      end
   end
   assign status_change = redge_trigger[0] ^ redge_trigger[1];

   RV_Interface #(TRB_CONTROL_BITS, TRB_STATUS_BITS)
   contrl_stat_intf
     (
      .CLK_I          (CLK_I),
      .RST_NI         (RST_NI),
      .READ_READY_I   (STATUS_READY_I),
      .READ_VALID_O   (STATUS_VALID_O),
      .READ_DATA_O    (STATUS_O),
      .WRITE_READY_O  (CONTROL_READY_O),
      .WRITE_VALID_I  (CONTROL_VALID_I),
      .WRITE_DATA_I   (CONTROL_I),
      .READ_ENABLE_I  (1'b1),
      .WRITE_ENABLE_I (1'b1),
      .UPDATE_O       (control_update),
      .DATA_O         (control),
      .CHANGE_I       (status_change),
      .DATA_I         (status),
      .READ_O         ()
      );

   logic [TRB_WIDTH-1:0]              sys_data, mem_data;
   logic                              sys_read, sys_write;
   logic                              read_allow, write_allow;


   RV_Interface #(TRB_WIDTH, TRB_WIDTH)
     data_intf
     (
      .CLK_I          (CLK_I),
      .RST_NI         (RST_NI),
      .READ_READY_I   (DATA_READY_I),
      .READ_VALID_O   (DATA_VALID_O),
      .READ_DATA_O    (DATA_O),
      .WRITE_READY_O  (DATA_READY_O),
      .WRITE_VALID_I  (DATA_VALID_I),
      .WRITE_DATA_I   (DATA_I),
      .READ_ENABLE_I  (read_allow),
      .WRITE_ENABLE_I (write_allow),
      .UPDATE_O       (sys_write),
      .DATA_O         (sys_data),
      .CHANGE_I       (1'b0),
      .DATA_I         (mem_data),
      .READ_O         (sys_read)
      );


   logic                              rw_turn;
   logic                              log_write_allow;
   logic                              log_read_allow;
   logic [TRB_ADDR_WIDTH-1:0]         log_read_ptr;
   logic [TRB_ADDR_WIDTH-1:0]         log_write_ptr;
   logic                              log_write;
   logic [TRB_WIDTH-1:0]              log_data_in;
   logic [TRB_WIDTH-1:0]              log_data_out;


   MemoryController mem_cntrl
     (
      .CLK_I                 (CLK_I),
      .RST_NI                (RST_NI),

      .RW_TURN_O             (rw_turn),
      .LOGGER_WRITE_ALLOW_O  (log_write_allow),
      .LOGGER_READ_ALLOW_O   (log_read_allow),
      .LOGGER_READ_PTR_I     (log_read_ptr),
      .LOGGER_WRITE_PTR_I    (log_write_ptr),
      .LOGGER_WRITE_I        (log_write),
      .LOGGER_DATA_I         (log_data_out),
      .LOGGER_DATA_O         (log_data_in),
      .TRG_EVENT_I           (status.trg_event),

      .MODE_I                (control.trg_mode),
      .WRITE_ALLOW_O         (write_allow),
      .READ_ALLOW_O          (read_allow),
      .READ_DATA_O           (mem_data),
      .READ_I                (sys_read),
      .WRITE_DATA_I          (sys_data),
      .WRITE_I               (sys_write)
      );

   TraceLogger trclog
     (
      .CLK_I              (CLK_I),
      .RST_NI             (RST_NI),

      .CONTROL_I          (control),
      .CONTROL_UPDATE_I   (control_update),
      .STATUS_O           (status),

      .RW_TURN_I          (rw_turn),

      .WRITE_O            (log_write),
      .WRITE_ALLOW_I      (log_write_allow),
      .READ_ALLOW_I       (log_read_allow),

      .READ_PTR_O         (log_read_ptr),
      .DMEM_I             (log_data_in),

      .WRITE_PTR_O        (log_write_ptr),
      .DMEM_O             (log_data_out),


      .FPGA_CLK_I         (FPGA_CLK_I),
      .FPGA_TRIG_I        (FPGA_TRIG_I),

      .FPGA_TRACE_I       (FPGA_TRACE_I),
      .FPGA_WRITE_READY_O (FPGA_WRITE_READY_O),

      .FPGA_READ_I        (FPGA_READ_I),

      .FPGA_STREAM_O      (FPGA_STREAM_O),
      .FPGA_DELAYED_TRIG_O(FPGA_DELAYED_TRIG_O)
      );


endmodule // StreamTraceBuffer
