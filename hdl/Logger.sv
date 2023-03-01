//                -*- Mode: SystemVerilog -*-
  // Filename        : Logger.sv
  // Description     : Module handling saving the trace to memory.
  // Author          : Stephan Proß
  // Created On      : Thu Dec  1 13:37:07 2022
  // Last Modified By: Stephan Proß
  // Last Modified On: Thu Dec  1 13:37:07 2022
  // Update Count    : 0
  // Status          : Unknown, Use with caution!

`include "../lib/STB_PKG.svh"

module Logger (
               // --- Interface Ports ---
               input logic                         CLK_I,
               input logic                         RST_NI,

               input logic [TRB_CONTROL_BITS-1:0]  CONTROL_I,
               output logic [TRB_STATUS_BITS-1:0]  STATUS_O,

               // Read & Write strobe. Indicates that a write operation
               // can be performed in the current cycle.
               input logic                         RW_TURN_I,
               // Signal write intend to memory.
               output logic                        WRITE_O,
               // Signals to indicate whether reading/writing is possible.
               input logic                         WRITE_ALLOW_I,
               input logic                         READ_ALLOW_I,

               // Read&Write Pointers with associated data ports.
               output logic [TRB_ADDR_WIDTH-1:0]   READ_PTR_O,
               input logic [TRB_WIDTH-1:0]         DMEM_I,

               output logic [TRB_ADDR_WIDTH-1:0]   WRITE_PTR_O,
               output logic [TRB_WIDTH-1:0]        DMEM_O,

               // --- To Tracer ----
               // Signals passed into the tracer (potentially through CDC).

               // Config & Status exchange
               // Mode bit switches from trace-buffer to data-streaming mode.
               output logic [1:0]                  MODE_O,
               // Number of traces captured in parallel.
               output bit [TRB_NTRACE_BITS-1:0]    NTRACE_O,


               // Outgoing signals to the system interface.
               // Position of the event in the word width of the memory.
               input logic [$clog2(TRB_WIDTH)-1:0] EVENT_POS_I,
               // Indicates presence of trigger event.
               input logic                         TRG_EVENT_I,
               // Signal denoting, whether event has occured and delay
               // timer has run out.
               output logic                        TRG_DELAYED_O,

               // Data from memory.
               output logic [TRB_WIDTH-1:0]        DATA_O,
               // Tracer request of new data from memory.
               input logic                         LOAD_REQUEST_I,
               // Signal to Tracer that read has been granted.
               output logic                        LOAD_GRANT_O,

               // Trace exchange
               // Trace register to be stored in memory.
               input logic [TRB_WIDTH-1:0]         DATA_I,
               // Load signal triggering capture of data from Tracer.
               input logic                         STORE_I,
               // Signal to determine whether writing the trace is currently permissible.
               output logic                        STORE_PERM_O
               );


   // Forwarding of relevant config fields to Tracer
   control_t control;
   assign control = CONTROL_I;

   assign MODE_O = control.trg_mode;
   assign NTRACE_O = control.trg_num_traces;

   // Forwarding of status to Interface.
   status_t status;
   assign status.zero = '0;

   assign STATUS_O = status;
   assign status.event_pos = EVENT_POS_I;
   assign TRG_DELAYED_O = status.trg_event;

   // -----------------------------------------------------------------------------
   // --- (Pre-)Trigger Event Handling ---
   // -----------------------------------------------------------------------------

   // // Address on which TRG_EVENT_I flipped from 0 to 1.
   // bit [TRB_ADDR_WIDTH-1:0]                        event_address;
   // assign status.event_addr = event_address;

   // Memory write pointer
   bit [TRB_ADDR_WIDTH-1:0]                        write_ptr;
   assign WRITE_PTR_O = write_ptr;
   // Registered (sticky) trg_event.
   logic                                           trg_event;
   always_ff @(posedge CLK_I) begin : STICKY_TRG_EVENT_ADDRESS
      if (!RST_NI) begin
         trg_event <= 0;
         // event_address <= '0;
      end
      else if (TRG_EVENT_I == 1 && trg_event == 0) begin
         // Save on which address the trigger has been registered.
         // event_address <= write_ptr;
         trg_event <= 1;
      end
   end

   // Counter for determining the ratio of history to pre-history.
   bit [TRB_ADDR_WIDTH-1:0] hist_count;

   // Write signal.
   logic                    write;
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
         // Let n := control.trg_delay, P := TRB_DEPTH, N := max(control.trg_delay)
         // L = n/N * (P-1)
         hist_count <= ((control.trg_delay) * (TRB_DEPTH-1)) / (2**TRB_DELAY_BITS-1);
         status.trg_event <= 0;
      end
      else begin
         if (write && RW_TURN_I) begin
            if (hist_count > 0) begin
               hist_count <= hist_count - 1;
               status.trg_event <= 0;
            end
            else begin
               status.trg_event <= 1;
            end
         end
      end // else: !if(!RST_NI || !TRB_EVENT_I)
   end // always_ff @ (posedge CLK_I)


   // -----------------------------------------------------------------------------
   // --- RW to memory ---
   // -----------------------------------------------------------------------------

   // Memory read pointer.
   bit [TRB_ADDR_WIDTH-1:0] read_ptr;
   assign READ_PTR_O = read_ptr;

   logic                    pending_write;

   logic                    read_valid;
   always_comb begin
      read_valid = 0;
      if (READ_ALLOW_I) begin
         if (control.trg_mode == w_stream_mode ) begin
            read_valid = 1;
         end
         else begin
            if ((read_ptr+1) % TRB_DEPTH != write_ptr) begin
               read_valid = 1;
            end
         end
      end
   end

   // Writing becomes invalid if the next pointer value equals the read pointer or
   // the delayed trg_event is set.
   logic                    write_valid;
   assign STORE_PERM_O = write_valid;
   // Writing is possible if the MemoryController allows writes,
   // the write_ptr is not equal to the read_ptr (ignored if in
   // Trace-Mode) and the delayed trigger event hasn't fired yet.
   logic                    ignore_pointer_collision;

   // In either trace or r-stream mode, correct output of memory through
   // the tracer is not the priority.
   assign ignore_pointer_collision = control.trg_mode == trace_mode
                                     || control.trg_mode == r_stream_mode;

   // Writing is valid so long the MemoryController allows it.
   // Further conditions are tied to mode of operation:
   //  - Writing is disabled if the delayed trg_event has fired in
   //    only in Trace-Mode.
   //  - Pointer collision of logger internal pointers are only relevant
   //    when in RW-Streaming mode.
   always_comb begin
      write_valid = 0;
      if (WRITE_ALLOW_I) begin
         if (control.trg_mode == trace_mode) begin
            //In Trace mode, block writing after delayed trigger event.
            if (!status.trg_event) begin
               write_valid = 1;
            end
         end
         else if (control.trg_mode == rw_stream_mode) begin
            //Logger pointer collisions only relevant in rw-mode
            if (write_ptr != read_ptr) begin
               write_valid = 1;
            end
         end
         else if (control.trg_mode == r_stream_mode) begin
            //Pointer collision irrelevant.
            write_valid = 1;
         end
      end
   end


   assign write = pending_write & RW_TURN_I & write_valid;
   always_ff @(posedge CLK_I) begin : WRITE_PROC
      if (!RST_NI) begin
         pending_write <= 0;
         DMEM_O <= '0;
         if(control.trg_mode == trace_mode) begin
            // In Trace Mode, the write pointer is placed behind the
            // read pointer.
            write_ptr <= 0;
         end
         else begin
            // In Streaming Mode, the write pointer is placed in the
            // middle of memory, one address after read ptr of memory
            // controller.
            write_ptr <= TRB_DEPTH/2 - 1;
         end
      end
      else begin
         if (STORE_I) begin
            pending_write <= 1;
            DMEM_O <= DATA_I;
         end
         if (write_valid) begin
            if (pending_write && RW_TURN_I) begin
               pending_write <= 0;
               write_ptr <= (write_ptr + 1) % TRB_DEPTH;
            end
         end
      end
   end

   logic pending_read, finished_read;
   always_ff @(posedge CLK_I) begin : READ_PROC
      if (!RST_NI) begin
         pending_read <= 0;
         finished_read <= 0;
         if(control.trg_mode == trace_mode) begin
            // In Trace Mode, the write pointer is placed behind the
            // read pointer.
            read_ptr <= 1;
         end
         else begin
            // In Streaming Mode, the read pointer is behind.
            read_ptr <= 0;
         end
      end
      else begin
         if(!LOAD_REQUEST_I) begin
            finished_read <= 0;
         end
         if (LOAD_REQUEST_I && !finished_read) begin
            pending_read <= 1;
         end

         if (!finished_read && read_valid) begin
            if ((LOAD_REQUEST_I || pending_read) && !RW_TURN_I) begin
               pending_read <= 0;
               finished_read <= 1;
               read_ptr <= (read_ptr + 1) % TRB_DEPTH;
            end
         end
      end
   end
   always_comb begin : READ_DATA_OUT
      if(!RST_NI) begin
         DATA_O = '0;
         LOAD_GRANT_O = 0;
      end
      else begin
         LOAD_GRANT_O = 0;
         DATA_O = '0;
         if (!finished_read && read_valid) begin
            if ((LOAD_REQUEST_I || pending_read) && !RW_TURN_I) begin
               DATA_O = DMEM_I;
               LOAD_GRANT_O = 1;
            end
         end
      end
   end




endmodule // Logger
