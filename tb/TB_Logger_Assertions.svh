//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_TraceLogger_assertions.sv
// Description     : Assertions for the TraceLogger module.
// Author          : Stephan Proß
// Created On      : Tue Dec 27 16:32:31 2022
// Last Modified By: Stephan Proß
// Last Modified On: Tue Dec 27 16:32:31 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


property outputs_after_reset_prop;
   @(posedge clk)
     (!reset_n) |-> ##1
       stat == STATUS_DEFAULT &&
             write == 0 &&
             dword_out == '0 &&
             data_out == '0 &&
             load_grant == 0;
endproperty // outputs_after_reset_prop
assert property(outputs_after_reset_prop)
  else
    $error("%m Output signals did not reset to correct values");


property store_permission_valid_prop;
   // Assert that the store is permitted under the right circumstances.
   @(posedge clk) disable iff(!reset_n)
     (write_allow &&
      (write_ptr + 1) % TRB_DEPTH != read_ptr &&
      !trg_delayed) |-> store_perm == 1;
endproperty // store_permission_valid_prop
assert property(store_permission_valid_prop)
  else
    $error ("%m Store permission expected");

property store_permission_invalid_prop;
   @(posedge clk) disable iff(!reset_n)
     (!write_allow ||
      (write_ptr + 1) % TRB_DEPTH == read_ptr ||
      trg_delayed) |-> !store_perm;
endproperty // store_permission_invalid_prop
assert property(store_permission_invalid_prop)
  else
    $error ("%m unexpected store permission");

logic assert_pending_read;
logic assert_successful_read;
logic [TRB_WIDTH-1:0] assert_read_value;

always_ff @(posedge clk) begin : load_to_tracer_assert
   if (!reset_n) begin
      assert_pending_read <= 0;
      assert_successful_read <= 0;
      assert_read_value <= '0;
   end
   else begin
      if (load_request) begin
         assert_pending_read <= 1;
      end
      if (!assert_successful_read) begin
         assert(!load_grant)
           else
             $error("%m unexpected load grant.");
      end
      if (assert_pending_read) begin
         if(!rw_turn && read_allow && (read_ptr+1)%TRB_DEPTH != write_ptr) begin
            assert_successful_read <= 1;
            assert_read_value <= dword_in;
         end
         if(assert_successful_read) begin
            assert(load_grant)
              else
                $error("%m expected load grant");
            assert(assert_read_value == data_out)
              else
                $error("%m incorrect data to tracer. Expected %8h, got %8h",assert_read_value, data_out);
            assert_pending_read <= load_request;
            assert_successful_read <= 0;
         end
      end
   end
end

logic assert_pending_write;
logic assert_successful_write;
logic [TRB_WIDTH-1:0] assert_write_value;

always_ff @(posedge clk) begin : store_to_memory_assert
   if (!reset_n) begin
      assert_pending_write <= 0;
      assert_successful_write <= 0;
      assert_write_value <= '0;
   end
   else begin
      if (store) begin
         assert_pending_write <= 1;
         assert_write_value <= data_in;
         assert(!write)
           else
             $error ("%m unexpected write.");
      end
      else begin
         if (assert_pending_write) begin
            if(rw_turn && write_allow && write_ptr != read_ptr && !stat.trg_event) begin
               assert(write)
                 else
                   $error ("%m write operation did not occur on next rw_turn.");
               assert(assert_write_value == dword_out)
                 else
                   $error("%m incorrect data to memory. Expected %8h, got %8h",assert_write_value, dword_out);
               assert_pending_write <= 0;
            end
            else begin
               assert(!write)
                 else
                   $error ("%m unexpected write.");
            end
         end
      end
   end
end

property write_pointer_increment_prop;
   // Make sure that the write pointer is always incremented after a write operation.
   @(posedge clk) disable iff(!reset_n || trg_delayed || !write_allow)
     (write) |-> ##1
       write_ptr == ($past(write_ptr) + 1) % TRB_DEPTH;
endproperty // write_pointer_increment_prop
assert property(write_pointer_increment_prop)
  else
    $error ("%m Write pointer did not increment after write operation");

int assert_delay;
logic assert_trg_event;
always_ff @(posedge clk) begin : trg_delay_assert_proc
   if (!reset_n) begin
      assert_trg_event <= 0;
   end
   else begin
      if (! trg_event) begin
         assert_delay <= 1 + ((conf.trg_delay+1)*(TRB_DEPTH-1))/ (2**TRB_DELAY_BITS);
         assert (!trg_delayed)
           else
             $error("%m unexpected trg_delayed");
      end
      else begin
         assert_trg_event <= 1;
      end
      if (assert_trg_event == 1) begin
         if (assert_delay > 0) begin
            if(write && rw_turn) begin
               assert_delay <= assert_delay - 1;
            end
            assert (!trg_delayed)
              else
                $error("%m unexpected trg_delayed");
         end
         else begin
            assert (trg_delayed)
              else
                $error("%m trg_delayed expected");
         end
      end
   end
end
