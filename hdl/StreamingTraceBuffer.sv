//                              -*- Mode: SystemVerilog -*-
// Filename        : StreamingTraceBuffer.sv
// Description     : Trace Buffer for FPGA with doubling as a interface for data streaming.
// Author          : Stephan Proß
// Created On      : Thu Dec  1 09:12:28 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 09:12:28 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

module StreamingTraceBuffer (
                             input logic  RST_NI,
                             input logic  CLK_I,

                             // Signal selecting between data and config register.
                             input logic  REG_SELECT_I,
                             // Ready-Valid signals.
                             input logic  READ_READY_I,
                             output logic READ_VALID_O,
                             output logic WRITE_READY_O,
                             input logic  WRITE_VALID_I,

                             // TODO Interface definitions!

                             // Signals of the FPGA facing side.
                             input logic  FPGA_CLK_I,
                             // Trigger signal.
                             input logic  FPGA_TRIG_I,
                             // Trace input and output. Allows for daisy-chaining STBs and serial
                             // data streaming from system interface
                             input logic  FPGA_TRACE_I,
                             output logic FPGA_TRACE_O,
                             // Set to high after trigger event with delay. Usable for daisy-chaining.
                             // Indicates whether data is valid in streaming mode.
                             output logic FPGA_TRIG_O
                             ) ;






endmodule // StreamingTraceBuffer
