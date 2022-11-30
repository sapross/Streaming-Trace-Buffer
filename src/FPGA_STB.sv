//                              -*- Mode: SystemVerilog -*-
// Filename        : FPGA_STB.sv
// Description     : FPGA facing side of Data Trace Buffer
// Author          : Stephan Proß
// Created On      : Thu Nov 24 13:09:49 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Nov 24 13:09:49 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!
import DTB_PKG::*;

module FPGA_STB (
                 input logic [$bits(config_t)-1:0]    CONFIG_I,
                 output logic [$bits(status_t)-1:0]   STATUS_O,
                 output logic [$clog2(TRB_DEPTH)-1:0] READ_ADDR_O,
                 output logic [$clog2(TRB_DEPTH)-1:0] WRITE_ADDR_O,

                 output logic                         WE_O,
                 input logic [TRB_WIDTH-1:0]                    DATA_I,
                 output logic [TRB_WIDTH-1:0]                   DATA_O,

                 input logic                          FPGA_CLK_I,
                 input logic                          FPGA_TRIG_I,
                 input logic                          FPGA_TRACE_I,
                 output logic                         FPGA_TRACE_O,
                 output logic                         FPGA_TRIG_O
                 );

   typedef enum {
                 st_idle,
                 st_wait_for_trigger,
                 st_capture_trace,
                 st_rwmode,
                 st_done
                 } state_t;
   state_t state, state_next;


   localparam integer unsigned low_bits = $clog2(TRB_WIDTH);
   localparam integer unsigned high_bits = $clog2(TRB_DEPTH);

   // Low address i.e. bit position of trigger.
   bit [low_bits-1: 0]         laddr, laddr_next;

   // High address i.e. address of the word containing the trigger.
   bit [high_bits-1:0]         haddr, haddr_next;
   bit [high_bits-1:0]         haddr_prev;

   assign READ_ADDR_O = haddr;
   assign WRITE_ADDR_O = haddr_prev;

   logic                       we, we_next;
   assign WE_O = we;

   logic [TRB_WIDTH-1:0]                       dword, dword_next;
   assign DATA_O = dword;


   // Counter for the number of bits processed after the trigger event.
   bit [$clog2(TRB_BITS)-1:0]  bit_counter, bit_counter_next;

   // Status register containing information regarding trigger.
   status_t stat, stat_next;
   assign STATUS_O = stat;

   // Config register
   config_t conf;
   always_ff @(posedge FPGA_CLK_I) begin : CONF_UPDATE
      conf <= CONFIG_I;
   end

   // Trace Register storing intermediate trace until a full data word for the
   // memory interface is collected.
   logic [TRB_WIDTH-1:0] trace, trace_next;
   assign FPGA_TRACE_O = trace[laddr];

  
   // Internal signal denoting, whether data streamed out of the TRACE_O line
   // is valid.
   logic                 ser_valid, ser_valid_next;

   // Controls value of TRIG_O line dependent on trg_mode.
   // In Trace-Buffer-Mode, TRIG_O is set high if both the trigger event has
   // been met and the bit_counter has run out.
   // In Streaming-Mode, TRIG_O indicates, whether TRACE_O line holds valid data.
   always_comb begin : FPGA_TRIGGER_OUTPUT
      if (conf.trg_mode) begin
         // With trg_mode = 1 TRIG_O becomes a valid signal.
         // Output of TRACE_O is safe to read so long as we haven't read all
         // the data (~trg_event) and serial_data is valid.
         FPGA_TRIG_O = ~stat.trg_event & ser_valid;
      end
      else begin
         // With trg_mode = 0 TRIG_O is simply the whether or not the trigger
         // condition has been met and the timer has run out.
         FPGA_TRIG_O = stat.trg_event;
      end
   end

   // Function for calculating the maximum bit_counter value.
   // The config trg_delay controls the ratio values before and after the
   // trigger event i.e.:
   // trg_delay = 111 : (Almost) all trace data is from directly after the trigger event.
   // trg_delay = 100 : Half the trace data if before and after the event (centered).
   // trg_delay = 000 : Entire trace contains data leading up to trace event.
   function automatic integer unsigned get_limit(config_t conf_i);
      // Formular for the limit L:
      // Let n := timer_stop, P := TRB_BITS, N := 2**timer_stop'length
      // L = n/N * P - 1
      // Example: Trace Buffer can hold 64 bits (P = 64), trg_delay is 3
      // bits (N = 8 => 0<n<8) and timer_stop is set to "011" (n=3):
      // L = 3/8 * 64 - 1 = 23
      return (conf_i.trg_delay + 1) * TRB_BITS / (2**$size(conf_i.trg_delay) - 1);
   endfunction // get_limit



   always_ff @(posedge FPGA_CLK_I) begin : FSM_CORE
      if (conf.trg_reset) begin
         state <= st_idle;
         stat <= STATUS_DEFAULT;
         laddr <= 0;
         haddr <= 0;
         haddr_prev <= TRB_DEPTH-1;

         bit_counter <= 0;
         trace <= '0;

         we <= 0;
         ser_valid <= 0;
         dword <= '0;

      end
      else begin
         if (conf.trg_enable) begin
            state <= state_next;
            stat <= stat_next;
            laddr <= laddr_next;
            haddr_prev <= haddr;
            haddr <= haddr_next;

            bit_counter <= bit_counter_next;
            trace <= trace_next;

            we <= we_next;
            ser_valid <= ser_valid_next;
            dword <= dword_next;
         end
      end // else: !if(conf.trg_reset)
   end // block: FSM_CORE

   always_comb begin : FSM
      if (conf.trg_reset) begin
         state_next = st_idle;
         stat_next = STATUS_DEFAULT;
      end
      else begin
         ser_valid_next = 0;
         state_next = state;
         stat_next = stat;

         case (state)

           st_idle: begin
              // Decide which mode to enter.
              if (conf.trg_mode == 0) begin
                 state_next = st_wait_for_trigger;
              end
              else begin
                 state_next = st_rwmode;
              end
           end // case: st_idle

           st_wait_for_trigger: begin
              // Has the trigger event occured?
              if (FPGA_TRIG_I == 1) begin
                 // Transition into caputure state.
                 state_next = st_capture_trace;
                 // Initialize bit_counter
                 bit_counter_next = get_limit(conf);
                 // Save next laddr and current haddr in status for host to evaluate.
                 stat_next.event_pos = laddr_next;
                 stat_next.event_addr = haddr;
              end
           end // case: st_wait_for_trigger

           st_capture_trace: begin
              if (0 < bit_counter) begin
                 bit_counter_next <= bit_counter - 1;
              end
              else begin
                 state_next = st_done;
                 stat_next.trg_event = 1;
              end
           end // case: st_capture_trace

           st_rwmode: begin
              // TODO Read-Write mode for full streaming.
              ser_valid_next = 1;
              stat_next.event_pos = 0;
              stat_next.event_addr = haddr;

           end
           st_done: begin
              state_next <= st_done;
           end
         endcase // case (state)
      end // else: !if(conf.trg_reset)
end // block: FSM


   always_comb begin : TRACE_PROCESS

      if (conf.trg_reset) begin
         trace_next = '0;
         laddr_next = 0;
         haddr_next = 0;
         dword_next = '0;
      end
      else begin
         we_next  = 0;
         trace_next = trace;
         laddr_next = laddr;
         haddr_next = haddr;
         dword_next = dword;

         if (state == st_idle) begin
            // Reset addresses
            trace_next = '0;
            laddr_next = 0;
            haddr_next = 0;
            dword_next = '0;
         end
         else if (state != st_done) begin

            laddr_next <= (laddr + 1) % TRB_WIDTH;

            // laddr overflow on next posedge?
            if (laddr == TRB_WIDTH - 1) begin
               // Increment haddr.
               haddr_next = (haddr + 1) % TRB_DEPTH;
               // Write trace to memory.
               we_next <= 1;
               // Trace register exchanges data with memory.
               dword_next <= {FPGA_TRACE_I, trace[TRB_WIDTH-2:0]};
               trace_next = DATA_I;
            end
            // "Shift" new values into trace register.
            trace_next[laddr] = FPGA_TRACE_I;
         end
      end
end




endmodule // FPGA_STB
