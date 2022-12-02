//                              -*- Mode: SystemVerilog -*-
// Filename        : Trace2Mem.sv
// Description     : Module handling saving the trace to memory.
// Author          : Stephan Proß
// Created On      : Thu Dec  1 13:37:07 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 13:37:07 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

import DTB_PKG::*;


module TraceLogger (
                  // --- To Interface ---
                  input logic                             CLK_I,
                  input logic                             RST_NI,

                  input logic [$bits(config_t)-1:0]       CONF_I,

                  output logic [$bits(status_t)-1:0]      STAT_O,
                  // Read&Wrote strobe. Indicates that a write operation
                  // can be performed in the current cycle.
                  input logic                             RW_TURN_I,
                  // RW enable.
                  output logic                            RW_O;
                  // RW address
                  output logic [$clog2(TRB_DEPTH)-1:0]    RW_PTR_O,
                  // Memory words to be exchanged.
                  input [TRB_WIDTH-1:0]                   DMEM_I;
                  output [TRB_WIDTH-1:0]                  DMEM_O;

                  // --- To Tracer ----
                  // Signals passed into the tracer (potentially through CDC).

                  // Config & Status exchange
                  // Mode bit switches from trace-buffer to data-streaming mode.
                  output logic                            MODE_O,
                  // Number of traces captured in parallel.
                  output bit [$clog2(TRB_MAX_TRACES)-1:0] NTRACE_O,

                  // Outgoing signals to the system interface.
                  // Position of the event in the word width of the memory.
                  input logic [TRB_WIDTH-1:0]             EVENT_POS_I,
                  // Signal denoting, whether event has occured and delay timer has run out.
                  input logic                             TRG_EVENT_I,

                  // Trace exchange
                  // Trace register to be stored in memory.
                  input logic [TRB_WIDTH-1:0]             DATA_I,
                  // Trigger storing of data and status.
                  input logic                             LOAD_I,
                  // Data from memory.
                  output logic [TRB_WIDTH-1:0]            DATA_O,
                  // Load signal triggering capture of output data.
                  output logic                            STORE_O,

                  );
   // Forwarding of relevant config fields to Tracer
   config_t conf;
   assign conf = CONF_I;

   assign MODE_O = conf.trg_mode;
   assign NTRACE_O = conf.trg_num_traces;

   // Forwarding of status to Interface.
   status_t stat;
   assign STAT_O = stat;

   assign stat.trg_event = TRG_EVENT_I;
   assign stat.event_pos = EVENT_POS_I;

   // Memory read and write pointer.
   bit [$clog2(TRB_DEPTH)-1:0] ptr, ptr_next;
   assign RW_PTR_O = ptr;

   // Address on which TRG_EVENT_I flipped from 0 to 1.
   bit [$clog2(TRB_DEPTH)-1:0]                            event_address;
   // Register required to determine TRG_EVENT_I posedge.
   logic                                                  reg_event;
   assign stat.evend_addr = event_address;

   always_ff @(posedge CLK_I) begin : SAVE_EVENT_ADDRESS
      if (!RST_NI) begin
         reg_event = 0;
         event_address = '0;
         end
      else if (TRG_EVENT_I == 1 && reg_event == 0) begin
         event_address = ptr;
         reg_event = 1;
      end
   end

   bit [$clog2(TRB_DEPTH)-1:0] word_counter, word_counter_next;
   always_ff @(posedge CLK_I) begin
      if(!RST_NI || CONF_UPDATE_I) begin
         // The config trg_delay controls the ratio values before and after the
         // trigger event i.e.:
         // trg_delay = 111 : (Almost) all trace data is from directly after the trigger event.
         // trg_delay = 100 : Half the trace data if before and after the event (centered).
         // trg_delay = 000 : Entire trace contains data leading up to trace event.
         // Formular for the limit L:
         // Let n := timer_stop, P := TRB_BITS, N := 2**timer_stop'length
         // L = n/N * P - 1
         word_counter = (conf.trg_delay * TRB_DEPTH) / 2**(TRB_DELAY_BITS-1) -1;
      end
      else begin
         if (word_counter != 0) begin
            word_counter = word_counter - 1;
         end



   end



   typedef enum {
                 st_idle,
                 st_rw_memory,
                 st_write_trace
                 } state_t;
   state_t state, state_next;


   logic [TRB_WIDTH-1:0] word, word_next;
   assign DMEM_O = word;

   logic                 store, store_next;
   assign STORE_O = store;

   always_ff (@posedge CLK_I)  begin : FSM_CORE
      if (!RST_NI) begin
         state <= st_idle;
         word <= '0;
         ptr <= 0;
         store <= 0;
      end
      else begin
         state <= state_next;
         word <= word_next;
         ptr <= ptr_next;
         store <= store_next;
      end
   end

   always_comb begin : FSM

      RW_O = 0;
      STORE_O = 0;

      if (!RST_NI) begin
         state_next = st_idle;
         word_next = '0;
      end
      else begin

         state_next = state;
         word_next = word;
         store_next = 0;

         case (state)
           // Waiting for load from tracer.
           st_idle: begin
              if (LOAD_I) begin
                 word_next = DATA_I;
                 state_next = st_rw_memory;
                 ptr_next = (ptr_next +1 ) % TRB_DEPTH;
              end
           end
           // Exchange trace with word from memory.
           st_rw_memory: begin
              RW_O = 1;
              if (RW_TURN_I = 1) begin
                 state_next = st_idle;
                 word_next = DMEM_I;
                 // Write mem word back to tracer.
                 store_next = 1;
              end
         endcase // case (state)
      end // else: !if(!RST_NI)
   end // block: FSM






endmodule // TraceLogger
