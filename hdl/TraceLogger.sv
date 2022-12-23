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
                    // --- Interface Ports ---
                    input logic                             CLK_I,
                    input logic                             RST_NI,

                    input logic [$bits(config_t)-1:0]       CONF_I,
                    output logic [$bits(status_t)-1:0]      STAT_O,

                    // Read & Write strobe. Indicates that a write operation
                    // can be performed in the current cycle.
                    input logic                             RW_TURN_I,
                    // Signal write intend to memory.
                    output logic                            WRITE_O,
                    // Signals to indicate whether reading/writing is possible.
                    input logic                             WRITE_ALLOW_I,
                    input logic                             READ_ALLOW_I,

                    // Read&Write Pointers with associated data ports.
                    output logic [$clog2(TRB_DEPTH)-1:0]    READ_PTR_O,
                    input logic [TRB_WIDTH-1:0]             DMEM_I,

                    output logic [$clog2(TRB_DEPTH)-1:0]    WRITE_PTR_O,
                    output logic [TRB_WIDTH-1:0]            DMEM_O,

                    // --- To Tracer ----
                    // Signals passed into the tracer (potentially through CDC).

                    // Config & Status exchange
                    // Mode bit switches from trace-buffer to data-streaming mode.
                    output logic                            MODE_O,
                    // Number of traces captured in parallel.
                    output bit [TRB_NTRACE_BITS-1:0] NTRACE_O,


                    // Outgoing signals to the system interface.
                    // Position of the event in the word width of the memory.
                    input logic [$clog2(TRB_WIDTH)-1:0]     EVENT_POS_I,
                    // Indicates presence of trigger event.
                    input logic                             TRG_EVENT_I,
                    // Signal denoting, whether event has occured and delay
                    // timer has run out.
                    output logic                            TRG_DELAYED_O,

                    // Data from memory.
                    output logic [TRB_WIDTH-1:0]            DATA_O,
                    // Tracer request of new data from memory.
                    input logic                             LOAD_REQUEST_I,
                    // Signal to Tracer that read has been granted.
                    output logic                            LOAD_GRANT_O,

                    // Trace exchange
                    // Trace register to be stored in memory.
                    input logic [TRB_WIDTH-1:0]             DATA_I,
                    // Load signal triggering capture of data from Tracer.
                    input logic                             STORE_I,
                    // Signal to determine whether writing the trace is currently permissible.
                    output logic                            STORE_PERM_O
                    );


   // Forwarding of relevant config fields to Tracer
   config_t conf;
   assign conf = CONF_I;

   assign MODE_O = conf.trg_mode;
   assign NTRACE_O = conf.trg_num_traces;

   // Forwarding of status to Interface.
   status_t stat;
   assign STAT_O = stat;
   assign stat.event_pos = EVENT_POS_I;
   assign TRG_DELAYED_O = stat.trg_event;

   // -----------------------------------------------------------------------------
   // --- (Pre-)Trigger Event Handling ---
   // -----------------------------------------------------------------------------

   // Address on which TRG_EVENT_I flipped from 0 to 1.
   bit [$clog2(TRB_DEPTH)-1:0]                              event_address;
   assign stat.event_addr = event_address;

   // Memory write pointer
   bit [$clog2(TRB_DEPTH)-1:0]                              write_ptr;
   assign WRITE_PTR_O = write_ptr;
   // Registered (sticky) trg_event.
   logic                                                    trg_event;
   always_ff @(posedge CLK_I) begin : SAVE_EVENT_ADDRESS
      if (!RST_NI) begin
         trg_event = 0;
         event_address = '0;
      end
      else if (TRG_EVENT_I == 1 && trg_event == 0) begin
         // Save on which address the trigger has been registered.
         event_address = write_ptr;
         trg_event = 1;
      end
   end

   // Counter for determining the ratio of history to pre-history.
   bit [$clog2(TRB_DEPTH)-1:0] hist_count;

   // Write signal.
   logic                       write;
   assign WRITE_O = write;



   always_ff @(posedge CLK_I) begin : PRE_TRIGGER_PROC
      // Only start counting down the moment a trigger event has been registered.
      if(!RST_NI || !trg_event) begin
         // The config trg_delay controls the ratio values before and after the
         // trigger event i.e.:
         // trg_delay = 111 : (Almost) all trace data is from directly after the trigger event.
         // trg_delay = 100 : Half the trace data if before and after the event (centered).
         // trg_delay = 000 : Entire trace contains data leading up to trace event.
         // Formular for the limit L:
         // Let n := timer_stop, P := TRB_BITS, N := 2**timer_stop'length
         // L = n/N * P - 1
         hist_count = (conf.trg_delay * TRB_DEPTH) / 2**(TRB_DELAY_BITS-1) -1;
         stat.trg_event = 0;
      end
      else begin
         if (write && RW_TURN_I) begin
            if (hist_count > 0) begin
               hist_count = hist_count - 1;
               stat.trg_event = 0;
            end
            else begin
               stat.trg_event = 1;
            end
         end
      end // else: !if(!RST_NI || !TRB_EVENT_I)
   end // always_ff @ (posedge CLK_I)


   // -----------------------------------------------------------------------------
   // --- RW to memory ---
   // -----------------------------------------------------------------------------

   // Memory read pointer.
   bit [$clog2(TRB_DEPTH)-1:0] read_ptr;
   assign READ_PTR_O = read_ptr;

   logic                       pending_write;

   logic                       read_valid;
   always_comb begin
      if( READ_ALLOW_I && (read_ptr +1)%TRB_DEPTH != write_ptr) begin
         read_valid = 1;
      end
      else begin
         read_valid = 0;
      end
   end

   // Writing becomes invalid if the next pointer value equals the read pointer or
   // the delayed trg_event is set.
   logic write_valid;
   assign STORE_PERM_O = write_valid;

   always_comb begin
      if (WRITE_ALLOW_I && write_ptr != read_ptr && !stat.trg_event) begin
         write_valid = 1;
      end
      else begin
         write_valid = 0;
      end
   end

   assign write = pending_write & RW_TURN_I;
   always_ff @(posedge CLK_I) begin : WRITE_PROC
      if (!RST_NI) begin
         pending_write <= 0;
         DMEM_O <= '0;
         write_ptr <= 0;
      end
      else begin
         if (write_valid) begin
            if (STORE_I) begin
               pending_write <= 1;
               DMEM_O <= DATA_I;
            end
            else begin
               if (pending_write && RW_TURN_I) begin
                  pending_write <= 0;
                  write_ptr <= (write_ptr + 1) % TRB_DEPTH;
               end
            end
         end
      end
   end

   logic pending_read;
   always_ff @(posedge CLK_I) begin : READ_PROC
      if (!RST_NI) begin
         pending_read <= 0;
         DATA_O <= '0;
         LOAD_GRANT_O <= 0;
         read_ptr <= 1;
      end
      else begin
         LOAD_GRANT_O <= 0;
         if (read_valid) begin
            if (LOAD_REQUEST_I) begin
               pending_read <= 1;
            end
            if (pending_read && RW_TURN_I) begin
               pending_read <= 0;
               DATA_O <= DMEM_I;
               LOAD_GRANT_O <= 1;
               read_ptr <= (read_ptr + 1) % TRB_DEPTH;
            end
         end
      end
   end

endmodule // TraceLogger
