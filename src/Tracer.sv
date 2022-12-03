//                             -*- Mode: SystemVerilog -*-
// Filename        : Tracer.sv
// Description     : FPGA facing side of Data Trace Buffer responsible for generating the trace.
// Author          : Stephan Proß
// Created On      : Thu Nov 24 13:09:49 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 24 13:09:49 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!
import DTB_PKG::*;

module Tracer (
               // Signals & config from the system interface.
               input logic                            RST_I,
               input logic                            EN_I,
               // Mode bit switches from trace-buffer to data-streaming mode.
               input logic                            MODE_I,
               // Number of traces captured in parallel.
               input bit [$clog2(TRB_MAX_TRACES)-1:0] NTRACE_I,
               // Trigger Event after delay.
               input logic                            TRG_EVENT_I,
               // Data from memory.
               input logic [TRB_WIDTH-1:0]            DATA_I,
               // Load signal triggering capture of input data.
               input logic                            LOAD_I,

               // Outgoing signals to the system interface.
               // Position of the event in the word width of the memory.
               output logic [TRB_WIDTH-1:0]           EVENT_POS_O,
               // Signal denoting, whether event has occured and delay timer has run out.
               output logic                           TRG_EVENT_O,
               // Trace register to be stored in memory.
               output logic [TRB_WIDTH-1:0]           DATA_O,
               // Trigger storing of data and status.
               output logic                           STORE_O,
               // Signal for loading data from memory.
               output logic                            LOAD_O,

               // Signals of the FPGA facing side.
               input logic                            FPGA_CLK_I,
               // Trigger signal.
               input logic                            FPGA_TRIG_I,
               // Trace input and output. Allows for daisy-chaining STBs and serial
               // data streaming from system interface
               input logic                            FPGA_TRACE_I,
               output logic                           FPGA_TRACE_O,
               // Set to high after trigger event with delay. Usable for daisy-chaining.
               // Indicates whether data is valid in streaming mode.
               output logic                           FPGA_TRIG_O
               );

   typedef enum                                       {
                                                       st_idle,
                                                       st_wait_for_trigger,
                                                       st_capture_trace,
                                                       st_rwmode,
                                                       st_done
                                                       } state_t;
   state_t state, state_next;

   // Bit position of trigger.
   bit [$clog2(TRB_WIDTH)-1: 0]                       trace_pos;
   bit [$clog2(TRB_WIDTH)-1: 0]                       stream_pos;

   // Trace Register storing intermediate trace until a full data word for the
   // memory interface is collected.
   logic [TRB_WIDTH-1:0] trace,stream;
   assign DATA_O = trace;
   // Serial output data validity.
   logic                                              data_valid;

   // Sticky Trigger.
   logic                                              sticky_trigger;
   logic                                              trigger;

   // Make sticky trigger sticky depending on mode.
   always_ff @(posedge FPGA_CLK_I) begin
      if (RST_I) begin
         sticky_trigger <= 0;
         EVENT_POS_O <= 0;
      end
      else begin
         sticky_trigger <= sticky_trigger | FPGA_TRIG_I;
         if (!MODE_I) begin
            if (FPGA_TRIG_I && !sticky_trigger) begin
               EVENT_POS_O <= trace_pos;
            end
         end
         else begin
            EVENT_POS_O <= 0;
         end
      end
   end
   assign trigger = FPGA_TRIG_I | sticky_trigger;
   assign TRG_EVENT_O = FPGA_TRIG_I | sticky_trigger;


   // Switch meaning/content of FPGA_TRACE and TRIG output.
   assign FPGA_TRACE_O = stream[trace_pos];
   always_comb begin : SWITCH_OUTPUT
      if (!MODE_I) begin
         // FPGA_TRIG_O indicates trigger event after delay.
         FPGA_TRIG_O = TRG_EVENT_I;
      end
      else begin
         // FPGA_TRIG_O indicates whether the stream_data is valid.
         FPGA_TRIG_O = data_valid;
      end
   end

   // Trace registering and storing in memory.
   always_ff @(posedge FPGA_CLK_I) begin : TRACE_PROCESS
      if (RST_I) begin
         trace <= '0;
         STORE_O <= 0;
         trace_pos <= 0;
      end
      else if (EN_I) begin
         STORE_O <= 0;
         trace[trace_pos] <= FPGA_TRACE_I;
         trace_pos <= (trace_pos + 1) % TRB_WIDTH;
         if (trace_pos == TRB_WIDTH - 1) begin
            STORE_O <= 1;
         end
      end // else: !if(RST_I)
   end // block: TRACE_PROCESS

   // Stream register loading from memory.
   // Load pulse generation.
   logic       ld;
   logic [1:0] ld_reg;
   always_ff @(posedge FPGA_CLK_I) begin : LOAD_PULSE
      ld_reg = {ld_reg[0], ld};
   end
   always_comb begin
      if (!MODE_I) begin
         LOAD_O = STORE_O;
      end
      else begin
         // Only set LOAD_O to high on a positive edge in ld_reg.
         LOAD_O  = ~ld_reg[1] & ld_reg[0];
      end
   end


   logic new_data;

   always_ff @(posedge FPGA_CLK_I) begin : STREAM_PROCESS
      if (RST_I) begin
         stream <= '0;
         stream_pos <= 0;

         new_data <= 0;
         data_valid <= 0;
         ld <= 0;

      end
      else begin
         ld <= 0;
         // Set data_valid as soon as LOAD_I from TraceLogger is set to high.
         if (LOAD_I) begin
            new_data <= 1;
         end
         if (!MODE_I) begin
            // Tracer mode.
            // Start requesting new data at trace position zero.
            if (EN_I == 1) begin
               if (trace_pos == 0) begin
                  ld <= 1;
               end

               // Load DATA_I into stream register in position overflow.
               // Validity of data is assumed at this point.
               if (trace_pos == TRB_WIDTH - 1) begin
                  stream <= DATA_I;
               end
            end
         end
         else begin

            data_valid <= 1;
            // Request data from on stream position overflow.
            if (stream_pos == 0 && EN_I == 1) begin
               ld <= 1;
            end

            if (FPGA_TRIG_I) begin
               // Increment enable stream_pos counter only if TRIG_I signial is set.
               // TRIG_I acts essentially as load signal for the streaming logic.
               if (stream_pos < TRB_WIDTH - 1) begin
                  stream_pos <= stream_pos + 1;
               end
               else begin
                  // stream_pos will overflow on next cycle with set TRIG_I.
                  // Do we have new data at DATA_I input?
                  if (new_data) begin
                     if (FPGA_TRIG_I) begin
                        stream_pos <= 0;
                        stream <= DATA_I;
                     end
                  end
                  else begin
                     // Without new data, signal to FPGA serial data on FPGA_TRACE_O is
                     // invalid.
                     data_valid <= 0;
                  end // else: !if(new_data)
               end // else: !if(stream_pos < TRB_WIDTH - 1)

            end // if (stream_pos == TRB_WIDTH - 1)
         end // else: !if(!MODE_I)
      end // else: !if(RST_I)
   end // block: STREAM_PROCESS

endmodule // Tracer
