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

               // ---- Control & Status signals -----
               input logic                          RST_I,
               // Mode bit switches from trace-buffer to data-streaming mode.
               input logic                          MODE_I,
               // Number of traces captured in parallel.
               input bit [TRB_NTRACE_BITS-1:0]      NTRACE_I,
               // Position of the event in the word width of the memory.
               output logic [$clog2(TRB_WIDTH)-1:0] EVENT_POS_O,
               // Signal denoting, whether event has occured and delay timer has run out.
               output logic                         TRG_EVENT_O,
               // Trigger Event after delay.
               input logic                          TRG_DELAYED_I,

               // ---- Memory IO -----
               // Data from memory.
               input logic [TRB_WIDTH-1:0]          DATA_I,
               // Signal for requesting data from memory.
               output logic                         LOAD_REQUEST_O,
               // Load signal triggering capture of input data.
               input logic                          LOAD_GRANT_I,

               // Trace register to be stored in memory.
               output logic [TRB_WIDTH-1:0]         DATA_O,
               // Trigger storing of data and status.
               output logic                         STORE_O,
               // Indicator for store permission.
               input logic                          STORE_PERM_I,

               // ---- FPGA signals ----
               // Signals of the FPGA facing side.
               input logic                          FPGA_CLK_I,
               // Trigger signal.
               input logic                          FPGA_TRIG_I,
               // Trace input
               input logic [TRB_MAX_TRACES-1:0]     FPGA_TRACE_I,
               // Write valid. Only relevant during streaming mode.
               output logic                         FPGA_WRITE_VALID_O,

               // Read signal for streaming mode, irrelevant during trace mode.
               input logic                          FPGA_READ_I,
               // Stream output.
               output logic [TRB_MAX_TRACES-1:0]    FPGA_STREAM_O,
               // Set to high after trigger event with delay. Usable for daisy-chaining.
               // Indicates whether data is valid in streaming mode.
               output logic                         FPGA_TRIG_O
               );

   // Delayed idle bit required to prevent immediate incement of trace_pos on
   // set enable.
   logic                                            start;
   always_ff @(posedge FPGA_CLK_I) begin
      if(RST_I) begin
         start <= 0;
      end
      else begin
         start <= 1;
      end
   end


   // Bit position of trigger.
   bit [$clog2(TRB_WIDTH)-1: 0]                trace_pos;
   bit [$clog2(TRB_WIDTH)-1: 0]                stream_pos;

   bit [$clog2(TRB_MAX_TRACES):0]              num_trc;
   assign num_trc = 2**NTRACE_I;

   // Trace Register storing intermediate trace until a full data word for the
   // memory interface is collected.
   // To handle correct assignemnt of mulitple traces at once, the trace register
   // is extended by the maximum number of traces minimize required logic.
   logic [TRB_WIDTH+TRB_MAX_TRACES-1:0]        trace;
   assign DATA_O = trace[TRB_WIDTH-1:0];
   logic [TRB_WIDTH+TRB_MAX_TRACES-1:0]        stream;
   // Serial output data validity.
   logic                                       data_valid;

   // Sticky Trigger.
   logic                                       sticky_trigger;

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
   assign TRG_EVENT_O = sticky_trigger;

   assign FPGA_STREAM_O = stream[stream_pos +: TRB_MAX_TRACES];


   // Switch meaning/content of FPGA_TRACE and TRIG output.
   always_comb begin : SWITCH_TRIG_PURPOSE
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
         FPGA_WRITE_VALID_O <= 1;
      end
      else if (start) begin
         STORE_O <= 0;
         // Store trace signals in trace register.
         trace[trace_pos +: TRB_MAX_TRACES] <= FPGA_TRACE_I;
         if (trace_pos < TRB_WIDTH - num_trc) begin
            trace_pos <= (trace_pos + num_trc);
         end
         else begin
            // Only wrap trace_pos if store is permitted.
            // Also signal the FPGA-Side that new data cannot be accepted.
            if (STORE_PERM_I) begin
               FPGA_WRITE_VALID_O <= 1;
               trace_pos <= 0;
               STORE_O <= 1;
            end
            else begin
               FPGA_WRITE_VALID_O <= 0;
            end
         end
      end // else: !if(RST_I)
   end // block: TRACE_PROCESS

   // Stream register loading from memory.
   // Load pulse generation.
   logic       req;
   logic       req_prev;
   always_ff @(posedge FPGA_CLK_I) begin : REQUEST_PULSE_GEN
      if (RST_I) begin
         req_prev = 0;
      end
      else begin
         req_prev = req;
      end
   end
   assign  LOAD_REQUEST_O  = ~req_prev & req;

   // Register signifying whether new_data is present at the
   // (registered) DATA_I port.
   logic new_data;
   always_comb  begin : REQUEST_LOGIC
      // No request is issued by default.
      req = 0;
      if (start) begin
         if (!MODE_I) begin
            // Start requesting new data at stream position zero.
            if (stream_pos == 0) begin
               req = 1;
            end
         end
         else begin
            // In streaming mode issue a request the moment no new data
            // is available.
            req = ~new_data;
         end
      end
   end

   always_ff @(posedge FPGA_CLK_I) begin : STREAM_PROCESS
      if (RST_I) begin
         stream <= '0;
         stream_pos <= 0;

         new_data <= 0;
         data_valid <= 0;
      end
      else begin
         if (start) begin
            if (LOAD_GRANT_I) begin
               // Set new_data if load request has been granted.
               new_data <= 1;
            end
            if (!MODE_I) begin
               // ---- Tracer Mode -------
               // Stream position is trace position with one cycle delay.
               stream_pos <= trace_pos;
               // Load DATA_I into stream register in position overflow.
               // Overflow of trace position is used here to ensure stream
               // register contains new data the same cycle stream position
               // becomes zero again.
               if (trace_pos == 0 && new_data) begin
                  stream[TRB_WIDTH-1:0] <= DATA_I;
                  // Since data at the DATA_I port has been loaded into the
                  // stream register, it is no longer new.
                  new_data = 0;
               end
            end // if (!MODE_I)
            else begin
               // ---- Stream Mode -------
               // If all data has been serialized out of the stream register
               // (!data_valid) and new data is available, load stream register
               // with new data.
               if (!data_valid && new_data) begin
                  stream[TRB_WIDTH-1:0] <= DATA_I;
                  // Unset the flag.
                  new_data <= 0;
                  // Output is valid again.
                  data_valid <= 1;
               end

               // Progress of stream position is gated by data validity and
               // read signal on the FPGA side.
               if (FPGA_READ_I && data_valid) begin
                  if (stream_pos < TRB_WIDTH - num_trc) begin
                     stream_pos <= stream_pos + num_trc;
                  end
                  else begin
                     stream_pos <= 0;
                     // Same process as above. If new data is already available
                     // on position overflow, load it into stream without lowering
                     // validity signal.
                     if (new_data) begin
                        // If new data is available load into stream register.
                        stream[TRB_WIDTH-1:0] <= DATA_I;
                        // Unset the flag.
                        new_data <= 0;
                        // Output remains valid.
                        data_valid <= 1;
                     end
                     else begin
                        // New data is not available.
                        data_valid <= 0;
                     end
                  end
               end
            end // else: !if(!MODE_I)

         end // if (EN_I == 1)
      end // else: !if(RST_I)
   end // block: STREAM_PROCESS

endmodule // Tracer
